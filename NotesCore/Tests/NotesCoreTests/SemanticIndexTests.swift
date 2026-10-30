import Foundation
import Testing
@testable import NotesCore

// Заглушка: «смысл» — какие слова-маркеры есть в тексте. Проверяем устройство индекса, а не модель.
private struct MarkerEmbedder: Embedder {
    let words = ["телефон", "git", "хлеб"]
    func vector(for text: String) throws -> [Float] {
        let low = text.lowercased()
        return words.map { low.contains($0) ? 1 : 0 } + [0.01]
    }
}

@Suite("поиск по смыслу")
struct SemanticIndexTests {
    @Test("абзацы — куски, длинный абзац режется по предложениям")
    func chunks() {
        let long = String(repeating: "Предложение про заметки. ", count: 40)
        let pieces = SemanticIndex.chunks(of: "Первый абзац.\n\n\(long)\n\n—")
        #expect(pieces.first == "Первый абзац.")
        #expect(pieces.count > 2 && pieces.dropFirst().allSatisfy { $0.count <= 620 })
    }

    // Иначе индекс пересчитывал бы все заметки на каждое изменение и не забывал удалённые.
    @Test("пересчёт только изменённых, удалённые пропадают, ближайшая заметка — первая")
    func updateAndSearch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sem-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "Открыть репозиторий с телефона".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "Купить хлеб".write(to: root.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        let lib = NoteLibrary(root: root), index = SemanticIndex(), embedder = MarkerEmbedder()
        #expect(index.update(library: lib, embedder: embedder) == 2)
        #expect(index.update(library: lib, embedder: embedder) == 0)
        #expect(index.search("заметки на телефоне", embedder: embedder).first?.note.lastPathComponent == "a.md")
        try FileManager.default.removeItem(at: root.appendingPathComponent("b.md"))
        index.update(library: lib, embedder: embedder)
        #expect(index.search("хлеб", embedder: embedder).allSatisfy { $0.note.lastPathComponent != "b.md" })
    }
}

// Настоящая модель Apple: включается `NOTES_APPLE_EMBED=1 swift test` (первый раз система докачивает ресурсы).
@Suite("поиск по смыслу: модель Apple", .enabled(if: ProcessInfo.processInfo.environment["NOTES_APPLE_EMBED"] == "1"))
struct AppleEmbedderTests {
    @Test("находит заметку по смыслу, без общих слов с запросом")
    func russianMeaning() async throws {
        let embedder = try #require(AppleEmbedder())
        try await embedder.prepare()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("apple-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let notes = ["working copy": "Можно открыть репозиторий в Working Copy и читать заметки с айфона.",
                     "покупки": "Молоко, хлеб, яйца и сыр на выходные.",
                     "тренировка": "Разминка двадцать минут, потом бег и растяжка.",
                     "книги": "Норвежский лес Мураками и Мастер и Маргарита."]
        for (name, text) in notes { try text.write(to: root.appendingPathComponent("\(name).md"), atomically: true, encoding: .utf8) }
        let lib = NoteLibrary(root: root), index = SemanticIndex()
        index.update(library: lib, embedder: embedder)
        // Встроенная модель — не идеал: требуем 3 из 4 запросов без общих слов (на 30.10.2026 «что почитать»
        // уходит в «покупки»). Упадёт ниже — пора думать о скачиваемой модели (CONTEXT.md).
        var right = 0
        for (query, expected) in [("как смотреть записи на телефоне", "working copy"), ("что купить в магазине", "покупки"),
                                  ("спорт и упражнения", "тренировка"), ("что почитать", "книги")] {
            let top = index.search(query, embedder: embedder).first?.note.deletingPathExtension().lastPathComponent
            print("«\(query)» → \(top ?? "-")")
            if top == expected { right += 1 }
        }
        #expect(right >= 3)
    }
}
