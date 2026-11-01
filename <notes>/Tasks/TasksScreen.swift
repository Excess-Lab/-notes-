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
                Text(String(localized: "\(model.count(.all) - model.count(.done)) открыто | \(model.count(.inCalendar)) в календаре"))
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(NotesLayout.gray)
                    .padding(.top, 6)

                NewTaskBar(model: model).padding(.top, 24)

                if model.visible.isEmpty {
                    Text(model.tasks.isEmpty
                         ? "задач нет. добавь выше или строкой «- [ ] дело» в заметке"
                         : "здесь пусто")
                        .font(Martian.body.font(13))
                        .kerning(Theme.tracking(-7, size: 13))
                        .foregroundStyle(NotesLayout.gray)
                        .padding(.top, 46)
                }
                ForEach(NoteTasks.Group.allCases, id: \.self) { group in
                    let items = model.visible.filter { NoteTasks.group($0) == group }
                    if !items.isEmpty {
                        Text(LocalizedStringKey(group.rawValue))
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
                    Button("чтобы задачи с датой попадали в календарь") {
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
    @State private var titleHeight: CGFloat = 60
    // Сколько сверху занято заголовком (с отступом листа): на столько сетка заходит под него.
    private var inset: CGFloat { 36 + titleHeight }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .app
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
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { titleHeight = $0 }
            .zIndex(1)

            if tasks.calendar.hasAccess {
                Group {
                    switch mode {
                    case .day: DayGrid(days: [calendar.startOfDay(for: anchor)], tasks: tasks, uploads: uploads, draft: $draft, inset: inset)
                    case .week: DayGrid(days: week, tasks: tasks, uploads: uploads, draft: $draft, inset: inset)
                    case .month: MonthGrid(month: anchor, calendar: calendar, tasks: tasks) { anchor = $0; mode = .day }
                    }
                }
                // Неделя, день, месяц и листание — мягким размытием, как разделы.
                .id("\(mode)-\(Int(anchor.timeIntervalSince1970 / 86_400))")
                .transition(.blurReplace)
                // День и неделя — сетка уходит под заголовок: шапка сверху цвета листа, книзу прозрачная
                // с размытием (01.11.2026). Месяц — как был, под заголовком.
                .padding(.top, mode == .month ? 30 : -inset)
            } else {
                Button("дать доступ") { Task { _ = await tasks.calendar.requestAccess(); anchor = Date() } }
                    .buttonStyle(CoralCapsuleStyle())
                    .padding(.top, 40)
            }
        }
        .padding(.leading, 58)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        // Стрелки ← → листают неделю, день или месяц.
        .onKeyPress(.leftArrow) { shift(-1); return .handled }
        .onKeyPress(.rightArrow) { shift(1); return .handled }
        .background {
            // ⌘T — сегодня, как в Календаре Apple.
            Button("") { withAnimation(.smooth(duration: 0.4)) { anchor = Date() } }
                .keyboardShortcut("t", modifiers: .command).opacity(0).allowsHitTesting(false)
        }
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
            Text(LocalizedStringKey(title))
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
        let ru = Locale.app
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
        Text(LocalizedStringKey(title))
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
    var inset: CGFloat = 0
    @State private var draftEnd: Date?
    @State private var dragging = false
    @State private var position = ScrollPosition(y: 8 * 44)
    // Перетаскиваемое событие: сдвиг на целые дни и четверти часа; растягиваемое — на четверти.
    @State private var moving: (slot: String, days: Int, quarters: Int)?
    @State private var resizing: (slot: String, quarters: Int)?
    @State private var opened: String?
    @Environment(\.undoManager) private var undo
    private let gutter: CGFloat = 44, hour: CGFloat = 44, head: CGFloat = 44

    var body: some View {
        let colW = (page - gutter) / CGFloat(days.count)
        let all = tasks.calendar.events(from: days[0], to: Calendar.current.date(byAdding: .day, value: 1, to: days.last!)!)
        // События на весь день — отдельной строкой над сеткой, как в Календаре Apple; раньше лежали на 0:00.
        let allDay = all.filter(\.isAllDay)
        let events = all.filter { !$0.isAllDay }
        let lanes = Self.lanes(events)
        let perDay = days.map { day in allDay.filter { Self.covers($0, day) } }
        let most = perDay.map(\.count).max() ?? 0
        // Над сеткой: место заголовка экрана, дни, строка «весь день». Сетка прокручивается под этим.
        let above = inset + head + (most > 0 ? CGFloat(most) * 22 + 6 : 0)
        ZStack(alignment: .topLeading) {
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Разделители дней — вертикальные линии, как в Календаре Apple: без них неделя сливалась.
                    ForEach(1..<max(1, days.count), id: \.self) { i in
                        Rectangle().fill(NotesLayout.line).frame(width: 1, height: 24 * hour)
                            .offset(x: gutter + CGFloat(i) * colW)
                    }
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
                            timed(event, column: column, colW: colW, lanes: lanes)
                        }
                    }
                    // Линия «сейчас» — красная черта с точкой в колонке сегодняшнего дня.
                    if let today = days.firstIndex(where: { Calendar.current.isDateInToday($0) }) {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            HStack(spacing: 0) {
                                Circle().fill(Theme.coral).frame(width: 7, height: 7)
                                Rectangle().fill(Theme.coral).frame(width: colW - 4, height: 1.5)
                            }
                            .offset(x: gutter + CGFloat(today) * colW - 3, y: top(at: context.date) - 3.5)
                            // Сколько сейчас — плашкой слева, поверх подписей часов.
                            Text(context.date.formatted(.dateTime.hour().minute()))
                                .font(Martian.body.font(10)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.coral))
                                .offset(x: -4, y: top(at: context.date) - 8)
                        }
                        .allowsHitTesting(false)
                        .zIndex(2)
                    }
                    if let start = draft, let column = days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: start) }) {
                        let end = draftEnd ?? start.addingTimeInterval(3600)
                        RoundedRectangle(cornerRadius: 10).fill(Theme.coral.opacity(0.18))
                            .overlay(alignment: .topLeading) {
                                Text(Self.span(start, end)).font(Martian.body.font(11)).foregroundStyle(Theme.coral).padding(6)
                            }
                            .frame(width: colW - 6, height: max(hour / 4, CGFloat(end.timeIntervalSince(start) / 3600) * hour) - 4)
                            // Попап — до offset: после него он цеплялся за исходное место (левый верх сетки),
                            // и задача «создавалась непонятно где» (01.11.2026).
                            .popover(isPresented: Binding(get: { draft != nil && !dragging }, set: { if !$0 { draft = nil; draftEnd = nil } }), arrowEdge: .trailing) {
                                NewTaskPopover(start: start, minutes: Int(end.timeIntervalSince(start) / 60)) { title, due, hasTime, minutes in
                                    tasks.add(title, due: due, hasTime: hasTime, minutes: minutes)
                                    draft = nil; draftEnd = nil
                                }
                            }
                            .offset(x: gutter + CGFloat(column) * colW + 3, y: top(at: start) + 2)
                    }
                }
                .frame(width: page, height: 24 * hour + 10, alignment: .topLeading)
                .padding(.top, above + 6)
            }
            .scrollIndicators(.never)
            // Сетка открывается на 8:00. scrollTo по id не срабатывал: метки часов сдвинуты offset'ом,
            // их рамки остаются наверху, и сетка висела на полуночи.
            .scrollPosition($position)
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: inset)
            ZStack(alignment: .topLeading) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let today = Calendar.current.isDateInToday(day)
                    VStack(alignment: .leading, spacing: 2) {
                        // Значок видео — у дня недели: рядом с числом он прилипал к числу соседнего дня.
                        HStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated).locale(.app)).lowercased())
                                .font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
                            let count = uploads.filter { Calendar.current.isDate($0.added, inSameDayAs: day) }.count
                            if count > 0 {
                                DotIcon(glyph: .video, size: 11, color: NotesLayout.gray).help(String(localized: "видео: \(count)"))
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

            if let most = perDay.map(\.count).max(), most > 0 {
                ZStack(alignment: .topLeading) {
                    Text("весь день").font(Martian.body.font(9)).foregroundStyle(NotesLayout.gray).offset(y: 4)
                    ForEach(Array(perDay.enumerated()), id: \.offset) { index, list in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(list, id: \.slot) { event in
                                EventBlock(event: event, task: tasks.calendar.isTaskEvent(event))
                                    .frame(width: colW - 6, height: 20)
                                    .onTapGesture { opened = event.slot }
                                    .popover(isPresented: openBinding(event)) { EventCard(event: event, tasks: tasks) { opened = nil } }
                                    .contextMenu { EventMenu(event: event, tasks: tasks) { opened = event.slot } }
                            }
                        }
                        .offset(x: gutter + CGFloat(index) * colW + 3)
                    }
                }
                .frame(width: page, height: CGFloat(most) * 22 + 6, alignment: .topLeading)
            }

            }
            .background(alignment: .top) { HeaderFade().frame(width: page + 116, height: above + 28).offset(x: -58) }
        }
    }

    // Событие со временем в сетке: тащить, растягивать, открыть. Отдельно от body — в общей цепочке
    // компилятор не успевал вывести типы.
    @ViewBuilder
    private func timed(_ event: EKEvent, column: Int, colW: CGFloat, lanes: [String: Lane]) -> some View {
            let lane = lanes[event.slot] ?? Lane()
            // Наложения — слоями, как в Календаре Apple: первое снизу во всю ширину, каждое следующее
            // сдвинуто вправо; сверху то, что начинается позже, у всех видно начало с названием (01.11.2026).
            let base = CGFloat(min(lane.level, 2)) * min(18, (colW - 6) * 0.2)  // глубже двух слоёв не сдвигаем: узко
            let region = colW - 6 - base
            // Узкая колонка недели: рядом не влезут — следующее ложится на правую половину сверху,
            // у нижнего название видно слева.
            let fits = region / CGFloat(lane.count) >= 44
            let indent = base + (fits ? CGFloat(lane.col) * region / CGFloat(lane.count)
                                      : CGFloat(lane.col) * region / 2 / CGFloat(max(1, lane.count - 1)))
            let width = fits ? region / CGFloat(lane.count) : region - (indent - base)
            let move = moving?.slot == event.slot ? moving : nil
            let grow = resizing?.slot == event.slot ? CGFloat(resizing!.quarters) * hour / 4 : 0
            // Тащим — событие во всю ширину колонки и поверх соседей, со своим новым временем.
            EventBlock(event: event, task: tasks.calendar.isTaskEvent(event),
                       span: move.map { Self.span(shifted(event, $0.days, $0.quarters).0, shifted(event, $0.days, $0.quarters).1) }
                           ?? (resizing?.slot == event.slot ? Self.span(event.startDate, resized(event, resizing!.quarters)) : nil))
                .frame(width: (move != nil ? colW - 6 : width) - 2, height: max(hour / 4 - 3, height(event) + grow))
                .overlay(alignment: .bottom) {
                    // Нижний край — растянуть, как в Календаре Apple.
                    Color.clear.frame(height: 6).contentShape(Rectangle())
                        .pointerStyle(.frameResize(position: .bottom))
                        .gesture(DragGesture(minimumDistance: 2)
                            .onChanged { resizing = (event.slot, Int(($0.translation.height / (hour / 4)).rounded())) }
                            .onEnded { _ in
                                if let r = resizing { tasks.move(event, start: event.startDate, end: resized(event, r.quarters), undo: undo) }
                                resizing = nil
                            })
                }
                .modifier(EventActions(event: event, tasks: tasks, opened: $opened))
                .offset(x: gutter + CGFloat(column) * colW + 3 + (move != nil ? 0 : indent)
                           + CGFloat(move?.days ?? 0) * colW,
                        y: top(event) + 1.5 + CGFloat(move?.quarters ?? 0) * hour / 4)
                .zIndex(move != nil || opened == event.slot ? 10_000 : event.startDate.timeIntervalSince(Calendar.current.startOfDay(for: event.startDate)) / 60 + Double(lane.level) / 10)
                .shadow(color: .black.opacity(move != nil ? 0.35 : lane.level > 0 ? 0.25 : 0), radius: move != nil ? 8 : 3, y: move != nil ? 3 : 1)
                .onTapGesture { opened = event.slot }
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { drag in
                        let shift = Int((drag.translation.width / colW).rounded())
                        moving = (event.slot, max(-column, min(days.count - 1 - column, shift)),
                                  Int((drag.translation.height / (hour / 4)).rounded()))
                    }
                    .onEnded { _ in
                        if let m = moving {
                            let (start, end) = shifted(event, m.days, m.quarters)
                            tasks.move(event, start: start, end: end, undo: undo)
                        }
                        moving = nil
                    })
    }

    private func openBinding(_ event: EKEvent) -> Binding<Bool> {
        Binding(get: { opened == event.slot }, set: { if !$0 { opened = nil } })
    }

    // Новое начало и конец после перетаскивания: дни и четверти часа, длительность та же.
    private func shifted(_ event: EKEvent, _ days: Int, _ quarters: Int) -> (Date, Date) {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: days, to: event.startDate)!
        let start = calendar.date(byAdding: .minute, value: quarters * 15, to: day)!
        return (start, start.addingTimeInterval(event.endDate.timeIntervalSince(event.startDate)))
    }

    // Новый конец после растягивания — не короче четверти часа.
    private func resized(_ event: EKEvent, _ quarters: Int) -> Date {
        max(event.startDate.addingTimeInterval(15 * 60), event.endDate.addingTimeInterval(TimeInterval(quarters * 15 * 60)))
    }

    // Событие на весь день задевает этот день (многодневные — каждый свой день).
    static func covers(_ event: EKEvent, _ day: Date) -> Bool {
        let start = Calendar.current.startOfDay(for: day)
        return event.startDate < start.addingTimeInterval(86_400) && event.endDate > start
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

    // Место события среди пересекающихся, как в Календаре Apple: начавшиеся почти вместе (до 45 мин)
    // стоят рядом и делят ширину, начавшееся позже ложится слоем со сдвигом вправо и не закрывает
    // чужое название. level — глубина слоя, col и count — место в ряду «рядом».
    struct Lane { var level = 0, col = 0, count = 1 }

    static func lanes(_ events: [EKEvent]) -> [String: Lane] {
        var result: [String: Lane] = [:]
        let byDay = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.startDate) }
        for (_, day) in byDay {
            var placed: [EKEvent] = []
            var rows: [String: [String]] = [:]  // первое событие ряда → все события ряда
            for event in day.sorted(by: { $0.startDate < $1.startDate }) {
                let active = placed.filter { shown($0) > event.startDate }
                if let near = active.first(where: { event.startDate.timeIntervalSince($0.startDate) < 45 * 60 }),
                   let head = rows.first(where: { $0.value.contains(near.slot) })?.key {
                    rows[head]!.append(event.slot)
                    result[event.slot] = Lane(level: result[near.slot]!.level, col: rows[head]!.count - 1)
                    for slot in rows[head]! { result[slot]!.count = rows[head]!.count }
                } else {
                    result[event.slot] = Lane(level: active.map { result[$0.slot]!.level + 1 }.max() ?? 0)
                    rows[event.slot] = [event.slot]
                }
                placed.append(event)
            }
        }
        return result
    }
}

private struct EventBlock: View {
    let event: EKEvent
    let task: Bool
    // Пока тащат или растягивают — новое время вместо начала.
    var span: String? = nil

    var body: some View {
        GeometryReader { geo in
            // Короткое событие — одной строкой «название · время», иначе текст налезал на соседей.
            Group {
                if geo.size.width < 26 {
                    // Узкая дорожка — только цвет: текст рвался по буквам в столбик.
                    Color.clear
                } else if geo.size.height < 38 || event.isAllDay || geo.size.width < 70 {
                    // Узко или коротко — одной строкой с многоточием: длинные слова рвались по буквам.
                    Text("\(event.title ?? "")\(event.isAllDay ? "" : " · " + (span ?? event.startDate.formatted(.dateTime.hour().minute())))")
                        .lineLimit(1)
                        .font(Martian.body.font(geo.size.height < 20 ? 9 : 11))
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title ?? "").lineLimit(max(1, Int((geo.size.height - 24) / 14)))
                        Text(span ?? event.startDate.formatted(.dateTime.hour().minute()))
                            .foregroundStyle(tint)
                    }
                }
            }
            .font(Martian.body.font(11)).foregroundStyle(Theme.ink)
            .padding(.leading, geo.size.width < 50 ? 6 : 8).padding(.trailing, geo.size.width < 50 ? 2 : 8)
            .padding(.vertical, geo.size.height < 24 ? 1 : 4)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        // Цвет календаря, как в Календаре Apple: заливка и полоска слева (01.11.2026, «подгружать цвета»).
        // Под цветом — непрозрачный фон: верхний слой закрывает нижний, текст не просвечивает.
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.2)).background(Theme.bg, in: RoundedRectangle(cornerRadius: 8)))
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tint: Color {
        event.calendar.map { Color(nsColor: $0.color) } ?? (task ? Theme.coral : Theme.fg.opacity(0.4))
    }
}

// Карточка события по клику: название (правится, Enter — сохранить), когда, календарь; удалить — для
// обычных событий. Событие задачи правится в заметке — карточка говорит, в какой.
private struct EventCard: View {
    let event: EKEvent
    let tasks: TasksModel
    let close: () -> Void
    @State private var title = ""
    // Сначала карточка только показывает; «изменить» — поле названия. Delete — удалить (01.11.2026).
    @State private var editing = false
    @FocusState private var focused: Bool
    @Environment(\.undoManager) private var undo

    var body: some View {
        let task = tasks.task(for: event)
        VStack(alignment: .leading, spacing: 10) {
            if task == nil && editing {
                TextField("без названия", text: $title)
                    .textFieldStyle(.plain)
                    .font(Martian.heading.font(17))
                    .focused($focused)
                    .onAppear { focused = true }
                    .onSubmit { tasks.rename(event, to: title, undo: undo); close() }
            } else if task == nil {
                HStack {
                    Text(event.title ?? "без названия").font(Martian.heading.font(17)).foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Button("изменить") { editing = true }.buttonStyle(QuietLinkStyle(size: 13, opacity: 0.6))
                }
            } else {
                Text(event.title ?? "").font(Martian.heading.font(17)).foregroundStyle(Theme.ink)
            }
            Text(when).font(Martian.body.font(13)).foregroundStyle(Theme.ink.opacity(0.7))
            // Календарь события — меню: перенести в другой.
            Menu {
                ForEach(tasks.calendar.calendars, id: \.calendarIdentifier) { target in
                    Button(target.title) { tasks.moveTo(event, target, undo: undo) }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(Color(nsColor: event.calendar.color)).frame(width: 8, height: 8)
                    Text(event.calendar.title).font(Martian.body.font(12)).foregroundStyle(NotesLayout.gray)
                }
            }
            .menuStyle(.button).buttonStyle(.plain).fixedSize()
            .disabled(task != nil)
            if let task {
                Text(String(localized: "задача из заметки «\(task.note.deletingPathExtension().lastPathComponent)», время меняй перетаскиванием"))
                    .font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button("удалить") { tasks.remove(event, undo: undo); close() }
                    .buttonStyle(QuietLinkStyle(size: 13, opacity: 0.6))
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
        .onAppear { title = event.title ?? "" }
        .focusable(!editing)
        .focusEffectDisabled()
        .onKeyPress(.delete) {
            guard !editing, task == nil else { return .ignored }
            tasks.remove(event, undo: undo); close(); return .handled
        }
    }

    private var when: String {
        let ru = Locale.app
        let day = event.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(ru))
        return event.isAllDay ? String(localized: "\(day), весь день") : "\(day), \(DayGrid.span(event.startDate, event.endDate))"
    }
}

// Карточка по клику и меню по правому клику — отдельным модификатором: в общей цепочке события
// компилятор не успевал вывести типы.
private struct EventActions: ViewModifier {
    let event: EKEvent
    let tasks: TasksModel
    @Binding var opened: String?

    func body(content: Content) -> some View {
        content
            .popover(isPresented: Binding(get: { opened == event.slot }, set: { if !$0 { opened = nil } }), arrowEdge: .trailing) {
                EventCard(event: event, tasks: tasks) { opened = nil }
            }
            .contextMenu { EventMenu(event: event, tasks: tasks) { opened = event.slot } }
    }
}

// Шапка календаря над сеткой: сверху цвет листа, книзу — в прозрачность; размытие под ней тоже сходит на нет.
private struct HeaderFade: View {
    var body: some View {
        // Тот же материал, что у листа (NoteViews: материал + фон 78 %), — иначе виден край прямоугольника.
        ZStack {
            Rectangle().fill(.regularMaterial)
            Rectangle().fill(Theme.bg.opacity(0.78))
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.62),
                                     .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }
}

// Правый клик по событию: изменить, перенести в другой календарь, удалить. Событие задачи правится в заметке.
private struct EventMenu: View {
    let event: EKEvent
    let tasks: TasksModel
    let open: () -> Void
    @Environment(\.undoManager) private var undo

    var body: some View {
        Button("изменить") { open() }
        if tasks.task(for: event) == nil {
            Menu("в календарь") {
                ForEach(tasks.calendar.calendars, id: \.calendarIdentifier) { target in
                    Button(target.title) { tasks.moveTo(event, target, undo: undo) }
                }
            }
            Divider()
            Button("удалить", role: .destructive) { tasks.remove(event, undo: undo) }
        }
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
                    let list = events.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
                    // Не влезло — «ещё N», как в Календаре Apple; клик открывает день.
                    ForEach(list.prefix(list.count > 3 ? 2 : 3), id: \.slot) { event in
                        Text(event.title ?? "")
                            .font(Martian.body.font(10))
                            .foregroundStyle(tasks.calendar.isTaskEvent(event) ? Theme.coral : NotesLayout.gray)
                            .lineLimit(1)
                    }
                    if list.count > 3 {
                        Text(String(localized: "ещё \(list.count - 2)")).font(Martian.body.font(10)).foregroundStyle(Theme.ink.opacity(0.5))
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
            Text("enter, чтобы добавить")
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
            }.buttonStyle(.plain).help(withDate ? "без срока" : "со сроком попадёт в календарь")
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
