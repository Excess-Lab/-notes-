import Foundation
import Testing
@testable import NotesCore

@Suite("шаблоны и заметка дня")
struct TemplatesTests {
    let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9, minute: 5))!

    private func vault() throws -> NoteLibrary {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("шаблоны"), withIntermediateDirectories: true)
        return NoteLibrary(root: root)
    }

    @Test("подстановки даты, времени и названия")
    func apply() {
        #expect(Templates.apply("# {{название}}\n{{дата}} {{время}}", title: "Встреча", date: date) == "# Встреча\n2026-10-31 09:05")
    }

    @Test("заметка из шаблона: имя шаблона, текст с подстановками, занятое имя — с номером")
    func create() throws {
        let library = try vault()
        let template = library.root.appendingPathComponent("шаблоны/встреча.md")
        try "# {{название}} {{дата}}".write(to: template, atomically: true, encoding: .utf8)
        let first = try Templates.create(from: template, in: library.root, library: library, date: date)
        let second = try Templates.create(from: template, in: library.root, library: library, date: date)
        #expect(try String(contentsOf: first, encoding: .utf8) == "# встреча 2026-10-31")
        #expect(first != second)
        #expect(Templates.list(in: library).map(\.lastPathComponent) == ["встреча.md"])
    }

    @Test("заметка дня: по шаблону «день», второй раз не перезаписывается")
    func daily() throws {
        let library = try vault()
        try "# {{дата}}\n- [ ] план".write(to: library.root.appendingPathComponent("шаблоны/день.md"), atomically: true, encoding: .utf8)
        let url = try Templates.daily(in: library, date: date)
        #expect(url.lastPathComponent == "2026-10-31.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == "# 2026-10-31\n- [ ] план")
        try "правка".write(to: url, atomically: true, encoding: .utf8)
        _ = try Templates.daily(in: library, date: date)
        #expect(try String(contentsOf: url, encoding: .utf8) == "правка")
    }
}
