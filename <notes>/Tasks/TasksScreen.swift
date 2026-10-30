import EventKit
import NotesCore
import SwiftUI

// Задачи — кадр «задачи» (секция «Задачи и календарь»): заголовок, «N открыто | M в календаре»,
// группы «сегодня / на неделе / позже / без даты / готово», строки с линией снизу.
struct TasksScreen: View {
    let model: TasksModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("задачи")
                    .font(Martian.heading.font(26))
                    .kerning(Theme.tracking(-7, size: 26))
                    .foregroundStyle(Theme.ink)
                Text("\(model.count(.all) - model.count(.done)) открыто | \(model.count(.inCalendar)) в календаре")
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(NotesLayout.gray)
                    .padding(.top, 6)

                NewTaskBar(model: model).padding(.top, 24)

                if model.visible.isEmpty {
                    Text(model.tasks.isEmpty
                         ? "задач нет — впиши первую выше или в любой заметке строкой «- [ ] дело»"
                         : "здесь пусто")
                        .font(Martian.body.font(13))
                        .kerning(Theme.tracking(-7, size: 13))
                        .foregroundStyle(NotesLayout.gray)
                        .padding(.top, 46)
                }
                ForEach(NoteTasks.Group.allCases, id: \.self) { group in
                    let items = model.visible.filter { NoteTasks.group($0) == group }
                    if !items.isEmpty {
                        Text(group.rawValue)
                            .font(Martian.body.font(15))
                            .kerning(Theme.tracking(-7, size: 15))
                            .foregroundStyle(Theme.ink)
                            .padding(.top, 26)
                        ForEach(items) { task in TaskRow(model: model, task: task) }
                    }
                }
                if !model.calendar.hasAccess && model.tasks.contains(where: { $0.due != nil }) {
                    Button("дать доступ к календарю, чтобы задачи с датой попали туда") {
                        Task { if await model.calendar.requestAccess() { model.reload() } }
                    }
                    .buttonStyle(QuietLinkStyle(size: 11, opacity: 0.3))
                    .padding(.top, 20)
                }
            }
            .frame(width: 832, alignment: .leading)
            .padding(.leading, 58)
            .padding(.top, 36)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.never)
    }
}

private struct TaskRow: View {
    let model: TasksModel
    let task: NoteTask

    var body: some View {
        let linked = model.calendar.isLinked(task)
        HStack(spacing: 10) {
            Button { model.toggle(task) } label: {
                DotIcon(glyph: task.done ? .taskDone : .task,
                        color: task.done ? Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255) : Theme.ink)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.done ? "вернуть" : "готово")
            if task.urgent {
                Text("!!").font(Martian.heading.font(13)).foregroundStyle(Theme.coral).help("срочно")
            }
            // Текст задачи — то, что ввёл человек: регистр не трогаем.
            Text(task.title)
                .font(Martian.body.font(13))
                .kerning(Theme.tracking(-7, size: 13))
                .foregroundStyle(Theme.ink.opacity(task.done ? 0.4 : 1))
                .lineLimit(1)
            Text(model.library.breadcrumb(for: task.note).joined(separator: " / "))
                .font(Martian.body.font(11))
                .kerning(Theme.tracking(-7, size: 11))
                .foregroundStyle(NotesLayout.gray)
                .lineLimit(1)
            Spacer(minLength: 10)
            if let when = model.when(task) {
                Text(when)
                    .font(Martian.body.font(11))
                    .kerning(Theme.tracking(-7, size: 11))
                    .foregroundStyle(linked ? Theme.coral : NotesLayout.gray)
            }
            if linked { DotIcon(glyph: .calendar, color: Theme.coral) }
        }
        .padding(.horizontal, 4)
        .frame(height: 35)
        .overlay(alignment: .bottom) { Rectangle().fill(NotesLayout.line).frame(height: 1) }
        .padding(.top, 6)
    }
}

// Календарь — кадр «календарь»: неделя с часами 9–17, сегодня коралловым, события — серые плашки,
// задачи из заметок — коралловые. Переключатель «день / неделя / месяц» как в поиске.
struct CalendarScreen: View {
    let tasks: TasksModel
    // Загруженные на расшифровку видео — серой строкой в день загрузки.
    var uploads: [VideoModel.Item] = []
    enum Mode: String, CaseIterable { case day = "день", week = "неделя", month = "месяц" }
    @State private var mode: Mode = .week
    @State private var anchor = Date()
    // Задача, которую сейчас вписывают: время начала.
    @State private var draft: Date?

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(Martian.heading.font(26))
                        .kerning(Theme.tracking(-7, size: 26))
                        .foregroundStyle(Theme.ink)
                    Text(tasks.calendar.hasAccess ? "синхронизировано с apple calendar" : "нет доступа к календарю")
                        .font(Martian.body.font(13))
                        .kerning(Theme.tracking(-7, size: 13))
                        .foregroundStyle(NotesLayout.gray)
                }
                Spacer()
                // Листать: ‹ сегодня › — раньше только стрелками с клавиатуры, и то не всегда.
                HStack(spacing: 4) {
                    Button { shift(-1) } label: { IconButtonLabel(glyph: .chevronLeft) }.buttonStyle(.plain)
                    Button("сегодня") { withAnimation(.smooth(duration: 0.4)) { anchor = Date() } }
                        .buttonStyle(QuietLinkStyle(size: 13, opacity: 0.6))
                    Button { shift(1) } label: { IconButtonLabel(glyph: .chevronRight) }.buttonStyle(.plain)
                }
                .padding(.trailing, 8).padding(.top, 2)
                // Плюс — новая задача на ближайший час сегодня (или на выбранный день).
                Button {
                    mode = mode == .month ? .day : mode
                    let hour = Calendar.current.component(.hour, from: Date()) + 1
                    draft = Calendar.current.date(bySettingHour: min(max(hour, 9), 16), minute: 0, second: 0,
                                                  of: mode == .day ? anchor : Date())
                } label: { IconButtonLabel(glyph: .plus) }
                    .buttonStyle(.plain).help("новая задача").padding(.trailing, 8).padding(.top, 2)
                HStack(spacing: 2) {
                    ForEach(Mode.allCases, id: \.self) { item in
                        Button { withAnimation(.smooth(duration: 0.4)) { mode = item } } label: { ModeChip(title: item.rawValue, on: mode == item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Capsule().fill(Theme.bg.opacity(0.45)))
                .overlay(Capsule().strokeBorder(Theme.edge.opacity(0.75), lineWidth: 1))
                .padding(.top, 4)
            }
            .frame(width: 832)

            if tasks.calendar.hasAccess {
                Group {
                    switch mode {
                    case .day: DayGrid(days: [calendar.startOfDay(for: anchor)], tasks: tasks, uploads: uploads, draft: $draft)
                    case .week: DayGrid(days: week, tasks: tasks, uploads: uploads, draft: $draft)
                    case .month: MonthGrid(month: anchor, calendar: calendar, tasks: tasks) { anchor = $0; mode = .day }
                    }
                }
                // Неделя, день, месяц и листание — мягким размытием, как разделы.
                .id("\(mode)-\(Int(anchor.timeIntervalSince1970 / 86_400))")
                .transition(.blurReplace)
                .padding(.top, 30)
            } else {
                Button("дать доступ") { Task { _ = await tasks.calendar.requestAccess(); anchor = Date() } }
                    .buttonStyle(CoralCapsuleStyle())
                    .padding(.top, 40)
            }
        }
        .padding(.leading, 58)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Стрелки ← → листают неделю, день или месяц.
        .onKeyPress(.leftArrow) { shift(-1); return .handled }
        .onKeyPress(.rightArrow) { shift(1); return .handled }
        .focusable()
        .focusEffectDisabled()
    }

    private var week: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    private var title: String {
        let ru = Locale(identifier: "ru_RU")
        switch mode {
        case .day: return anchor.formatted(.dateTime.day().month(.wide).locale(ru))
        case .week:
            let days = week
            return "\(calendar.component(.day, from: days[0])) – " + days[6].formatted(.dateTime.day().month(.wide).locale(ru))
        case .month: return anchor.formatted(Date.FormatStyle(locale: ru).month(.wide).year()).lowercased()
        }
    }

    private func shift(_ step: Int) {
        let unit: Calendar.Component = mode == .day ? .day : mode == .week ? .weekOfYear : .month
        withAnimation(.smooth(duration: 0.4)) { anchor = calendar.date(byAdding: unit, value: step, to: anchor) ?? anchor }
    }
}

private struct ModeChip: View {
    let title: String
    let on: Bool

    var body: some View {
        Text(title)
            .font(Martian.body.font(13))
            .kerning(Theme.tracking(-7, size: 13))
            .foregroundStyle(on ? Theme.ink : NotesLayout.gray)
            .padding(.horizontal, 10)
            .frame(height: 21)
            .background(Capsule().fill(on ? Theme.bg : .clear).shadow(color: .black.opacity(0.08), radius: 3))
            .contentShape(Capsule())
    }
}

// Колонки дней на сутки 0:00–23:59 с прокруткой, открываются на 8:00. Пересекающиеся события стоят
// рядом, а не друг на друге (раньше всё после 17:00 прижималось к низу и налезало).
private struct DayGrid: View {
    let days: [Date]
    let tasks: TasksModel
    let uploads: [VideoModel.Item]
    @Binding var draft: Date?
    private let gutter: CGFloat = 44, hour: CGFloat = 44, head: CGFloat = 44

    var body: some View {
        let colW = (832 - gutter) / CGFloat(days.count)
        let events = tasks.calendar.events(from: days[0], to: Calendar.current.date(byAdding: .day, value: 1, to: days.last!)!)
        let lanes = Self.lanes(events)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let today = Calendar.current.isDateInToday(day)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ru_RU"))).lowercased())
                            .font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
                        HStack(spacing: 6) {
                            Text("\(Calendar.current.component(.day, from: day))")
                                .font(Martian.heading.font(15)).foregroundStyle(today ? Theme.coral : Theme.ink)
                            let count = uploads.filter { Calendar.current.isDate($0.added, inSameDayAs: day) }.count
                            if count > 0 {
                                DotIcon(glyph: .video, size: 12, color: NotesLayout.gray).help("видео на расшифровку: \(count)")
                            }
                        }
                    }
                    .offset(x: gutter + CGFloat(index) * colW + 6)
                }
            }
            .frame(width: 832, height: head, alignment: .topLeading)

            ScrollViewReader { scroll in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<24, id: \.self) { h in
                            Rectangle().fill(NotesLayout.line).frame(width: 832 - gutter, height: 1)
                                .offset(x: gutter, y: CGFloat(h) * hour)
                            Text("\(h):00").font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
                                .offset(y: CGFloat(h) * hour - 6).id(h)
                        }
                        // Клик по пустому месту — новая задача на этот час, с шагом полчаса.
                        Color.clear.contentShape(Rectangle())
                            .frame(width: 832 - gutter, height: 24 * hour)
                            .offset(x: gutter)
                            .onTapGesture { point in
                                let column = min(Int(point.x / colW), days.count - 1)
                                let half = (point.y / (hour / 2)).rounded(.down) / 2
                                draft = Calendar.current.date(byAdding: .minute, value: Int(half * 60), to: days[column])
                            }
                        ForEach(events, id: \.eventIdentifier) { event in
                            if let column = days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: event.startDate) }) {
                                let lane = lanes[event.eventIdentifier] ?? (0, 1)
                                let width = (colW - 6) / CGFloat(lane.1)
                                EventBlock(event: event, task: tasks.calendar.isTaskEvent(event))
                                    .frame(width: width - 2, height: height(event))
                                    .offset(x: gutter + CGFloat(column) * colW + 3 + CGFloat(lane.0) * width, y: top(event) + 2)
                            }
                        }
                        if let start = draft, let column = days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: start) }) {
                            RoundedRectangle(cornerRadius: 10).fill(Theme.coral.opacity(0.12))
                                .frame(width: colW - 6, height: hour - 4)
                                .offset(x: gutter + CGFloat(column) * colW + 3, y: top(at: start) + 2)
                                .popover(isPresented: Binding(get: { draft != nil }, set: { if !$0 { draft = nil } }), arrowEdge: .trailing) {
                                    NewTaskPopover(start: start) { title, due, hasTime in
                                        tasks.add(title, due: due, hasTime: hasTime)
                                        draft = nil
                                    }
                                }
                        }
                    }
                    .frame(width: 832, height: 24 * hour + 10, alignment: .topLeading)
                    .padding(.top, 6)
                }
                .scrollIndicators(.never)
                .onAppear { scroll.scrollTo(8, anchor: .top) }
            }
        }
    }

    private func top(at date: Date) -> CGFloat {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (CGFloat(parts.hour ?? 0) + CGFloat(parts.minute ?? 0) / 60) * hour
    }

    private func top(_ event: EKEvent) -> CGFloat { event.isAllDay ? 0 : top(at: event.startDate) }

    private func height(_ event: EKEvent) -> CGFloat {
        if event.isAllDay { return 20 }
        return max(CGFloat(event.endDate.timeIntervalSince(event.startDate) / 3600) * hour - 4, 22)
    }

    // Пересекающиеся по времени события одного дня — в соседние дорожки: (номер, сколько всего).
    static func lanes(_ events: [EKEvent]) -> [String: (Int, Int)] {
        var result: [String: (Int, Int)] = [:]
        let byDay = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.startDate) }
        for (_, day) in byDay {
            var cluster: [EKEvent] = [], ends: [Date] = [], clusterEnd = Date.distantPast
            func close() { for e in cluster { result[e.eventIdentifier] = (result[e.eventIdentifier]?.0 ?? 0, max(ends.count, 1)) }; cluster = []; ends = [] }
            for event in day.sorted(by: { $0.startDate < $1.startDate }) {
                let end = max(event.endDate, event.startDate.addingTimeInterval(1800))
                if event.startDate >= clusterEnd { close() }
                let lane = ends.firstIndex { $0 <= event.startDate } ?? ends.count
                if lane == ends.count { ends.append(end) } else { ends[lane] = end }
                result[event.eventIdentifier] = (lane, 1)
                cluster.append(event)
                clusterEnd = max(clusterEnd, end)
            }
            close()
        }
        return result
    }
}

private struct EventBlock: View {
    let event: EKEvent
    let task: Bool

    var body: some View {
        GeometryReader { geo in
            // Короткое событие — одной строкой «название · время», иначе текст налезал на соседей.
            Group {
                if geo.size.height < 38 || event.isAllDay {
                    Text("\(event.title ?? "")\(event.isAllDay ? "" : " · " + event.startDate.formatted(.dateTime.hour().minute()))")
                        .lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title ?? "").lineLimit(max(1, Int((geo.size.height - 24) / 14)))
                        Text(event.startDate.formatted(.dateTime.hour().minute()))
                            .foregroundStyle(task ? Theme.coral : NotesLayout.gray)
                    }
                }
            }
            .font(Martian.body.font(11)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(task ? Theme.coral.opacity(0.14) : Theme.fg.opacity(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// Месяц: сетка 7 × 6, в ячейке — число и до трёх событий строчками.
private struct MonthGrid: View {
    let month: Date
    let calendar: Calendar
    let tasks: TasksModel
    let openDay: (Date) -> Void

    var body: some View {
        let start = calendar.dateInterval(of: .weekOfYear, for: calendar.dateInterval(of: .month, for: month)!.start)!.start
        let days = (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        let events = tasks.calendar.events(from: days[0], to: days[41])
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(832 / 7 - 4), spacing: 4), count: 7), spacing: 4) {
            ForEach(days, id: \.self) { day in
                let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(calendar.component(.day, from: day))")
                        .font(Martian.heading.font(13))
                        .foregroundStyle(calendar.isDateInToday(day) ? Theme.coral : Theme.ink.opacity(inMonth ? 1 : 0.3))
                    ForEach(events.filter { calendar.isDate($0.startDate, inSameDayAs: day) }.prefix(3), id: \.eventIdentifier) { event in
                        Text(event.title ?? "")
                            .font(Martian.body.font(10))
                            .foregroundStyle(tasks.calendar.isTaskEvent(event) ? Theme.coral : NotesLayout.gray)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(height: 70, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.fg.opacity(0.03)))
                .contentShape(Rectangle())
                .onTapGesture { openDay(day) }
            }
        }
        .frame(width: 832)
    }
}

// Новая задача из календаря — как быстрое событие в Календаре Apple: сразу печатаешь название, Enter — готово.
// Под названием одна строка: когда (можно поменять) и «весь день». Длительность — из настроек календаря.
private struct NewTaskPopover: View {
    let start: Date
    let add: (String, Date, Bool) -> Void
    @State private var title = ""
    @State private var date = Date()
    @State private var allDay = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("новая задача", text: $title)
                .textFieldStyle(.plain)
                .font(Martian.heading.font(17))
                .focused($focused)
                .onSubmit(save)
            HStack(spacing: 8) {
                DatePicker("", selection: $date, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).font(Martian.body.font(13))
                Toggle("весь день", isOn: $allDay).toggleStyle(.checkbox).font(Martian.body.font(13))
            }
            Text("enter — добавить, esc — закрыть")
                .font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .onAppear { date = start; focused = true }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        add(title, date, !allDay)
    }
}

// Новая задача прямо на экране задач: пишешь, Enter — готово. Срок и срочность — по желанию,
// одним кликом. Задача ложится строкой во «Входящие.md».
private struct NewTaskBar: View {
    let model: TasksModel
    @State private var title = ""
    @State private var withDate = false
    @State private var date = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var urgent = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            DotIcon(glyph: .plus)
            TextField("новая задача", text: $title)
                .textFieldStyle(.plain)
                .font(Martian.body.font(15))
                .focused($focused)
                .onSubmit(save)
            if withDate {
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).font(Martian.body.font(12))
            }
            Button { withDate.toggle() } label: {
                DotIcon(glyph: .calendar, color: withDate ? Theme.coral : NotesLayout.gray)
            }.buttonStyle(.plain).help(withDate ? "без срока" : "со сроком — уйдёт в календарь")
            Button { urgent.toggle() } label: {
                Text("!!").font(Martian.heading.font(13)).foregroundStyle(urgent ? Theme.coral : NotesLayout.gray)
            }.buttonStyle(.plain).help("срочно")
        }
        .padding(.horizontal, 14)
        .frame(width: 832, height: 44)
        .background(Capsule().fill(Theme.fg.opacity(0.04)))
        .overlay(Capsule().strokeBorder(focused ? Theme.coral.opacity(0.5) : .clear, lineWidth: 1))
        .animation(.smooth(duration: 0.25), value: withDate)
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.add(title, due: withDate ? date : nil, hasTime: true, urgent: urgent)
        title = ""; urgent = false
        focused = true
    }
}
