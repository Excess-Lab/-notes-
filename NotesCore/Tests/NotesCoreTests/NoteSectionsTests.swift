import Testing
@testable import NotesCore

@Suite("разделы от apple intelligence")
struct NoteSectionsTests {
    @Test("кратко — под заголовком, повтор заменяет")
    func summary() {
        let note = "---\nисточник: a\n---\n\n# Встреча\n\nтекст"
        let once = NoteSections.setSummary("- первое", in: note)
        #expect(once == "---\nисточник: a\n---\n\n# Встреча\n\n## Кратко\n\n- первое\n\nтекст")
        #expect(NoteSections.setSummary("- второе", in: once) == "---\nисточник: a\n---\n\n# Встреча\n\n## Кратко\n\n- второе\n\nтекст")
    }

    @Test("задачи — в конце строками задач, повтор заменяет")
    func tasks() {
        let once = NoteSections.setTasks([("Позвонить", "2026-11-03"), ("Купить", nil)], in: "# Т\n\nтекст\n")
        #expect(once == "# Т\n\nтекст\n\n## Задачи\n\n- [ ] Позвонить 📅 2026-11-03\n- [ ] Купить\n")
        #expect(NoteSections.setTasks([("Одна", nil)], in: once) == "# Т\n\nтекст\n\n## Задачи\n\n- [ ] Одна\n")
        let task = NoteTasks.parse("- [ ] Позвонить 📅 2026-11-03", note: .init(fileURLWithPath: "/a.md"), index: 0)
        #expect(task?.due != nil)
    }
}
