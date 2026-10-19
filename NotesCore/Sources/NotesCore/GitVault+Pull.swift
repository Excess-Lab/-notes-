import Foundation
import libgit2

public enum PullResult: Equatable, Sendable {
    case upToDate
    case fastForwarded
    // conflicts — заметки, которые правили на обоих Маках по-разному. Рядом с каждой лежит копия
    // с другого Мака: «имя (конфликт дата).md».
    case merged(conflicts: [String])
}

extension GitVault {
    // Второй Мак: забрать хранилище с GitHub в пустую папку.
    public static func clone(from url: String, to folder: URL, token: String?) throws -> GitVault {
        gitReady()
        var options = git_clone_options()
        try check(git_clone_options_init(&options, UInt32(GIT_CLONE_OPTIONS_VERSION)))
        var pointer: OpaquePointer?
        // Ветку берём явно: у сервера HEAD может смотреть не туда (например, на пустой master),
        // и тогда клон вышел бы пустым.
        try withAuth(token) { callbacks in
            options.fetch_opts.callbacks = callbacks
            try defaultBranch.withCString { branch in
                options.checkout_branch = branch
                try check(git_clone(&pointer, url, folder.path, &options))
            }
        }
        let vault = GitVault(repo: pointer!, folder: folder)
        try vault.writeLocalAuthor()
        return vault
    }

    public func fetch(token: String?, remote name: String = "origin") throws {
        var remote: OpaquePointer?
        try check(git_remote_lookup(&remote, repo, name))
        defer { git_remote_free(remote) }
        var options = git_fetch_options()
        try check(git_fetch_options_init(&options, UInt32(GIT_FETCH_OPTIONS_VERSION)))
        try withAuth(token) { callbacks in
            options.callbacks = callbacks
            try check(git_remote_fetch(remote, nil, &options, nil))
        }
    }

    // Забирает правки с сервера и вливает в текущую ветку.
    //
    // Главное правило: текст не теряется никогда. Если одну заметку поменяли на двух Маках по-разному,
    // в файле остаётся версия этого Мака, а версия с другого ложится рядом отдельной копией. Удаление
    // против правки — побеждает правка: удалить ещё раз проще, чем восстанавливать.
    //
    // Перед вызовом незакоммиченных правок быть не должно (SyncEngine сначала коммитит).
    public func pull(token: String?, date: Date = Date()) throws -> PullResult {
        guard let branch = headReference, branch.hasPrefix("refs/heads/") else { return .upToDate }
        try fetch(token: token)

        var theirID = git_oid()
        let tracking = "refs/remotes/origin/" + branch.dropFirst("refs/heads/".count)
        // Ветки на сервере ещё нет — забирать нечего.
        guard git_reference_name_to_id(&theirID, repo, tracking) == 0 else { return .upToDate }

        var annotated: OpaquePointer?
        try check(git_annotated_commit_lookup(&annotated, repo, &theirID))
        defer { git_annotated_commit_free(annotated) }
        var analysis = git_merge_analysis_t(rawValue: 0)
        var preference = git_merge_preference_t(rawValue: 0)
        var heads: [OpaquePointer?] = [annotated]
        _ = try heads.withUnsafeMutableBufferPointer { buffer in
            try check(git_merge_analysis(&analysis, &preference, repo, buffer.baseAddress, 1))
        }

        if analysis.rawValue & GIT_MERGE_ANALYSIS_UP_TO_DATE.rawValue != 0 { return .upToDate }
        if analysis.rawValue & GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue != 0 {
            try fastForward(branch: branch, to: &theirID)
            return .fastForwarded
        }
        return try merge(theirs: &theirID, date: date)
    }

    // Здесь ничего не меняли, там есть новое — просто догоняем сервер.
    private func fastForward(branch: String, to id: inout git_oid) throws {
        var commit: OpaquePointer?
        try check(git_commit_lookup(&commit, repo, &id))
        defer { git_commit_free(commit) }
        try checkout(commit)
        var ref: OpaquePointer?
        try check(git_reference_lookup(&ref, repo, branch))
        defer { git_reference_free(ref) }
        var moved: OpaquePointer?
        try check(git_reference_set_target(&moved, ref, &id, "pull: fast-forward"))
        git_reference_free(moved)
    }

    // Правили и здесь, и там: сливаем, конфликты разводим по разным файлам, создаём коммит слияния.
    private func merge(theirs theirID: inout git_oid, date: Date) throws -> PullResult {
        var headID = git_oid()
        try check(git_reference_name_to_id(&headID, repo, "HEAD"))
        var ours: OpaquePointer?, theirs: OpaquePointer?
        try check(git_commit_lookup(&ours, repo, &headID))
        defer { git_commit_free(ours) }
        try check(git_commit_lookup(&theirs, repo, &theirID))
        defer { git_commit_free(theirs) }

        var options = git_merge_options()
        try check(git_merge_options_init(&options, UInt32(GIT_MERGE_OPTIONS_VERSION)))
        var index: OpaquePointer?
        try check(git_merge_commits(&index, repo, ours, theirs, &options))
        defer { git_index_free(index) }

        let conflicts = try resolveConflicts(in: index, date: date)

        var treeID = git_oid()
        try check(git_index_write_tree_to(&treeID, index, repo))
        var tree: OpaquePointer?
        try check(git_tree_lookup(&tree, repo, &treeID))
        defer { git_tree_free(tree) }

        // Сначала рабочая папка, потом коммит: так файлы на диске всегда совпадают с HEAD.
        try checkout(tree)

        var signature: UnsafeMutablePointer<git_signature>?
        try check(git_signature_now(&signature, Self.authorName, Self.authorEmail))
        defer { git_signature_free(signature) }
        let message = conflicts.isEmpty
            ? "слияние с другого мака"
            : "слияние с другого мака, конфликты: \(conflicts.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))"
        var commitID = git_oid()
        var parents: [OpaquePointer?] = [ours, theirs]
        _ = try parents.withUnsafeMutableBufferPointer { buffer in
            try check(git_commit_create(&commitID, repo, "HEAD", signature, signature, nil, message,
                                        tree, buffer.count, buffer.baseAddress))
        }
        return .merged(conflicts: conflicts)
    }

    private struct Conflict {
        var ours: git_index_entry?
        var theirs: git_index_entry?
        let path: String
    }

    // Разводит конфликты так, чтобы не потерять ни строчки. Возвращает пути заметок, у которых
    // появилась копия с другого Мака.
    private func resolveConflicts(in index: OpaquePointer?, date: Date) throws -> [String] {
        guard git_index_has_conflicts(index) == 1 else { return [] }

        // Сначала копируем всё из итератора: дальше индекс меняется, и указатели в него устаревают.
        var iterator: OpaquePointer?
        try check(git_index_conflict_iterator_new(&iterator, index))
        var found: [Conflict] = []
        var ancestor: UnsafePointer<git_index_entry>?, our: UnsafePointer<git_index_entry>?, their: UnsafePointer<git_index_entry>?
        while git_index_conflict_next(&ancestor, &our, &their, iterator) == 0 {
            let any = our ?? their ?? ancestor
            guard let path = any.map({ String(cString: $0.pointee.path) }) else { continue }
            found.append(Conflict(ours: our?.pointee, theirs: their?.pointee, path: path))
        }
        git_index_conflict_iterator_free(iterator)

        var copies: [String] = []
        for conflict in found {
            try check(git_index_conflict_remove(index, conflict.path))
            switch (conflict.ours, conflict.theirs) {
            case let (ours?, theirs?):
                // Правили на обоих: файл — наша версия, рядом — копия с другого Мака.
                try add(ours, at: conflict.path, to: index)
                try add(theirs, at: conflictCopyPath(for: conflict.path, date: date, in: index), to: index)
                copies.append(conflict.path)
            case let (ours?, nil):
                // Там удалили, здесь правили — оставляем правку.
                try add(ours, at: conflict.path, to: index)
            case let (nil, theirs?):
                // Здесь удалили, там правили — возвращаем их правку.
                try add(theirs, at: conflict.path, to: index)
            case (nil, nil):
                break
            }
        }
        return copies
    }

    private func add(_ entry: git_index_entry, at path: String, to index: OpaquePointer?) throws {
        var copy = entry
        copy.flags &= ~UInt16(0x3000)   // GIT_INDEX_ENTRY_STAGEMASK: из «конфликтной» стадии в обычную
        try path.withCString { pointer in
            copy.path = pointer
            try check(git_index_add(index, &copy))
        }
    }

    // «папка/план.md» → «папка/план (конфликт 2026-10-19).md», при повторе — «… 2», «… 3».
    func conflictCopyPath(for path: String, date: Date, in index: OpaquePointer?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        let ns = path as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        var number = 1
        while true {
            let suffix = number == 1 ? "" : " \(number)"
            let candidate = "\(stem) (конфликт \(day)\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
            if git_index_get_bypath(index, candidate, 0) == nil { return candidate }
            number += 1
        }
    }

    private func checkout(_ object: OpaquePointer?) throws {
        var options = git_checkout_options()
        try check(git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)))
        // SAFE: файлы, которые человек успел поменять после нашего коммита, не перезаписываем.
        options.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue
        try check(git_checkout_tree(repo, object, &options))
    }
}
