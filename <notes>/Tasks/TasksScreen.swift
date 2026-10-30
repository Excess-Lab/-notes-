import EventKit
import NotesCore
import SwiftUI

// Задачи — кадр «задачи» (секция «Задачи и календарь»): заголовок, «N открыто | M в календаре»,
// группы «сегодня / на неделе / позже / без даты / готово», строки с линией снизу.
struct TasksScreen: View {
    @Environment(\.pageWidth) private var page
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
                        ForEach(items) { task in
                            TaskRow(model: model, task: task)
                                .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
                        }
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
            .frame(width: min(832, page), alignment: .leading)
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
    // Отметили — галочка и зачёркивание сразу, а строка уходит через полсекунды плавно (ТЗ 30.10.2026).
    @State private var checking = false
    @Environment(\.undoManager) private var undo

    var body: some View {
        let linked = model.calendar.isLinked(task)
        let done = task.done != checking
        HStack(spacing: 10) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { checking = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.smooth(duration: 0.45)) { model.toggle(task, undo: undo) }
                    checking = false
                }
            } label: {
                DotIcon(glyph: done ? .taskDone : .task,
                        color: done ? Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255) : Theme.ink)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(checking)
            .help(task.done ? "вернуть" : "готово")
            if task.urgent {
                Text("!!").font(Martian.heading.font(13)).foregroundStyle(Theme.coral).help("срочно")
            }
            // Текст задачи — то, что ввёл человек: регистр не трогаем.
            Text(task.title)
                .font(Martian.body.font(13))
                .kerning(Theme.tracking(-7, size: 13))
                .foregroundStyle(Theme.ink.opacity(done ? 0.4 : 1))
                .strikethrough(done && !task.done, color: Theme.ink.opacity(0.4))
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
    @Environment(\.pageWidth) private var page
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
            // Узкое окно — кнопки уходят под заголовок, а не сжимают его в столбик (31.10.2026).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) {
                    header
                    Spacer()
                    controls
                }
                VStack(alignment: .leading, spacing: 16) {
                    header
                    HStack(alignment: .top, spacing: 0) { controls }
                }
            }
            .frame(width: page)

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
        .onAppear(perform: takeFocus)
        .onChange(of: tasks.calendar.focus) { takeFocus() }
    }

    // Событие из поиска — открываем его день.
    private func takeFocus() {
        guard let date = tasks.calendar.focus else { return }
        anchor = date
        mode = .day
        tasks.calendar.focus = nil
    }

    private var header: some View {
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
        .fixedSize()
    }

    @ViewBuilder private var controls: some View {
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
    @Environment(\.pageWidth) private var page
    let days: [Date]
    let tasks: TasksModel
    let uploads: [VideoModel.Item]
    @Binding var draft: Date?
    @State private var draftEnd: Date?
    @State private var dragging = false
    @State private var position = ScrollPosition(y: 8 * 44)
    private let gutter: CGFloat = 44, hour: CGFloat = 44, head: CGFloat = 44

    var body: some View {
        let colW = (page - gutter) / CGFloat(days.count)
        let events = tasks.calendar.events(from: days[0], to: Calendar.current.date(byAdding: .day, value: 1, to: days.last!)!)
        let lanes = Self.lanes(events)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let today = Calendar.current.isDateInToday(day)
                    VStack(alignment: .leading, spacing: 2) {
                        // Значок видео — у дня недели: рядом с числом он прилипал к числу соседнего дня.
                        HStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ru_RU"))).lowercased())
                                .font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
                            let count = uploads.filter { Calendar.current.isDate($0.added, inSameDayAs: day) }.count
                            if count > 0 {
                                DotIcon(glyph: .video, size: 11, color: NotesLayout.gray).help("видео на расшифровку: \(count)")
                            }
                        }
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(Martian.heading.font(15)).foregroundStyle(today ? Theme.coral : Theme.ink)
                    }
                    // Подпись дня — строго в своей колонке: значок видео раньше налезал на число соседнего дня.
                    .frame(width: colW - 8, alignment: .leading)
                    .clipped()
                    .offset(x: gutter + CGFloat(index) * colW + 6)
                }
            }
            .frame(width: page, height: head, alignment: .topLeading)

            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(0..<24, id: \.self) { h in
                        Rectangle().fill(NotesLayout.line).frame(width: page - gutter, height: 1)
                            .offset(x: gutter, y: CGFloat(h) * hour)
                        Text("\(h):00").font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
                            .offset(y: CGFloat(h) * hour - 6)
                    }
                    // Клик по пустому месту — задача на час; протянуть — сразу задать период. Шаг — 15 минут.
                    Color.clear.contentShape(Rectangle())
                        .frame(width: page - gutter, height: 24 * hour)
                        .offset(x: gutter)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let column = max(0, min(Int(drag.startLocation.x / colW), days.count - 1))
                                func at(_ y: CGFloat) -> Date {
                                    let quarters = max(0, min(96, Int((y / (hour / 4)).rounded(.down))))
                                    return Calendar.current.date(byAdding: .minute, value: quarters * 15, to: days[column])!
                                }
                                let a = at(drag.startLocation.y), b = at(drag.location.y)
                                dragging = true
                                draft = min(a, b)
                                let end = max(a, b).addingTimeInterval(15 * 60)
                                draftEnd = abs(drag.translation.height) < 6 ? draft!.addingTimeInterval(3600) : end
                            }
                            .onEnded { _ in dragging = false })
                    ForEach(events, id: \.slot) { event in
                        if let column = days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: event.startDate) }) {
                            let lane = lanes[event.slot] ?? (0, 1)
                            let width = (colW - 6) / CGFloat(lane.1)
                            EventBlock(event: event, task: tasks.calendar.isTaskEvent(event))
                                .frame(width: width - 2, height: height(event))
                                .offset(x: gutter + CGFloat(column) * colW + 3 + CGFloat(lane.0) * width, y: top(event) + 1.5)
                        }
                    }
                    if let start = draft, let column = days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: start) }) {
                        let end = draftEnd ?? start.addingTimeInterval(3600)
                        RoundedRectangle(cornerRadius: 10).fill(Theme.coral.opacity(0.18))
                            .overlay(alignment: .topLeading) {
                                Text(Self.span(start, end)).font(Martian.body.font(11)).foregroundStyle(Theme.coral).padding(6)
                            }
                            .frame(width: colW - 6, height: max(hour / 4, CGFloat(end.timeIntervalSince(start) / 3600) * hour) - 4)
                            .offset(x: gutter + CGFloat(column) * colW + 3, y: top(at: start) + 2)
                            .popover(isPresented: Binding(get: { draft != nil && !dragging }, set: { if !$0 { draft = nil; draftEnd = nil } }), arrowEdge: .trailing) {
                                NewTaskPopover(start: start, minutes: Int(end.timeIntervalSince(start) / 60)) { title, due, hasTime, minutes in
                                    tasks.add(title, due: due, hasTime: hasTime, minutes: minutes)
                                    draft = nil; draftEnd = nil
                                }
                            }
                    }
                }
                .frame(width: page, height: 24 * hour + 10, alignment: .topLeading)
                .padding(.top, 6)
            }
            .scrollIndicators(.never)
            // Сетка открывается на 8:00. scrollTo по id не срабатывал: метки часов сдвинуты offset'ом,
            // их рамки остаются наверху, и сетка висела на полуночи.
            .scrollPosition($position)
        }
    }

    static func span(_ start: Date, _ end: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "H:mm"
        return "\(f.string(from: start))–\(f.string(from: end))"
    }

    private func top(at date: Date) -> CGFloat {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (CGFloat(parts.hour ?? 0) + CGFloat(parts.minute ?? 0) / 60) * hour
    }

    private func top(_ event: EKEvent) -> CGFloat { event.isAllDay ? 0 : top(at: event.startDate) }

    // Высота — ровно по длительности (не меньше 20 минут), с тем же зазором, что у часовых. Раньше короткие
    // растягивались до 22 pt и наезжали на следующее событие — выглядело как наложение, хотя его нет.
    private func height(_ event: EKEvent) -> CGFloat {
        if event.isAllDay { return 20 }
        return CGFloat(Self.shown(event).timeIntervalSince(event.startDate) / 3600) * hour - 3
    }

    // Конец, каким событие нарисовано: дорожки считаются по нему же, чтобы видимое и расчёт совпадали.
    static func shown(_ event: EKEvent) -> Date { max(event.endDate, event.startDate.addingTimeInterval(20 * 60)) }

    // Пересекающиеся по времени события одного дня — в соседние дорожки: (номер, сколько всего).
    static func lanes(_ events: [EKEvent]) -> [String: (Int, Int)] {
        var result: [String: (Int, Int)] = [:]
        let byDay = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.startDate) }
        for (_, day) in byDay {
            var cluster: [EKEvent] = [], ends: [Date] = [], clusterEnd = Date.distantPast
            func close() { for e in cluster { result[e.slot] = (result[e.slot]?.0 ?? 0, max(ends.count, 1)) }; cluster = []; ends = [] }
            for event in day.sorted(by: { $0.startDate < $1.startDate }) {
                let end = shown(event)
                if event.startDate >= clusterEnd { close() }
                let lane = ends.firstIndex { $0 <= event.startDate } ?? ends.count
                if lane == ends.count { ends.append(end) } else { ends[lane] = end }
                result[event.slot] = (lane, 1)
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
                if geo.size.width < 40 {
                    // Узкая дорожка — только цвет: текст рвался по буквам в столбик.
                    Color.clear
                } else if geo.size.height < 38 || event.isAllDay {
                    Text("\(event.title ?? "")\(event.isAllDay ? "" : " · " + event.startDate.formatted(.dateTime.hour().minute()))")
                        .lineLimit(1)
                        .font(Martian.body.font(geo.size.height < 20 ? 9 : 11))
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title ?? "").lineLimit(max(1, Int((geo.size.height - 24) / 14)))
                        Text(event.startDate.formatted(.dateTime.hour().minute()))
                            .foregroundStyle(task ? Theme.coral : NotesLayout.gray)
                    }
                }
            }
            .font(Martian.body.font(11)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 8).padding(.vertical, geo.size.height < 24 ? 1 : 4)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(task ? Theme.coral.opacity(0.14) : Theme.fg.opacity(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// Месяц: сетка 7 × 6, в ячейке — число и до трёх событий строчками.
private struct MonthGrid: View {
    @Environment(\.pageWidth) private var page
    let month: Date
    let calendar: Calendar
    let tasks: TasksModel
    let openDay: (Date) -> Void

    var body: some View {
        let start = calendar.dateInterval(of: .weekOfYear, for: calendar.dateInterval(of: .month, for: month)!.start)!.start
        let days = (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        let events = tasks.calendar.events(from: days[0], to: days[41])
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(page / 7 - 4), spacing: 4), count: 7), spacing: 4) {
            ForEach(days, id: \.self) { day in
                let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(calendar.component(.day, from: day))")
                        .font(Martian.heading.font(13))
                        .foregroundStyle(calendar.isDateInToday(day) ? Theme.coral : Theme.ink.opacity(inMonth ? 1 : 0.3))
                    ForEach(events.filter { calendar.isDate($0.startDate, inSameDayAs: day) }.prefix(3), id: \.slot) { event in
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
        .frame(width: page)
    }
}

// Новая задача из календаря — как быстрое событие в Календаре Apple: сразу печатаешь название, Enter — готово.
// Под названием одна строка: когда (можно поменять) и «весь день». Длительность — из настроек календаря.
private struct NewTaskPopover: View {
    let start: Date
    @State var minutes: Int
    let add: (String, Date, Bool, Int?) -> Void
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
                DatePicker("", selection: $date, displayedComponents: [.date])
                    .labelsHidden().datePickerStyle(.field).font(Martian.body.font(13))
                Toggle("весь день", isOn: $allDay).toggleStyle(.checkbox).font(Martian.body.font(13))
            }
            if !allDay {
                // Начало и конец — две ячейки; конец не раньше начала + 15 минут.
                HStack(spacing: 8) {
                    Text("начало").font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
                    DatePicker("", selection: $date, displayedComponents: [.hourAndMinute])
                        .labelsHidden().datePickerStyle(.field)
                    Text("конец").font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
                    DatePicker("", selection: Binding(get: { date.addingTimeInterval(TimeInterval(minutes * 60)) },
                                                      set: { minutes = max(15, Int($0.timeIntervalSince(date) / 60)) }),
                               displayedComponents: [.hourAndMinute])
                        .labelsHidden().datePickerStyle(.field)
                }
                .font(Martian.body.font(13))
            }
            Text("enter — добавить")
                .font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .onAppear { date = start; focused = true }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        add(title, date, !allDay, allDay ? nil : minutes)
    }
}

// Новая задача прямо на экране задач: пишешь, Enter — готово. Срок и срочность — по желанию,
// одним кликом. Задача ложится строкой во «Входящие.md».
private struct NewTaskBar: View {
    @Environment(\.pageWidth) private var page
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
        .frame(width: min(832, page), height: 44)
        .background(Capsule().fill(Theme.fg.opacity(0.04)))
        .overlay(Capsule().strokeBorder(focused ? Theme.coral.opacity(0.5) : .clear, lineWidth: 1))
        // Плюс справа сверху — сюда, в строку новой задачи.
        .onChange(of: model.focusNew) { focused = true }
        .animation(.smooth(duration: 0.25), value: withDate)
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.add(title, due: withDate ? date : nil, hasTime: true, urgent: urgent)
        title = ""; urgent = false
        focused = true
    }
}

// У повторов одного события общий eventIdentifier: по нему ForEach и дорожки путали повторы между собой —
// события съезжали в чужие дни и делили ширину, как будто наложены (ТЗ: «ненакладывающиеся выглядят наложенными»).
extension EKEvent {
    var slot: String { "\(eventIdentifier ?? "")@\(startDate.timeIntervalSince1970)" }
}
