import Foundation
import Testing
@testable import NotesCore

@Suite("заметки в папке")
struct NoteLibraryTests {
    private func vault() throws -> NoteLibrary {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("проекты/вложенная"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "# План\nСинхронизация через git, без облака.".write(to: root.appendingPathComponent("проекты/план приложения.md"), atomically: true, encoding: .utf8)
        try "идеи".write(to: root.appendingPathComponent("проекты/вложенная/идеи.md"), atomically: true, encoding: .utf8)
        try "купить хлеб".write(to: root.appendingPathComponent("Входящие.md"), atomically: true, encoding: .utf8)
        try "служебное".write(to: root.appendingPathComponent(".git/HEAD.md"), atomically: true, encoding: .utf8)
        try Data([1]).write(to: root.appendingPathComponent("картинка.png"))
        return NoteLibrary(root: root)
    }

    // Иначе в боковой панели появились бы файлы git и картинки, а счётчики врали бы.
    @Test("дерево: только .md, скрытые папки пропускаем, счётчик со вложенными")
    func tree() throws {
        let tree = try vault().tree()
        #expect(tree.notes.map(\.title) == ["Входящие"])
        #expect(tree.folders.map(\.name) == ["проекты"])
        #expect(tree.folders[0].noteCount == 2)
        #expect(tree.noteCount == 3)
    }

    @Test("новая заметка не перезаписывает существующую")
    func createNoteKeepsExisting() throws {
        let lib = try vault()
        let first = try lib.createNote(in: lib.root)
        let second = try lib.createNote(in: lib.root)
        #expect(first.lastPathComponent == "без названия.md")
        #expect(second.lastPathComponent == "без названия 2.md")
    }

    @Test("переименование: «/» не ломает путь, пустое имя не принимаем")
    func rename() throws {
        let lib = try vault()
        let note = lib.root.appendingPathComponent("Входящие.md")
        let renamed = try lib.rename(note, to: "дела/неделя")
        #expect(renamed.lastPathComponent == "дела-неделя.md")
        #expect(try lib.rename(renamed, to: "  ") == renamed)
    }

    @Test("поиск по тексту: все слова, ё как е, название важнее, отрывок из строки с совпадением")
    func search() throws {
        let lib = try vault()
        let hits = lib.search("СИНХРОНИЗАЦИЯ облака")
        #expect(hits.map(\.note.title) == ["план приложения"])
        #expect(hits[0].snippet.hasPrefix("Синхронизация через git"))
        #expect(lib.search("хлеб пирог").isEmpty)
        #expect(lib.search("   ").isEmpty)
    }

    @Test("путь заметки для строки сверху и счёт слов")
    func breadcrumbAndWords() throws {
        let lib = try vault()
        #expect(lib.breadcrumb(for: lib.root.appendingPathComponent("проекты/план приложения.md")) == ["проекты", "план приложения"])
        #expect(NoteLibrary.wordCount("# План\nдва слова — и 3") == 5)
    }
}
