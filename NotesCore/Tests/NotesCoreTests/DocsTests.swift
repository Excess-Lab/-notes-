import Foundation
import Testing

// Документация не расходится с кодом.
//
// Сессии читают не код целиком, а CLAUDE.md и файл своей области в docs/. Если там путь к файлу,
// которого больше нет, или в карте нет нового файла, следующая сессия уверенно идёт не туда:
// так CLAUDE.md писал про «NotesCore/.../GitVault.swift», а новых файлов входа в списке не было.
// Поэтому проверяем то, что можно проверить механически.
@Suite("документация")
struct DocsTests {
    // Этот файл — NotesCore/Tests/NotesCoreTests/DocsTests.swift: корень репозитория на четыре папки выше.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    static func files(in dir: String, ext: String) -> [String] {
        let base = root.appendingPathComponent(dir)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == ext }
            .map { dir + "/" + $0.path.dropFirst(base.path.count + 1) }
            .sorted()
    }

    static var docs: [String] {
        ["CLAUDE.md"] + files(in: "docs", ext: "md")
    }

    // Код, который обязан быть в карте. Тесты карта перечисляет группой, по одному их не требуем.
    static var codeFiles: [String] {
        files(in: "<notes>", ext: "swift")
            + files(in: "NotesCore/Sources", ext: "swift")
            + files(in: "NotesSpeech/Sources", ext: "swift")
            + files(in: "Scripts", ext: "sh")
            + ["NotesCore/Package.swift", "NotesSpeech/Package.swift"]
    }

    @Test("в карте есть каждый файл кода")
    func mapListsEveryFile() throws {
        let map = try Self.read("docs/MAP.md")
        let missing = Self.codeFiles.filter { !map.contains("`\($0)`") }
        #expect(missing.isEmpty, "добавь в docs/MAP.md строку на каждый новый файл: \(missing)")
    }

    // Путь в обратных кавычках, который начинается с папки проекта и кончается расширением.
    // Шаблоны со звёздочкой, «...» и заглушки в угловых скобках — не пути.
    @Test("пути к файлам в документации живые")
    func pathsAreAlive() throws {
        let pattern = try Regex(#"`((?:<notes>|NotesCore|NotesSpeech|Scripts|docs)/[^`\s]+\.[a-z]+)`"#)
        var dead: [String] = []
        for doc in Self.docs {
            for match in try Self.read(doc).matches(of: pattern) {
                let path = String(match.output[1].substring ?? "")
                if path.contains("*") || path.contains("...") || path.contains("…") { continue }
                if !Self.exists(path) { dead.append("\(doc): \(path)") }
            }
        }
        #expect(dead.isEmpty, "мёртвые пути: \(dead)")
    }

    @Test("ссылки между документами живые")
    func linksAreAlive() throws {
        let pattern = try Regex(#"\]\(([^)#\s]+\.md)\)"#)
        var dead: [String] = []
        for doc in Self.docs {
            let folder = (doc as NSString).deletingLastPathComponent
            for match in try Self.read(doc).matches(of: pattern) {
                let link = String(match.output[1].substring ?? "")
                if link.hasPrefix("http") { continue }
                let path = ((folder.isEmpty ? link : folder + "/" + link) as NSString).standardizingPath
                if !Self.exists(path) { dead.append("\(doc): \(link)") }
            }
        }
        #expect(dead.isEmpty, "мёртвые ссылки: \(dead)")
    }

    @Test("CLAUDE.md ведёт к каждому документу в docs")
    func routerCoversDocs() throws {
        let router = try Self.read("CLAUDE.md")
        let missing = Self.files(in: "docs", ext: "md").filter { !router.contains("](\($0))") }
        #expect(missing.isEmpty, "добавь документ в таблицу CLAUDE.md: \(missing)")
    }

    // Иначе журнал тихо превращается в свалку без статусов, и непонятно, что в работе.
    @Test("у каждой задачи статус, у журнала дата")
    func tasksHaveStatus() throws {
        let tasks = try Self.read("docs/TASKS.md")
        let allowed = ["[в работе]", "[следующая]", "[ждёт Макара]", "[пауза]", "[потом]", "[готово]"]
        let body = tasks.components(separatedBy: "## Задачи").dropFirst().joined()
        let items = body.split(separator: "\n").filter { $0.hasPrefix("- ") }
        let bad = items.filter { line in !allowed.contains { line.hasPrefix("- " + $0) } }
        #expect(!items.isEmpty)
        #expect(bad.isEmpty, "задача без статуса: \(bad)")
        #expect(tasks.contains(try Regex(#"Обновлено: \d{2}\.\d{2}\.\d{4}\."#)))
    }
}
