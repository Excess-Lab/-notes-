import Foundation
import Testing
@testable import NotesCore

@Suite("задачи в заметках")
struct NoteTasksTests {
    let note = URL(fileURLWithPath: "/tmp/план.md")

    @Test("разбор: чекбокс, готово, дата, дата со временем, не задачи")
    func parse() throws {
        let text = """
        # План
        - [ ] Созвониться с командой 📅 2026-10-16 15:00
          - [x] Выбрать модель
        * [ ] Купить хлеб 📅 2026-10-17
        - [ ]
        - обычный пункт
        """
        let tasks = NoteTasks.tasks(in: text, note: note)
        #expect(tasks.map(\.title) == ["Созвониться с командой", "Выбрать модель", "Купить хлеб"])
        #expect(tasks.map(\.done) == [false, true, false])
        #expect(tasks[0].hasTime && !tasks[2].hasTime)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: try #require(tasks[0].due))
        #expect([parts.year, parts.month, parts.day, parts.hour, parts.minute] == [2026, 10, 16, 15, 0])
        #expect(tasks[1].line == 2)
    }

    // Иначе отметка «готово» могла бы попасть не в ту строку, если файл поменяли в другом редакторе.
    @Test("отметка правит только свою строку и не трогает изменённый файл")
    func setDone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let lib = NoteLibrary(root: root)
        let url = root.appendingPathComponent("a.md")
        try "текст\n- [ ] Дело 📅 2026-10-16\nхвост".write(to: url, atomically: true, encoding: .utf8)
        let task = try #require(NoteTasks.all(in: lib).first)
        try NoteTasks.setDone(task, true, library: lib)
        #expect(try lib.read(url) == "текст\n- [x] Дело 📅 2026-10-16\nхвост")
        #expect(throws: NoteTasks.EditError.self) { try NoteTasks.setDone(task, false, library: lib) }
    }

    @Test("группы: просроченное — сегодня, неделя, позже, без даты, готово")
    func groups() {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        func task(_ days: Double?, done: Bool = false) -> NoteTask {
            NoteTask(note: note, line: 0, raw: "", title: "x", done: done,
                     due: days.map { now.addingTimeInterval($0 * 86_400) }, hasTime: false)
        }
        #expect(NoteTasks.group(task(-3), now: now) == .today)
        #expect(NoteTasks.group(task(3), now: now) == .week)
        #expect(NoteTasks.group(task(20), now: now) == .later)
        #expect(NoteTasks.group(task(nil), now: now) == .noDate)
        #expect(NoteTasks.group(task(1, done: true), now: now) == .done)
    }

    // Иначе событие в календаре оставалось бы после «готово» или плодилось бы при каждой синхронизации.
    @Test("календарь: создать новое, обновить изменённое, удалить готовое, не трогать совпадающее")
    func plan() {
        let day = Date(timeIntervalSince1970: 1_792_000_000)
        func task(_ title: String, done: Bool = false, due: Date? = day) -> NoteTask {
            NoteTask(note: note, line: 0, raw: "", title: title, done: done, due: due, hasTime: true)
        }
        let same = CalendarPlan.Event(title: "Тот же", start: day, allDay: false)
        let actions = CalendarPlan.actions(
            tasks: [task("Новая"), task("Тот же"), task("Сдвинут"), task("Готово", done: true), task("Без даты", due: nil)],
            links: ["\(note.path)|Тот же": "e1", "\(note.path)|Сдвинут": "e2", "\(note.path)|Готово": "e3"],
            existing: ["e1": same, "e2": CalendarPlan.Event(title: "Сдвинут", start: day.addingTimeInterval(3600), allDay: false), "e3": same])
        #expect(actions.contains(.create(key: "\(note.path)|Новая", CalendarPlan.Event(title: "Новая", start: day, allDay: false))))
        #expect(actions.contains(.update(key: "\(note.path)|Сдвинут", eventID: "e2", CalendarPlan.Event(title: "Сдвинут", start: day, allDay: false))))
        #expect(actions.contains(.delete(key: "\(note.path)|Готово", eventID: "e3")))
        #expect(actions.count == 3)
    }

    // Иначе новая задача склеивалась бы с последней строкой заметки.
    @Test("задача из календаря дописывается новой строкой и читается обратно")
    func append() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("append-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let lib = NoteLibrary(root: root)
        let url = root.appendingPathComponent("Входящие.md")
        try "купить хлеб".write(to: url, atomically: true, encoding: .utf8)
        let due = Date(timeIntervalSince1970: 1_792_000_000)
        try NoteTasks.append("Созвон", due: due, hasTime: true, to: url, library: lib)
        let tasks = NoteTasks.all(in: lib)
        #expect(try lib.read(url).hasPrefix("купить хлеб\n- [ ] Созвон 📅 "))
        #expect(tasks.first?.title == "Созвон" && tasks.first?.hasTime == true)
    }

    // Иначе «!!» оставалось бы в названии задачи и в событии календаря.
    @Test("срочность: «!!» в строке, в названии её нет; задача без даты дописывается")
    func urgent() throws {
        let task = try #require(NoteTasks.parse("- [ ] Позвонить !! 📅 2026-10-31", note: note, index: 0))
        #expect(task.urgent && task.title == "Позвонить" && task.due != nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("urg-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let lib = NoteLibrary(root: root), url = root.appendingPathComponent("Входящие.md")
        try NoteTasks.append("Купить хлеб", due: nil, hasTime: false, urgent: true, to: url, library: lib)
        #expect(try lib.read(url) == "- [ ] Купить хлеб !!\n")
    }

    @Test("длительность: конец после тире")
    func duration() {
        let task = NoteTasks.parse("- [ ] Созвон 📅 2026-10-31 15:00–16:30", note: URL(fileURLWithPath: "/n.md"), index: 0)
        #expect(task?.minutes == 90)
        #expect(task?.title == "Созвон")
        #expect(task?.hasTime == true)
    }
}
