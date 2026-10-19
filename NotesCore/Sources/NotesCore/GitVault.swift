import Foundation
import libgit2

public struct FileChange: Equatable, Sendable {
    public enum Kind: Sendable { case added, modified, deleted }
    public let path: String
    public let kind: Kind

    public init(path: String, kind: Kind) {
        self.path = path
        self.kind = kind
    }
}

public struct GitError: Error, CustomStringConvertible, Equatable {
    public let code: Int32
    public let message: String
    public var description: String { "git: \(message) (\(code))" }
}

// libgit2 возвращает отрицательный код при ошибке, а текст кладёт в «последнюю ошибку» потока.
@discardableResult
func check(_ code: Int32) throws -> Int32 {
    guard code < 0 else { return code }
    let message = git_error_last().map { String(cString: $0.pointee.message) } ?? "неизвестная ошибка"
    throw GitError(code: code, message: message)
}

// libgit2 нужно один раз инициализировать на процесс.
private let libgit2Ready: Void = { git_libgit2_init() }()
func gitReady() { _ = libgit2Ready }

// Git-репозиторий в папке хранилища: создать, закоммитить всё изменённое, отправить на сервер.
//
// Обёртки над libgit2 вроде SwiftGitX не берём: им не хватает init с веткой main и push с токеном,
// а нам нужны ровно эти вещи. Поэтому напрямую через C API — его немного.
public final class GitVault {
    public static let defaultBranch = "main"
    // Автор коммитов. Пишем в .git/config самого репозитория: глобальный конфиг git пользователя
    // не читаем и не трогаем (CLAUDE.md).
    public static let authorName = "notes"
    public static let authorEmail = "notes@local"
    public static let initialMessage = "начало истории"

    // Что не попадает в историю: служебное Obsidian и macOS, тяжёлые медиа для расшифровки видео.
    public static let gitignore = """
    # создано <notes>
    .DS_Store
    .obsidian/workspace*.json
    .trash/
    *.mp4
    *.mov
    *.m4a
    *.mp3
    *.wav

    """

    public let folder: URL
    let repo: OpaquePointer

    init(repo: OpaquePointer, folder: URL) {
        self.repo = repo
        self.folder = folder
    }

    deinit { git_repository_free(repo) }

    public static func isRepository(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path)
    }

    // Открывает репозиторий в папке или создаёт новый с первым коммитом.
    // created = false — папка уже была репозиторием, его историю не трогаем (CONTEXT.md).
    public static func prepare(at folder: URL) throws -> (vault: GitVault, created: Bool) {
        _ = libgit2Ready
        if isRepository(folder) {
            var pointer: OpaquePointer?
            try check(git_repository_open(&pointer, folder.path))
            return (GitVault(repo: pointer!, folder: folder), false)
        }

        var options = git_repository_init_options()
        try check(git_repository_init_options_init(&options, UInt32(GIT_REPOSITORY_INIT_OPTIONS_VERSION)))
        options.flags = GIT_REPOSITORY_INIT_MKPATH.rawValue
        var pointer: OpaquePointer?
        // Ветка main сразу: libgit2 по умолчанию создаёт master.
        try defaultBranch.withCString { head in
            options.initial_head = head
            try check(git_repository_init_ext(&pointer, folder.path, &options))
        }
        let vault = GitVault(repo: pointer!, folder: folder)
        try vault.writeLocalAuthor()

        // Чужие файлы не трогаем: если .gitignore уже есть, оставляем как был.
        let ignore = folder.appendingPathComponent(".gitignore")
        if !FileManager.default.fileExists(atPath: ignore.path) {
            try gitignore.write(to: ignore, atomically: true, encoding: .utf8)
        }
        try vault.commitAll(message: initialMessage)
        return (vault, true)
    }

    func writeLocalAuthor() throws {
        var config: OpaquePointer?
        try check(git_repository_config(&config, repo))
        defer { git_config_free(config) }
        try check(git_config_set_string(config, "user.name", Self.authorName))
        try check(git_config_set_string(config, "user.email", Self.authorEmail))
    }

    // Коммитит всё изменённое, новое и удалённое. false — менять было нечего, коммит не создан.
    @discardableResult
    public func commitAll(message: String) throws -> Bool {
        var index: OpaquePointer?
        try check(git_repository_index(&index, repo))
        defer { git_index_free(index) }

        // Как `git add -A`: новые и изменённые файлы попадают в индекс, удалённые из него уходят,
        // игнорируемые из .gitignore пропускаются.
        try withPathspec(["*"]) { pathspec in
            try check(git_index_add_all(index, pathspec, GIT_INDEX_ADD_DEFAULT.rawValue, nil, nil))
        }
        try check(git_index_write(index))

        var treeID = git_oid()
        try check(git_index_write_tree(&treeID, index))
        var tree: OpaquePointer?
        try check(git_tree_lookup(&tree, repo, &treeID))
        defer { git_tree_free(tree) }

        var parent: OpaquePointer?
        var headID = git_oid()
        if git_reference_name_to_id(&headID, repo, "HEAD") == 0 {
            try check(git_commit_lookup(&parent, repo, &headID))
        }
        defer { if let parent { git_commit_free(parent) } }

        // Дерево совпадает с прошлым коммитом — изменений нет, пустых коммитов не плодим.
        if let parent, git_oid_equal(git_commit_tree_id(parent), &treeID) == 1 {
            return false
        }

        var signature: UnsafeMutablePointer<git_signature>?
        try check(git_signature_now(&signature, Self.authorName, Self.authorEmail))
        defer { git_signature_free(signature) }

        var commitID = git_oid()
        var parents: [OpaquePointer?] = parent.map { [$0] } ?? []
        _ = try parents.withUnsafeMutableBufferPointer { buffer in
            try check(git_commit_create(&commitID, repo, "HEAD", signature, signature, nil, message,
                                        tree, buffer.count, buffer.baseAddress))
        }
        return true
    }

    // Открывает уже существующий репозиторий. В отличие от prepare ничего не создаёт.
    public static func open(at folder: URL) throws -> GitVault {
        _ = libgit2Ready
        var pointer: OpaquePointer?
        try check(git_repository_open(&pointer, folder.path))
        return GitVault(repo: pointer!, folder: folder)
    }

    // Новые, изменённые и удалённые файлы (пути от корня хранилища) — без игнорируемых.
    // Нужны для подписи коммита.
    public func changes() throws -> [FileChange] {
        var options = git_status_options()
        try check(git_status_options_init(&options, UInt32(GIT_STATUS_OPTIONS_VERSION)))
        options.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR
        options.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue | GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.rawValue
        var list: OpaquePointer?
        try check(git_status_list_new(&list, repo, &options))
        defer { git_status_list_free(list) }

        let added = GIT_STATUS_WT_NEW.rawValue | GIT_STATUS_INDEX_NEW.rawValue
        let deleted = GIT_STATUS_WT_DELETED.rawValue | GIT_STATUS_INDEX_DELETED.rawValue
        var result: [FileChange] = []
        for i in 0..<git_status_list_entrycount(list) {
            guard let entry = git_status_byindex(list, i)?.pointee,
                  let delta = entry.index_to_workdir ?? entry.head_to_index,
                  let file = delta.pointee.new_file.path ?? delta.pointee.old_file.path
            else { continue }
            let flags = entry.status.rawValue
            let kind: FileChange.Kind = flags & added != 0 ? .added : flags & deleted != 0 ? .deleted : .modified
            result.append(FileChange(path: String(cString: file), kind: kind))
        }
        return result.sorted { $0.path < $1.path }
    }

    // Есть ли коммиты, которых ещё нет на сервере (сравниваем ветку с её копией origin/<ветка>).
    public var hasUnpushedCommits: Bool {
        guard let branch = headReference, branch.hasPrefix("refs/heads/") else { return false }
        var local = git_oid()
        guard git_reference_name_to_id(&local, repo, "HEAD") == 0 else { return false }
        let tracking = "refs/remotes/origin/" + branch.dropFirst("refs/heads/".count)
        var remote = git_oid()
        // Ветки на сервере ещё нет — значит, ничего не отправляли.
        guard git_reference_name_to_id(&remote, repo, tracking) == 0 else { return true }
        return git_oid_equal(&local, &remote) == 0
    }

    public var commitCount: Int {
        var walker: OpaquePointer?
        guard git_revwalk_new(&walker, repo) == 0 else { return 0 }
        defer { git_revwalk_free(walker) }
        guard git_revwalk_push_head(walker) == 0 else { return 0 }
        var id = git_oid()
        var count = 0
        while git_revwalk_next(&id, walker) == 0 { count += 1 }
        return count
    }

    // Полное имя текущей ветки, например refs/heads/main.
    public var headReference: String? {
        var ref: OpaquePointer?
        guard git_repository_head(&ref, repo) == 0 else { return nil }
        defer { git_reference_free(ref) }
        return String(cString: git_reference_name(ref))
    }

    public func setRemote(_ url: String, name: String = "origin") throws {
        var remote: OpaquePointer?
        if git_remote_lookup(&remote, repo, name) == 0 {
            git_remote_free(remote)
            try check(git_remote_set_url(repo, name, url))
        } else {
            try check(git_remote_create(&remote, repo, name, url))
            git_remote_free(remote)
        }
    }

    public func remoteURL(name: String = "origin") -> String? {
        var remote: OpaquePointer?
        guard git_remote_lookup(&remote, repo, name) == 0 else { return nil }
        defer { git_remote_free(remote) }
        return git_remote_url(remote).map { String(cString: $0) }
    }

    // Отправляет текущую ветку на сервер. Токен GitHub уходит паролем по HTTPS и нигде не сохраняется:
    // в URL репозитория его не пишем, иначе он окажется в .git/config внутри хранилища.
    public func push(token: String?, remote name: String = "origin") throws {
        guard let branch = headReference else {
            throw GitError(code: -1, message: "в репозитории ещё нет коммитов")
        }
        var remote: OpaquePointer?
        try check(git_remote_lookup(&remote, repo, name))
        defer { git_remote_free(remote) }

        var options = git_push_options()
        try check(git_push_options_init(&options, UInt32(GIT_PUSH_OPTIONS_VERSION)))
        try withAuth(token) { callbacks in
            options.callbacks = callbacks
            try withPathspec(["\(branch):\(branch)"]) { refspecs in
                try check(git_remote_push(remote, refspecs, &options))
            }
        }
    }
}

// Колбэки сети libgit2 с токеном GitHub: токен уходит паролем по HTTPS и живёт только на время вызова.
// C-колбэк не может захватывать переменные, поэтому токен передаём через payload.
func withAuth<T>(_ token: String?, _ body: (git_remote_callbacks) throws -> T) throws -> T {
    var callbacks = git_remote_callbacks()
    try check(git_remote_init_callbacks(&callbacks, UInt32(GIT_REMOTE_CALLBACKS_VERSION)))
    let box = Unmanaged.passRetained(TokenBox(token))
    defer { box.release() }
    callbacks.payload = box.toOpaque()
    callbacks.credentials = { out, _, _, _, payload in
        guard let payload,
              let token = Unmanaged<TokenBox>.fromOpaque(payload).takeUnretainedValue().value
        else { return -1 }
        return git_credential_userpass_plaintext_new(out, "x-access-token", token)
    }
    return try body(callbacks)
}
final class TokenBox {
    let value: String?
    init(_ value: String?) { self.value = value }
}

// git_strarray из Swift-строк на время вызова.
@discardableResult
func withPathspec<T>(_ items: [String], _ body: (UnsafePointer<git_strarray>) throws -> T) throws -> T {
    var pointers: [UnsafeMutablePointer<CChar>?] = items.map { strdup($0) }
    defer { pointers.forEach { free($0) } }
    return try pointers.withUnsafeMutableBufferPointer { buffer in
        var array = git_strarray(strings: buffer.baseAddress, count: buffer.count)
        return try body(&array)
    }
}

extension GitVault {
    // Пустой bare-репозиторий — как «сервер» на диске. Нужен тестам push без сети.
    static func prepareBare(at folder: URL) throws -> OpaquePointer {
        _ = libgit2Ready
        var options = git_repository_init_options()
        try check(git_repository_init_options_init(&options, UInt32(GIT_REPOSITORY_INIT_OPTIONS_VERSION)))
        options.flags = GIT_REPOSITORY_INIT_BARE.rawValue | GIT_REPOSITORY_INIT_MKPATH.rawValue
        var pointer: OpaquePointer?
        try defaultBranch.withCString { head in
            options.initial_head = head
            try check(git_repository_init_ext(&pointer, folder.path, &options))
        }
        return pointer!
    }
}
