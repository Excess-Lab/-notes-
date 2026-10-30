import Foundation

// Задачи живут в заметках обычными строками Markdown (DECISIONS.md, «Задачи»):
//   - [ ] Созвониться с командой 📅 2026-10-16 15:00
//   - [x] Выбрать модель
// Своей базы задач нет: список собирается из файлов, отметка «готово» правит саму строку в файле.
public struct NoteTask: Hashable, Sendable, Identifiable {
    public let note: URL
    public let line: Int          // номер строки в файле, с нуля
    public let raw: String        // строка целиком — чтобы перед правкой убедиться, что её не поменяли
    public let title: String
    public let done: Bool
    public let due: Date?
    public let hasTime: Bool
    // Срочная — «!!» в строке: `- [ ] Позвонить !! 📅 2026-10-31`.
    public var urgent = false

    // Ключ для связки с событием календаря: заметка + текст. Переставили строку — связь не теряется.
    public var key: String { note.path + "|" + title }
    public var id: String { note.path + "#\(line)" }
}

public enum NoteTasks {
    static let marker = "📅"

    // Разбор одной строки. nil — это не задача.
    public static func parse(_ line: String, note: URL, index: Int) -> NoteTask? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard trimmed.hasPrefix("- [") || trimmed.hasPrefix("* ["), trimmed.count >= 6 else { return nil }
        let box = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)]
        guard box == " " || box == "x" || box == "X",
              trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)] == "]" else { return nil }
        var text = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        var due: Date?
        var hasTime = false
        if let range = text.range(of: marker) {
            let tail = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            (due, hasTime) = parseDate(String(tail))
            text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        var urgent = false
        if text.hasSuffix("!!") || text.contains(" !! ") {
            urgent = true
            text = text.replacingOccurrences(of: " !! ", with: " ").replacingOccurrences(of: "!!", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty else { return nil }
        return NoteTask(note: note, line: index, raw: line, title: text, done: box != " ", due: due, hasTime: hasTime, urgent: urgent)
    }

    // «2026-10-16» или «2026-10-16 15:00», время — в часовом поясе Mac.
    static func parseDate(_ text: String) -> (Date?, Bool) {
        let parts = text.split(separator: " ").map(String.init)
        guard let day = parts.first else { return (nil, false) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        if parts.count > 1, parts[1].contains(":") {
            formatter.dateFormat = "yyyy-MM-dd H:mm"
            if let date = formatter.date(from: day + " " + parts[1]) { return (date, true) }
        }
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.date(from: day), false)
    }

    public static func format(_ date: Date, withTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = withTime ? "yyyy-MM-dd H:mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func tasks(in text: String, note: URL) -> [NoteTask] {
        text.components(separatedBy: "\n").enumerated().compactMap { parse($0.element, note: note, index: $0.offset) }
    }

    public static func all(in library: NoteLibrary) -> [NoteTask] {
        library.allNotes(in: library.tree()).flatMap { note in
            library.text(of: note).map { tasks(in: $0, note: note.url) } ?? []
        }
    }

    public enum EditError: Error { case changedOnDisk }

    // Задача из календаря: строка дописывается в конец заметки (заметку создаём, если её нет).
    public static func append(_ title: String, due: Date?, hasTime: Bool, urgent: Bool = false,
                              to url: URL, library: NoteLibrary) throws {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var text = (try? library.read(url)) ?? ""
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        let date = due.map { " \(marker) \(format($0, withTime: hasTime))" } ?? ""
        try library.write(text + "- [ ] \(clean)\(urgent ? " !!" : "")\(date)\n", to: url)
    }

    // Отметить задачу (не)сделанной — правим только её строку. Если файл с тех пор поменяли и строки
    // уже нет на месте, ничего не трогаем: иначе можно испортить чужую правку.
    public static func setDone(_ task: NoteTask, _ done: Bool, library: NoteLibrary) throws {
        var lines = try library.read(task.note).components(separatedBy: "\n")
        guard lines.indices.contains(task.line), lines[task.line] == task.raw else { throw EditError.changedOnDisk }
        let line = lines[task.line]
        guard let open = line.range(of: "[") else { return }
        let box = line.index(after: open.lowerBound)
        lines[task.line] = line.replacingCharacters(in: box...box, with: done ? "x" : " ")
        try library.write(lines.joined(separator: "\n"), to: task.note)
    }

    // MARK: - Группы на экране «задачи»

    public enum Group: String, CaseIterable, Sendable {
        case today = "сегодня", week = "на неделе", later = "позже", noDate = "без даты", done = "готово"
    }

    public static func group(_ task: NoteTask, now: Date = Date(), calendar: Calendar = .current) -> Group {
        if task.done { return .done }
        guard let due = task.due else { return .noDate }
        // Просроченное — тоже «сегодня»: его надо сделать сейчас, а не потерять в прошлом.
        if calendar.isDate(due, inSameDayAs: now) || due < calendar.startOfDay(for: now) { return .today }
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now))!
        return due < weekEnd ? .week : .later
    }
}

// План синхронизации с календарём: что создать, обновить и удалить, чтобы события совпали с задачами.
// Сам EventKit — в приложении; здесь только решение, его можно проверить тестом.
public enum CalendarPlan {
    public struct Event: Equatable, Sendable {
        public let title: String
        public let start: Date
        public let allDay: Bool
        public init(title: String, start: Date, allDay: Bool) {
            self.title = title
            self.start = start
            self.allDay = allDay
        }
    }

    public enum Action: Equatable, Sendable {
        case create(key: String, Event)
        case update(key: String, eventID: String, Event)
        case delete(key: String, eventID: String)
    }

    // links — какие задачи уже связаны с какими событиями; existing — что сейчас в событии (nil — удалено руками).
    public static func actions(tasks: [NoteTask], links: [String: String],
                               existing: [String: Event?]) -> [Action] {
        var actions: [Action] = []
        var wanted: Set<String> = []
        for task in tasks where !task.done {
            guard let due = task.due else { continue }
            let event = Event(title: task.title, start: due, allDay: !task.hasTime)
            wanted.insert(task.key)
            if let id = links[task.key], let current = existing[id] {
                if current != event { actions.append(.update(key: task.key, eventID: id, event)) }
            } else {
                // Связи нет или событие удалили в Календаре — создаём заново.
                actions.append(.create(key: task.key, event))
            }
        }
        for (key, id) in links where !wanted.contains(key) {
            actions.append(.delete(key: key, eventID: id))
        }
        return actions.sorted { "\($0)" < "\($1)" }
    }
}
