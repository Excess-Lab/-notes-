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
    // Растёт по плюсу справа сверху — строка новой задачи берёт фокус.
    var focusNew = 0
    let calendar = CalendarSync.shared

    init(library: NoteLibrary) {
        self.library = library
        reload()
    }

    func reload() {
        // Экран показывает ровно то, что уходит в календарь: задачи из выбранных папок (настройки → календарь,
        // «задачи из папок»). Остальной Markdown не тянем (ТЗ 30.10.2026: «отображаем то, что с календаря»).
        tasks = NoteTasks.all(in: library).filter { calendar.includes(library.breadcrumb(for: $0.note)) }
        calendar.sync(tasks)
    }

    // Поменялась одна заметка (своё сохранение): разбираем только её. Календарь трогаем, только если её
    // задачи и правда изменились — обычный набор текста EventKit не будит.
    func reload(note: URL, text: String) {
        guard calendar.includes(library.breadcrumb(for: note)) else { return }
        let fresh = NoteTasks.tasks(in: text, note: note)
        let old = tasks.filter { $0.note.standardizedFileURL == note.standardizedFileURL }
        guard fresh != old else { return }
        // На место старых — порядок в списке не прыгает.
        let at = tasks.firstIndex { $0.note.standardizedFileURL == note.standardizedFileURL } ?? tasks.count
        tasks.removeAll { $0.note.standardizedFileURL == note.standardizedFileURL }
        tasks.insert(contentsOf: fresh, at: min(at, tasks.count))
        calendar.sync(tasks)
    }

    func count(_ filter: Filter) -> Int { tasks.filter { matches($0, filter) }.count }

    // Срочные — первыми в своей группе.
    var visible: [NoteTask] { tasks.filter { matches($0, filter) }.sorted { $0.urgent && !$1.urgent } }

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
    func add(_ title: String, due: Date?, hasTime: Bool, urgent: Bool = false, minutes: Int? = nil) {
        try? NoteTasks.append(title, due: due, hasTime: hasTime, urgent: urgent, minutes: minutes,
                              to: library.root.appendingPathComponent("Входящие.md"), library: library)
        reload()
    }

    func toggle(_ task: NoteTask, undo: UndoManager? = nil) {
        do {
            try NoteTasks.setDone(task, !task.done, library: library)
        } catch {
            // Файл поменяли в другом редакторе — перечитываем и не трогаем.
            NSSound.beep()
        }
        reload()
        // ⌘Z — отметка обратно: ищем ту же строку уже с новым текстом.
        guard let undo else { return }
        undo.registerUndo(withTarget: self) { model in
            if let fresh = model.tasks.first(where: { $0.note == task.note && $0.line == task.line }) { model.toggle(fresh, undo: undo) }
        }
        undo.setActionName(task.done ? "Снять отметку" : "Отметку")
    }

    // MARK: - Правка событий прямо в календаре (удобство «как у Apple», 31.10.2026)

    // Задача, из которой сделано событие, — по связи «ключ задачи → id события».
    func task(for event: EKEvent) -> NoteTask? {
        guard let key = calendar.links.first(where: { $0.value == event.eventIdentifier })?.key else { return nil }
        return tasks.first { $0.key == key }
    }

    // Перетащили или растянули. Событие задачи двигаем через её строку в заметке — иначе синхронизация
    // вернула бы старое время. ⌘Z — обратно.
    func move(_ event: EKEvent, start: Date, end: Date, undo: UndoManager?) {
        let old = (event.startDate!, event.endDate!)
        guard old != (start, end) else { return }
        if let task = task(for: event) {
            let minutes = Int(end.timeIntervalSince(start) / 60)
            do { try NoteTasks.setDue(task, start, hasTime: true, minutes: minutes, library: library) } catch { NSSound.beep(); return }
            reload()
        } else {
            event.startDate = start
            event.endDate = end
            do { try calendar.store.save(event, span: .thisEvent, commit: true) } catch { NSSound.beep(); return }
        }
        undo?.registerUndo(withTarget: self) { model in
            guard let fresh = model.calendar.store.event(withIdentifier: event.eventIdentifier) else { return }
            model.move(fresh, start: old.0, end: old.1, undo: undo)
        }
        undo?.setActionName("Перенос события")
    }

    func rename(_ event: EKEvent, to title: String, undo: UndoManager?) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = event.title ?? ""
        guard !clean.isEmpty, clean != old, task(for: event) == nil else { return }
        event.title = clean
        do { try calendar.store.save(event, span: .thisEvent, commit: true) } catch { NSSound.beep(); return }
        undo?.registerUndo(withTarget: self) { model in
            if let fresh = model.calendar.store.event(withIdentifier: event.eventIdentifier) { model.rename(fresh, to: old, undo: undo) }
        }
        undo?.setActionName("Переименование")
    }

    // Перенести событие в другой календарь. Событие задачи живёт в календаре для задач — его не двигаем.
    func moveTo(_ event: EKEvent, _ target: EKCalendar, undo: UndoManager?) {
        guard task(for: event) == nil, let old = event.calendar, old != target else { return }
        event.calendar = target
        do { try calendar.store.save(event, span: .thisEvent, commit: true) } catch { NSSound.beep(); return }
        undo?.registerUndo(withTarget: self) { model in
            if let fresh = model.calendar.store.event(withIdentifier: event.eventIdentifier) { model.moveTo(fresh, old, undo: undo) }
        }
        undo?.setActionName("Перенос в календарь")
    }

    // Удалить обычное событие (задача удаляется в своей заметке). ⌘Z — создаём такое же заново.
    func remove(_ event: EKEvent, undo: UndoManager?) {
        guard task(for: event) == nil else { return }
        let copy = (event.title, event.startDate, event.endDate, event.isAllDay, event.calendar, event.notes, event.location)
        do { try calendar.store.remove(event, span: .thisEvent, commit: true) } catch { NSSound.beep(); return }
        undo?.registerUndo(withTarget: self) { model in
            let back = EKEvent(eventStore: model.calendar.store)
            (back.title, back.startDate, back.endDate, back.isAllDay, back.calendar, back.notes, back.location) = copy
            try? model.calendar.store.save(back, span: .thisEvent, commit: true)
        }
        undo?.setActionName("Удаление события")
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
    // Меняется при любой правке календарей (в том числе снаружи) — экран перечитывает список.
    // Раньше удалённый календарь висел в боковой панели, пока не переключишь раздел.
    private(set) var revision = 0
    // Событие из поиска: экран календаря переходит на его день и сбрасывает значение.
    var focus: Date?
    private var storeObserver: NSObjectProtocol?
    // Связи «задача → событие» — вне хранилища: в заметки служебное не пишем.
    private(set) var links: [String: String] = [:]
    private static let linksURL = AppSupport.folder
        .appendingPathComponent("calendar-links.json")

    private static let calendarKey = "tasksCalendar"
    private static let durationKey = "taskMinutes"

    init() {
        // Папки Application Support в новом контейнере может ещё не быть — без неё связи не сохранялись,
        // и каждый запуск создавал события заново.
        try? FileManager.default.createDirectory(at: Self.linksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        links = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: Self.linksURL))) ?? [:]
        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarSync.shared.revision += 1 }
        }
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
        set { UserDefaults.standard.set(newValue?.calendarIdentifier, forKey: Self.calendarKey); revision += 1 }
    }

    var calendars: [EKCalendar] { store.calendars(for: .event).filter(\.allowsContentModifications) }

    // Скрытые на экране календаря — галочка в боковой панели. Только вид: в Календаре Apple ничего не меняется.
    private(set) var hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenCalendars") ?? [])

    func toggleShown(_ calendar: EKCalendar) {
        if hidden.remove(calendar.calendarIdentifier) == nil { hidden.insert(calendar.calendarIdentifier) }
        UserDefaults.standard.set(Array(hidden), forKey: "hiddenCalendars")
        revision += 1
    }

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
        event.endDate = plan.allDay ? plan.start : plan.start.addingTimeInterval(TimeInterval((plan.minutes ?? minutes) * 60))
        event.notes = "Задача из заметок <notes>."
    }

    // Удалить календарь, но не события: сначала все его события переезжают в календарь по умолчанию
    // («обычный»), потом удаляется сам календарь. Повторяющиеся переносим один раз, всей серией.
    // Возвращает, сколько событий перенесено.
    // Новый календарь — в той же учётной записи, что календарь по умолчанию (iCloud или «На Mac»).
    func createCalendar(_ title: String) throws {
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = title
        guard let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first(where: { $0.sourceType == .local }) else {
            throw CocoaError(.featureUnsupported)
        }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        revision += 1
    }

    func rename(_ calendar: EKCalendar, _ title: String) throws {
        calendar.title = title
        try store.saveCalendar(calendar, commit: true)
        revision += 1
    }

    func recolor(_ calendar: EKCalendar, _ color: NSColor) {
        calendar.color = color
        try? store.saveCalendar(calendar, commit: true)
        revision += 1
    }

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
        revision += 1
        return moved
    }

    // События недели или дня для экрана календаря.
    func events(from start: Date, to end: Date) -> [EKEvent] {
        guard hasAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).filter { !hidden.contains($0.calendar.calendarIdentifier) }
            .sorted { $0.startDate < $1.startDate }
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
        // Только своя связь: синхронизация удаляет события всех связей, которых нет в списке, — с общими
        // связями проверка 31.10.2026 стёрла события задач Макара (PITFALLS.md). Чужие связи откладываем
        // и возвращаем, файл связей переписываем как было.
        let saved = links
        links = [:]
        defer {
            enabled = wasEnabled
            links = saved
            try? JSONEncoder().encode(links).write(to: Self.linksURL)
        }
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

#if DEBUG
extension TasksModel {
    // Живая проверка правки событий: временный календарь, событие в нём → перенос, растягивание,
    // переименование, удаление и ⌘Z каждого → календарь удаляется. Чужие события не трогает.
    func editSelfTest(_ log: (String, Bool) -> Void) {
        let store = calendar.store
        guard calendar.hasAccess, let source = store.defaultCalendarForNewEvents?.source else { return log("доступ к календарю", false) }
        let temp = EKCalendar(for: .event, eventStore: store)
        temp.title = "<notes> проверка правки"
        temp.source = source
        do { try store.saveCalendar(temp, commit: true) } catch { return log("временный календарь", false) }
        defer { try? store.removeCalendar(temp, commit: true) }
        let event = EKEvent(eventStore: store)
        event.calendar = temp
        event.title = "<notes> правка"
        event.startDate = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date().addingTimeInterval(86_400))!
        event.endDate = event.startDate.addingTimeInterval(3600)
        try? store.save(event, span: .thisEvent, commit: true)
        let id = event.eventIdentifier!, start = event.startDate!, undo = UndoManager()
        undo.groupsByEvent = false
        func fresh() -> EKEvent? { store.event(withIdentifier: id) }
        func step(_ action: () -> Void) { undo.beginUndoGrouping(); action(); undo.endUndoGrouping() }

        step { move(event, start: start.addingTimeInterval(86_400 + 1800), end: start.addingTimeInterval(86_400 + 5400), undo: undo) }
        log("перенос на день и полчаса", fresh()?.startDate == start.addingTimeInterval(86_400 + 1800))
        undo.undo()
        log("⌘Z вернул время", fresh()?.startDate == start && fresh()?.endDate == start.addingTimeInterval(3600))
        step { move(fresh()!, start: start, end: start.addingTimeInterval(5400), undo: undo) }
        log("растянуто до 1,5 ч", fresh()?.endDate == start.addingTimeInterval(5400))
        step { rename(fresh()!, to: "<notes> новое имя", undo: undo) }
        log("переименовано", fresh()?.title == "<notes> новое имя")
        undo.undo()
        log("⌘Z вернул имя", fresh()?.title == "<notes> правка")
        step { remove(fresh()!, undo: undo) }
        log("удалено", fresh() == nil)
        undo.undo()
        let back = store.events(matching: store.predicateForEvents(withStart: start.addingTimeInterval(-60), end: start.addingTimeInterval(7200), calendars: [temp]))
        log("⌘Z вернул удалённое", back.first?.title == "<notes> правка" && back.first?.endDate == start.addingTimeInterval(5400))
        try? calendar.rename(temp, "<notes> проверка имени")
        calendar.recolor(temp, .systemTeal)
        let renamed = store.calendar(withIdentifier: temp.calendarIdentifier)
        log("календарь переименован", renamed?.title == "<notes> проверка имени")
        // Цвет сравниваем по компонентам в sRGB: календарь хранит его в своём цветовом пространстве.
        func rgb(_ c: NSColor?) -> [Int] {
            guard let c = c?.usingColorSpace(.sRGB) else { return [] }
            return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 20).rounded()) }
        }
        log("календарь перекрашен", !rgb(renamed?.color).isEmpty && rgb(renamed?.color) == rgb(.systemTeal))
        let other = EKCalendar(for: .event, eventStore: store)
        other.title = "<notes> проверка переноса"
        other.source = source
        if (try? store.saveCalendar(other, commit: true)) != nil, let moved = back.first {
            step { moveTo(moved, other, undo: undo) }
            log("событие перенесено в другой календарь", store.event(withIdentifier: moved.eventIdentifier)?.calendar == other)
            undo.undo()
            log("⌘Z вернул календарь события", store.event(withIdentifier: moved.eventIdentifier)?.calendar == temp)
            try? store.removeCalendar(other, commit: true)
        }
    }
}
#endif
