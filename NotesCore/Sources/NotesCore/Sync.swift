import Foundation

// Подпись автокоммита. В истории человек ищет глазами, что менялось, поэтому пишем имена заметок
// и что с ними случилось, а не «auto commit»:
//   «новая: идеи.md», «правки: план.md, идеи.md», «удалены: 5 файлов»,
//   «правки: план.md, +1 новая, −2 удалены» — когда всё вперемешку.
public enum CommitMessage {
    public static func make(for changes: [FileChange]) -> String {
        let added = names(changes, .added)
        let modified = names(changes, .modified)
        let deleted = names(changes, .deleted)

        // Всё одного вида — перечисляем имена (или число, если их много).
        for (list, one, many) in [(modified, "правка", "правки"), (added, "новая", "новые"), (deleted, "удалена", "удалены")]
        where list.count == changes.count && !list.isEmpty {
            let prefix = list.count == 1 ? one : many
            return list.count <= 3 ? "\(prefix): \(list.joined(separator: ", "))" : "\(prefix): \(list.count) \(files(list.count))"
        }
        if changes.isEmpty { return "правка" }

        // Вперемешку: изменённые по именам (до двух), новые и удалённые — числом.
        var parts: [String] = []
        if !modified.isEmpty {
            parts.append(modified.count <= 2 ? modified.joined(separator: ", ") : "\(modified.count) \(files(modified.count))")
        }
        if !added.isEmpty { parts.append("+\(added.count) \(plural(added.count, "новая", "новые", "новых"))") }
        if !deleted.isEmpty { parts.append("−\(deleted.count) \(plural(deleted.count, "удалена", "удалены", "удалено"))") }
        return "правки: " + parts.joined(separator: ", ")
    }

    private static func names(_ changes: [FileChange], _ kind: FileChange.Kind) -> [String] {
        changes.filter { $0.kind == kind }.map { ($0.path as NSString).lastPathComponent }
    }

    static func files(_ n: Int) -> String { plural(n, "файл", "файла", "файлов") }

    // Русское склонение по числу: 1 файл, 2 файла, 5 файлов, 11 файлов, 21 файл.
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let tail = n % 100
        if (11...14).contains(tail) { return many }
        switch n % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}

// Отправка на GitHub раз в день (так в макете «гитхаб кул (5)»): коммиты частые и локальные,
// а на сервер уходят пачкой.
public enum PushSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func isDue(lastPush: Date?, now: Date = Date()) -> Bool {
        guard let lastPush else { return true }
        return now.timeIntervalSince(lastPush) >= interval
    }
}

// Синхронизация хранилища: коммит накопившихся правок и отправка на GitHub.
// Как часто — решает тот, кто вызывает (SyncController: коммит раз в час, отправка раз в сутки).
// actor — чтобы коммит и push никогда не шли одновременно: libgit2 не любит параллельную работу
// с одним репозиторием.
public actor SyncEngine {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    // Коммитит всё изменённое. nil — менять было нечего.
    @discardableResult
    public func commitNow() throws -> String? {
        let vault = try GitVault.open(at: folder)
        let changes = try vault.changes()
        guard !changes.isEmpty else { return nil }
        let message = CommitMessage.make(for: changes)
        return try vault.commitAll(message: message) ? message : nil
    }

    // Отправляет историю, если пора и есть что отправлять. true — отправили.
    public func pushIfDue(token: String?, lastPush: Date?, now: Date = Date()) throws -> Bool {
        guard PushSchedule.isDue(lastPush: lastPush, now: now) else { return false }
        let vault = try GitVault.open(at: folder)
        guard vault.remoteURL() != nil, vault.hasUnpushedCommits else { return false }
        try vault.push(token: token)
        return true
    }
}
