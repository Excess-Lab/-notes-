import AppKit
import EventKit
import NotesCore

// Задачи из всех заметок и их отражение в Apple Calendar. Список собирается из файлов заново
// при каждой правке хранилища — своей базы задач нет (DECISIONS.md, «Задачи»).
@Observable final class TasksModel {
    enum Filter: String, CaseIterable {
        case all = "все задачи", today = "сегодня", week = "на неделе", noDate = "без даты"
        case inCalendar = "в календаре", done = "готово"
    }

    let library: NoteLibrary
    private(set) var tasks: [NoteTask] = []
    var filter: Filter = .all
    let calendar = CalendarSync.shared

    init(library: NoteLibrary) {
        self.library = library
        reload()
    }

    func reload() {
        tasks = NoteTasks.all(in: library)
        // В календарь — только задачи из выбранных папок (настройки → календарь).
        calendar.sync(tasks.filter { calendar.includes(library.breadcrumb(for: $0.note)) })
    }

    func count(_ filter: Filter) -> Int { tasks.filter { matches($0, filter) }.count }

    var visible: [NoteTask] { tasks.filter { matches($0, filter) } }

    func matches(_ task: NoteTask, _ filter: Filter) -> Bool {
        let group = NoteTasks.group(task)
        switch filter {
        case .all: return true
        case .today: return group == .today
        case .week: return group == .week
        case .noDate: return group == .noDate
        case .inCalendar: return calendar.isLinked(task)
        case .done: return task.done
        }
    }

    // Добавить из календаря: в «Входящие.md» в корне хранилища, дальше — обычная синхронизация.
    func add(_ title: String, due: Date, hasTime: Bool) {
        try? NoteTasks.append(title, due: due, hasTime: hasTime,
                              to: library.root.appendingPathComponent("Входящие.md"), library: library)
        reload()
    }

    func toggle(_ task: NoteTask) {
        do {
            try NoteTasks.setDone(task, !task.done, library: library)
        } catch {
            // Файл поменяли в другом редакторе — перечитываем и не трогаем.
            NSSound.beep()
        }
        reload()
    }

    // «сегодня», «чт 16 окт», «в календаре, 15:00».
    func when(_ task: NoteTask) -> String? {
        guard let due = task.due else { return task.done ? nil : nil }
        let time = task.hasTime ? ", " + due.formatted(.dateTime.hour().minute()) : ""
        let day = Calendar.current.isDateInToday(due) ? "сегодня"
            : due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "ru_RU")))
                .replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
        return calendar.isLinked(task) ? "\(day) в календаре\(time)" : day + time
    }
}

// Задачи с датой → события в Apple Calendar. Что создать, обновить и удалить, решает
// NotesCore.CalendarPlan; здесь только EventKit (системная библиотека календаря) и хранение связей.
@Observable final class CalendarSync {
    static let shared = CalendarSync()

    let store = EKEventStore()
    // Связи «задача → событие» — вне хранилища: в заметки служебное не пишем.
    private(set) var links: [String: String] = [:]
    private static let linksURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("calendar-links.json")

    private static let calendarKey = "tasksCalendar"
    private static let durationKey = "taskMinutes"

    init() {
        // Папки Application Support в новом контейнере может ещё не быть — без неё связи не сохранялись,
        // и каждый запуск создавал события заново.
        try? FileManager.default.createDirectory(at: Self.linksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        links = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: Self.linksURL))) ?? [:]
    }

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    // Какой календарь для задач: выбранный в настройках, иначе календарь по умолчанию.
    var tasksCalendar: EKCalendar? {
        get {
            UserDefaults.standard.string(forKey: Self.calendarKey).flatMap { store.calendar(withIdentifier: $0) }
                ?? store.defaultCalendarForNewEvents
        }
        set { UserDefaults.standard.set(newValue?.calendarIdentifier, forKey: Self.calendarKey) }
    }

    var calendars: [EKCalendar] { store.calendars(for: .event).filter(\.allowsContentModifications) }

    // Сколько длится событие задачи, у которой есть время, но нет конца.
    var minutes: Int {
        get { UserDefaults.standard.object(forKey: Self.durationKey) as? Int ?? 30 }
        set { UserDefaults.standard.set(newValue, forKey: Self.durationKey) }
    }

    // Папки верхнего уровня, задачи из которых в календарь не идут. Заметки без папки идут всегда.
    var excludedFolders: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "calendarExcludedFolders") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "calendarExcludedFolders") }
    }

    func includes(_ path: [String]) -> Bool {
        path.count < 2 || !excludedFolders.contains(path[0])
    }

    func isLinked(_ task: NoteTask) -> Bool { links[task.key] != nil }
    func isTaskEvent(_ event: EKEvent) -> Bool { links.values.contains(event.eventIdentifier) }

    // Тестовая папка (-testVault) не трогает настоящий календарь: раньше проверки создали в Календаре
    // Макара события из тестовых задач (26.10.2026).
    var enabled = true

    func sync(_ tasks: [NoteTask]) {
        guard enabled, hasAccess, let target = tasksCalendar else { return }
        var existing: [String: CalendarPlan.Event?] = [:]
        for id in links.values {
            existing[id] = store.event(withIdentifier: id).map {
                CalendarPlan.Event(title: $0.title ?? "", start: $0.startDate, allDay: $0.isAllDay)
            }
        }
        for action in CalendarPlan.actions(tasks: tasks, links: links, existing: existing) {
            switch action {
            case .create(let key, let plan):
                let event = EKEvent(eventStore: store)
                event.calendar = target
                fill(event, plan)
                if (try? store.save(event, span: .thisEvent, commit: false)) != nil { links[key] = event.eventIdentifier }
            case .update(_, let id, let plan):
                if let event = store.event(withIdentifier: id) {
                    fill(event, plan)
                    try? store.save(event, span: .thisEvent, commit: false)
                }
            case .delete(let key, let id):
                if let event = store.event(withIdentifier: id) { try? store.remove(event, span: .thisEvent, commit: false) }
                links[key] = nil
            }
        }
        try? store.commit()
        try? JSONEncoder().encode(links).write(to: Self.linksURL)
    }

    #if DEBUG
    // Убрать события, созданные из тестовой папки, и их связи. Возвращает, сколько удалено.
    func removeTestEvents() -> Int {
        var removed = 0
        // Связи могли не сохраниться — ищем ещё и по метке приложения и названиям тестовых задач за ±60 дней.
        let titles: Set = ["Купить хлеб", "Созвониться с командой", "Собрать иконку приложения", "Дописать план приложения"]
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60 * 86_400),
                                                 end: now.addingTimeInterval(60 * 86_400), calendars: nil)
        for event in store.events(matching: predicate)
        where event.notes == "Задача из заметок <notes>." && titles.contains(event.title ?? "") {
            try? store.remove(event, span: .thisEvent, commit: false)
            removed += 1
        }
        for (key, id) in links where key.contains("/test-vault/") {
            if let event = store.event(withIdentifier: id) {
                try? store.remove(event, span: .thisEvent, commit: false)
                removed += 1
            }
            links[key] = nil
        }
        try? store.commit()
        try? JSONEncoder().encode(links).write(to: Self.linksURL)
        return removed
    }
    #endif

    private func fill(_ event: EKEvent, _ plan: CalendarPlan.Event) {
        event.title = plan.title
        event.isAllDay = plan.allDay
        event.startDate = plan.start
        event.endDate = plan.allDay ? plan.start : plan.start.addingTimeInterval(TimeInterval(minutes * 60))
        event.notes = "Задача из заметок <notes>."
    }

    // Удалить календарь, но не события: сначала все его события переезжают в календарь по умолчанию
    // («обычный»), потом удаляется сам календарь. Повторяющиеся переносим один раз, всей серией.
    // Возвращает, сколько событий перенесено.
    func removeCalendar(_ calendar: EKCalendar) throws -> Int {
        guard let target = store.defaultCalendarForNewEvents, target.calendarIdentifier != calendar.calendarIdentifier else {
            throw CocoaError(.featureUnsupported)
        }
        var moved = 0
        var seenSeries: Set<String> = []
        // EventKit отдаёт события кусками не длиннее 4 лет — идём окнами от −12 до +12 лет.
        var start = Calendar.current.date(byAdding: .year, value: -12, to: Date())!
        let end = Calendar.current.date(byAdding: .year, value: 12, to: Date())!
        while start < end {
            let stop = min(Calendar.current.date(byAdding: .year, value: 4, to: start)!, end)
            for event in store.events(matching: store.predicateForEvents(withStart: start, end: stop, calendars: [calendar])) {
                if event.hasRecurrenceRules {
                    let series = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? ""
                    guard seenSeries.insert(series).inserted else { continue }
                }
                event.calendar = target
                try store.save(event, span: event.hasRecurrenceRules ? .futureEvents : .thisEvent, commit: false)
                moved += 1
            }
            start = stop
        }
        try store.commit()
        try store.removeCalendar(calendar, commit: true)
        return moved
    }

    // События недели или дня для экрана календаря.
    func events(from start: Date, to end: Date) -> [EKEvent] {
        guard hasAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
}

#if DEBUG
extension CalendarSync {
    // Живая проверка с настоящим Календарём: задача с уникальным названием → событие → «готово» → удалено.
    func selfTest(_ log: (String, Bool) -> Void) {
        log("доступ к календарю есть", hasAccess)
        guard hasAccess else { return }
        let note = URL(fileURLWithPath: "/calendar-selftest/проверка.md")
        let title = "<notes> проверка \(UUID().uuidString.prefix(6))"
        let due = Date().addingTimeInterval(86_400)
        let when = NoteTasks.format(due, withTime: true)
        guard let open = NoteTasks.parse("- [ ] \(title) 📅 \(when)", note: note, index: 0),
              let done = NoteTasks.parse("- [x] \(title) 📅 \(when)", note: note, index: 0) else { return log("разбор задачи", false) }
        let wasEnabled = enabled
        enabled = true
        defer { enabled = wasEnabled }
        sync([open])
        let id = links[open.key]
        let event = id.flatMap { store.event(withIdentifier: $0) }
        log("событие создано в «\(tasksCalendar?.title ?? "—")»", event?.title == title && event?.calendar == tasksCalendar)
        sync([done])
        log("после «готово» событие удалено", id.flatMap { store.event(withIdentifier: $0) } == nil && links[open.key] == nil)
    }
}
#endif

// Подтверждение перед удалением календаря — системным окном, обычным языком (UI.md).
enum CalendarRemoval {
    static func confirm(_ calendar: EKCalendar, sync: CalendarSync) {
        let target = sync.store.defaultCalendarForNewEvents?.title ?? "календарь по умолчанию"
        let alert = NSAlert()
        alert.messageText = "Удалить календарь «\(calendar.title)»?"
        alert.informativeText = "Его события не пропадут — они переедут в «\(target)». Сам календарь исчезнет из Календаря Apple на всех устройствах."
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let moved = try sync.removeCalendar(calendar)
            let done = NSAlert()
            done.messageText = "Календарь удалён"
            done.informativeText = "Событий перенесено в «\(target)»: \(moved)."
            done.runModal()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

#if DEBUG
extension CalendarSync {
    // Живая проверка удаления: временный календарь с событием → удаление → событие в календаре
    // по умолчанию, временного календаря нет → тестовое событие убираем. Чужие календари не трогает.
    func removalSelfTest(_ log: (String, Bool) -> Void) {
        guard hasAccess, let target = store.defaultCalendarForNewEvents else { return log("доступ к календарю", false) }
        let temp = EKCalendar(for: .event, eventStore: store)
        temp.title = "<notes> проверка удаления"
        temp.source = target.source
        do { try store.saveCalendar(temp, commit: true) } catch { return log("временный календарь: \(error.localizedDescription)", false) }
        let event = EKEvent(eventStore: store)
        event.calendar = temp
        event.title = "<notes> переезд \(UUID().uuidString.prefix(6))"
        event.startDate = Date().addingTimeInterval(7200)
        event.endDate = event.startDate.addingTimeInterval(1800)
        try? store.save(event, span: .thisEvent, commit: true)
        let id = event.eventIdentifier!
        let moved = (try? removeCalendar(temp)) ?? -1
        let after = store.event(withIdentifier: id)
        log("удаление календаря: перенесено \(moved), событие теперь в «\(after?.calendar.title ?? "-")»",
            moved == 1 && after?.calendar.calendarIdentifier == target.calendarIdentifier)
        log("временного календаря больше нет", store.calendar(withIdentifier: temp.calendarIdentifier) == nil)
        if let after { try? store.remove(after, span: .thisEvent, commit: true) }
    }
}
#endif
