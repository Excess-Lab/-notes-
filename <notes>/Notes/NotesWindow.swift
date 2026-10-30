import EventKit
import NotesCore
import SwiftUI

// Главный экран — секция «Заметки» в Figma (16:7138): кадры «заметка» (7:34), «все заметки» (79:11295)
// и поиск поверх (79:12603). Окно 1200×760, все координаты — из кадров.
enum NotesLayout {
    static let window = CGSize(width: 1200, height: 760)
    static let header: CGFloat = 92
    static let gray = Color(red: 134 / 255, green: 134 / 255, blue: 139 / 255)
    static let line = Color(light: Color(red: 227 / 255, green: 227 / 255, blue: 232 / 255), dark: .white.opacity(0.1))
}

struct NotesWindow: View {
    @Bindable var model: NotesModel
    @State private var arrived = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            screen
                // Под поиском экран размыт и чуть затемнён — как в кадре, а не залит серым.
                .blur(radius: model.searchShown || model.pinEntryShown ? 8 : 0)
                .allowsHitTesting(!model.searchShown && !model.pinEntryShown)

            if model.searchShown {
                SearchOverlay(model: model)
                    .transition(.opacity.combined(with: .blurReplace))
            }
            if model.pinEntryShown {
                ZStack {
                    Theme.bg.opacity(0.45)
                    PinEntrySheet { _ in model.pinEntryShown = false }
                }
                .transition(.opacity.combined(with: .blurReplace))
            }
        }
        // Окно тянется: минимум — размер кадра 1200×760.
        .frame(minWidth: NotesLayout.window.width, maxWidth: .infinity,
               minHeight: NotesLayout.window.height, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .animation(.smooth(duration: 0.3), value: model.searchShown)
        .onDisappear { model.flush() }
    }

    private var screen: some View {
        GeometryReader { geo in
        let w = geo.size.width, h = geo.size.height
        ZStack(alignment: .topLeading) {
            // Шапка из планок, как на первом входе, только 92 px и во всю ширину.
            // Планки — около 60 слоёв с размытием. Раньше они перерисовывались при каждом изменении экрана
            // (буква в заметке, наведение) — отсюда лаги. Теперь один раз на ширину окна, слой через Metal.
            StaticSlats(width: w).equatable()
                .frame(height: NotesLayout.header)

            TopBar(model: model)
                .modifier(Arrival(shown: arrived, delay: 0.05))

            // Боковая панель и лист содержимого — отдельные стеклянные листы под шапкой.
            Group {
                GlassSheet(radius: 14)
                    .frame(width: 247, height: h - 92)
                // Смена раздела: панель уходит в размытие и проявляется новой, вместе с листом справа.
                SectionSidebar(model: model)
                    .id(model.section)
                    .transition(.blurReplace)
                    .frame(width: 247, height: h - 92, alignment: .topLeading)
            }
            .animation(.smooth(duration: 0.45), value: model.section)
            .offset(x: 17, y: 92)
            .modifier(Arrival(shown: arrived, delay: 0.15))

            Group {
                GlassSheet(radius: 18)
                    .frame(width: w - 294, height: h - 92)
                // Обрезаем до сдвига: после .offset обрезка шла по старому месту, и правый край листа пропадал.
                SectionContent(model: model)
                    .frame(width: w - 294, height: h - 92, alignment: .topLeading)
                    .clipped()
            }
            .offset(x: 279, y: 92)
            .modifier(Arrival(shown: arrived, delay: 0.25))
        }
        }
        .onAppear { arrived = true }
    }
}

// Первый показ окна: шапка, панель и лист проявляются по очереди из размытия, чуть снизу (ТЗ 30.10.2026).
private struct Arrival: ViewModifier {
    let shown: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 12)
            .offset(y: shown ? 0 : 14)
            .animation(.smooth(duration: 0.7).delay(delay), value: shown)
    }
}

// Стеклянный лист: #F9F9F9 20 % и светлый кант, как лист шагов первого входа.
// Листы доходят до низа окна — скруглены только сверху (ТЗ 30.10.2026); нижний кант уходит за край окна.
struct GlassSheet: View {
    var radius: CGFloat

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius)
        shape
            .fill(Theme.sheet.opacity(0.2))
            .overlay(shape.strokeBorder(Theme.edge.opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.07), radius: 10, y: -2)
            .padding(.bottom, -1)
    }
}

// Капсула в шапке: #F9F9F9 20 % со стеклом, скругление 18.
private struct HeaderGroup<Content: View>: View {
    let width: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.sheet.opacity(0.2))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.edge.opacity(0.6), lineWidth: 1))
            content()
        }
        .frame(width: width, height: 48)
    }
}

private struct TopBar: View {
    let model: NotesModel
    @State private var sync = SyncController.shared
    @State private var hovered: NotesModel.Section?
    @Namespace private var hover

    var body: some View {
        GeometryReader { geo in
        let compact = geo.size.width < 1240
        ZStack(alignment: .topLeading) {
            HeaderGroup(width: 417) {
                Button { model.section = .notes } label: {
                    Text("<notes>")
                        .font(Martian.logo.font(15))
                        .kerning(Theme.tracking(-5, size: 15))
                        .foregroundStyle(Theme.fg)
                }
                .buttonStyle(.plain)
                .offset(x: 15)
                Button { model.searchShown = true } label: {
                    HStack(spacing: 6) {
                        DotIcon(glyph: .search)
                        Text("поиск")
                            .font(Martian.body.font(13))
                            .kerning(Theme.tracking(-7, size: 13))
                            .foregroundStyle(NotesLayout.gray)
                        Spacer(minLength: 0)
                        Keycap(text: "⌘K")
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 10)
                    .frame(width: 256, height: 30)
                    .background(Capsule().fill(Theme.bg.opacity(0.5)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("k", modifiers: .command)
                .offset(x: 146)
            }
            .offset(x: 17, y: 15)

            // Узкое окно — разделы и синхронизация одними значками, название — подсказкой при наведении;
            // широкое — со словами, как в кадрах (ТЗ 30.10.2026: «только иконки при сжимании»).
            // Подсветка наведения одна на группу и переезжает между кнопками, не вылезая за них.
            let sections: CGFloat = compact ? 5 * 34 + 4 * 6 + 22 : 540
            HeaderGroup(width: sections) {
                HStack(spacing: compact ? 6 : 10) {
                    section("заметки", .notes, .notes, compact)
                    section("задачи", .taskDone, .tasks, compact)
                    section("календарь", .calendar, .calendar, compact)
                    section("видео", .video, .video, compact)
                    section("настройки", .settings, .settings, compact)
                }
                .offset(x: 11)
                .animation(.smooth(duration: 0.25), value: hovered)
            }
            .offset(x: 449, y: 15)

            // Синхронизация тянется до правого края окна с тем же отступом, что слева.
            let left = 449 + sections + 15
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HeaderGroup(width: max(48, geo.size.width - left - 17)) {
                    HStack(spacing: 6) {
                        DotIcon(glyph: .git)
                        if !compact {
                            Text(sync.status(now: context.date))
                                .font(Martian.body.font(11))
                                .kerning(Theme.tracking(-7, size: 11))
                                .foregroundStyle(Theme.fg)
                                .lineLimit(1)
                                .transition(.blurReplace)
                        }
                    }
                    .opacity(0.4)
                    .offset(x: 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .help(sync.status(now: context.date))
                }
            }
            .offset(x: left, y: 15)
        }
        .animation(.smooth(duration: 0.35), value: compact)
        }
    }

    // Раздел в шапке: выбранный — ярко на белом 10 %, остальные — 30 %, как в кадрах.
    private func section(_ title: String, _ glyph: DotGlyph, _ target: NotesModel.Section, _ compact: Bool) -> some View {
        let active = model.section == target
        return Button {
            model.flush()
            model.section = target
        } label: {
            HStack(spacing: 8) {
                DotIcon(glyph: glyph)
                if !compact {
                    Text(title)
                        .font(Martian.body.font(13))
                        .kerning(Theme.tracking(-7, size: 13))
                        .foregroundStyle(Theme.ink)
                        .fixedSize()
                        .transition(.blurReplace)
                }
            }
                .padding(.horizontal, compact ? 0 : 8)
                .frame(minWidth: 34, minHeight: 26)
                .background {
                    if hovered == target && !active {
                        RoundedRectangle(cornerRadius: 8).fill(Theme.bg.opacity(0.06))
                            .matchedGeometryEffect(id: "hover", in: hover)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg.opacity(active ? 0.1 : 0)))
                .opacity(active || hovered == target ? 1 : 0.3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(compact ? title : "")
        .onHover { inside in
            if inside { hovered = target } else if hovered == target { hovered = nil }
        }
    }
}

struct NotesSidebar: View {
    let model: NotesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.open(.folder(model.library.root)) } label: {
                Text("заметки")
                    .font(Martian.body.font(11))
                    .kerning(Theme.tracking(-7, size: 11))
                    .foregroundStyle(Theme.fg.opacity(0.2))
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Закреплённые — над деревом.
                    let pins = model.pinned
                    if !pins.isEmpty {
                        ForEach(pins, id: \.self) { url in
                            SidebarRow(glyph: .file, title: url.deletingPathExtension().lastPathComponent,
                                       selected: model.selection == .note(url)) { model.open(.note(url)) }
                                .contextMenu { NoteMenu(model: model, url: url) }
                        }
                        Rectangle().fill(NotesLayout.line).frame(height: 1).padding(.vertical, 6)
                    }
                    FolderRows(model: model, folder: model.tree, depth: 0)
                }
                .contextMenu { NoteMenu(model: model, url: model.library.root, folder: true) }
                // Мимо папок — в корень хранилища.
                .dropDestination(for: URL.self) { urls, _ in model.drop(urls, into: model.library.root) }
                .padding(.horizontal, 10)
                .padding(.top, 15)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
        }
    }
}

// Папки и заметки одного уровня; раскрытая папка показывает свои строки со сдвигом 18.
private struct FolderRows: View {
    let model: NotesModel
    let folder: NoteLibrary.Folder
    let depth: Int
    @State private var target: URL?

    var body: some View {
        ForEach(folder.folders) { child in
            SidebarRow(glyph: .folder, title: child.name, depth: depth,
                       selected: model.selection == .folder(child.url), targeted: target == child.url) {
                model.toggle(child.url)
                model.open(.folder(child.url))
            }
            .contextMenu { NoteMenu(model: model, url: child.url, folder: true) }
            .draggable(child.url)
            .dropDestination(for: URL.self) { urls, _ in model.drop(urls, into: child.url) } isTargeted: { inside in
                if inside { target = child.url } else if target == child.url { target = nil }
            }
            if model.expanded.contains(child.url) {
                FolderRows(model: model, folder: child, depth: depth + 1)
            }
        }
        ForEach(folder.notes) { note in
            SidebarRow(glyph: .file, title: note.title, depth: depth,
                       selected: model.selection == .note(note.url)) {
                model.open(.note(note.url))
            }
            .contextMenu { NoteMenu(model: model, url: note.url) }
            .draggable(note.url)
        }
    }
}

// Строка боковой панели (компонент «сайдбар/строка»): 227×26, скругление 8, выбранная — чёрный 7 %.
struct SidebarRow: View {
    let glyph: DotGlyph
    let title: String
    var depth = 0
    var count: Int? = nil
    let selected: Bool
    // Сюда сейчас тянут файл — коралловая подсветка.
    var targeted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                DotIcon(glyph: glyph)
                // Имя файла — то, что ввёл человек: регистр не трогаем.
                Text(title)
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let count {
                    Text("\(count)")
                        .font(Martian.body.font(11))
                        .kerning(Theme.tracking(-7, size: 11))
                        .foregroundStyle(NotesLayout.gray)
                }
            }
            .padding(.leading, 8 + CGFloat(depth) * 18)
            .padding(.trailing, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fg.opacity(selected ? 0.07 : 0)))
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.coral.opacity(targeted ? 0.18 : 0)))
            .animation(.smooth(duration: 0.2), value: targeted)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// Лист раздела: сверху капсула с путём и две кнопки (надиктовка, новая заметка), под ними — сам раздел.
struct SectionContent: View {
    let model: NotesModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch model.section {
                case .notes:
                    if let note = model.openNote {
                        NoteEditor(model: model, url: note).id(note)
                    } else {
                        FolderOverview(model: model, folder: model.currentFolder)
                    }
                case .tasks: TasksScreen(model: model.tasks)
                case .calendar: CalendarScreen(tasks: model.tasks, uploads: model.video.items)
                case .video: VideoScreen(model: model)
                case .settings: SettingsScreen(model: model)
                }
            }
            // Раздел, заметка или папка сменились — старое уходит в размытие, новое из него проявляется,
            // как шаги первого входа. Раньше текст менялся рывком, хотя окно двигалось плавно.
            .id(contentID)
            .transition(.blurReplace)
            .padding(.top, 51)

            Text(crumb)
                .contentTransition(.interpolate)
                .font(Martian.body.font(13))
                .kerning(Theme.tracking(-7, size: 13))
                .foregroundStyle(NotesLayout.gray)
                .lineLimit(1)
                .padding(.horizontal, 15)
                .frame(height: 36)
                .background(Capsule().fill(Theme.bg.opacity(0.2)))
                .offset(x: 15, y: 15)

            HStack(spacing: 8) {
                IconButton(glyph: .microphone, help: "надиктовать") { DictationController.shared.toggleFromApp() }
                IconButton(glyph: .newNote, help: "новая заметка") { model.newNote() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 15)
            .offset(y: 109 - 92)
        }
        .animation(.smooth(duration: 0.45), value: contentID)
    }

    private var contentID: String {
        switch model.section {
        case .notes: "notes-\(model.selection)"
        case .video: "video-\(model.video.open?.uuidString ?? "")"
        default: "\(model.section)"
        }
    }

    private var crumb: String {
        switch model.section {
        case .notes: model.breadcrumb
        case .tasks: "задачи / " + model.tasks.filter.rawValue
        case .calendar: "календарь"
        case .video: model.video.crumb
        case .settings: "настройки / " + model.settingsPage.rawValue
        }
    }
}

// Календари в боковой панели: клик — показать или скрыть на экране, цвет — как в Календаре Apple.
// При наведении — «задачи сюда» и корзина; новый календарь вписывается прямо в список, Enter — создать.
private struct CalendarList: View {
    let sync: CalendarSync
    @State private var hovered: String?
    @State private var adding = false
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        let _ = sync.revision
        let main = sync.store.defaultCalendarForNewEvents?.calendarIdentifier
        ForEach(sync.calendars, id: \.calendarIdentifier) { calendar in
            let id = calendar.calendarIdentifier
            let shown = !sync.hidden.contains(id)
            let color = Color(cgColor: calendar.cgColor)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color, lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 4).fill(shown ? color : .clear))
                    .overlay { if shown { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white) } }
                    .frame(width: 14, height: 14)
                Text(calendar.title)
                    .font(Martian.body.font(13)).kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(Theme.ink.opacity(shown ? 1 : 0.4)).lineLimit(1)
                Spacer(minLength: 0)
                if id == sync.tasksCalendar?.calendarIdentifier {
                    Text("задачи").font(Martian.body.font(10)).foregroundStyle(NotesLayout.gray)
                } else if hovered == id {
                    Button("задачи сюда") { sync.tasksCalendar = calendar }
                        .buttonStyle(QuietLinkStyle(size: 10, opacity: 0.4))
                }
                if hovered == id, id != main {
                    Button { CalendarRemoval.confirm(calendar, sync: sync) } label: {
                        Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(NotesLayout.gray)
                    }.buttonStyle(.plain).help("удалить календарь")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.fg.opacity(hovered == id ? 0.05 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { withAnimation(.smooth(duration: 0.2)) { sync.toggleShown(calendar) } }
            .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
        }
        if adding {
            TextField("название", text: $name)
                .textFieldStyle(.plain).font(Martian.body.font(13))
                .focused($focused)
                .padding(.horizontal, 8).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.coral.opacity(0.5)))
                .onSubmit(create)
                .onExitCommand { adding = false; name = "" }
                .onAppear { focused = true }
        } else {
            SidebarRow(glyph: .plus, title: "новый календарь", selected: false) { adding = true }
                .opacity(0.5)
        }
    }

    private func create() {
        let title = name.trimmingCharacters(in: .whitespaces)
        adding = false; name = ""
        guard !title.isEmpty else { return }
        do { try sync.createCalendar(title) } catch { NSAlert(error: error).runModal() }
    }
}

// Боковая панель своего раздела: дерево заметок, фильтры задач, календари, видео, страницы настроек.
struct SectionSidebar: View {
    let model: NotesModel

    var body: some View {
        switch model.section {
        case .notes: NotesSidebar(model: model)
        case .tasks:
            SidebarList(title: "задачи") {
                ForEach(TasksModel.Filter.allCases, id: \.self) { filter in
                    SidebarRow(glyph: filter == .inCalendar ? .calendar : filter == .done ? .taskDone : .task,
                               title: filter.rawValue, count: model.tasks.count(filter),
                               selected: model.tasks.filter == filter) { model.tasks.filter = filter }
                }
            }
        case .calendar:
            SidebarList(title: "календари") {
                CalendarList(sync: model.tasks.calendar)
            }
        case .video:
            SidebarList(title: "видео") {
                ForEach(VideoModel.Filter.allCases, id: \.self) { filter in
                    SidebarRow(glyph: filter == .done ? .taskDone : .video, title: filter.rawValue,
                               count: model.video.count(filter), selected: model.video.filter == filter) {
                        model.video.filter = filter
                        model.video.open = nil
                    }
                }
            }
        case .settings:
            SidebarList(title: "настройки") {
                ForEach(NotesModel.SettingsPage.allCases, id: \.self) { page in
                    SidebarRow(glyph: page.glyph, title: page.rawValue, selected: model.settingsPage == page) {
                        model.settingsPage = page
                    }
                }
            }
        }
    }
}

struct SidebarList<Rows: View>: View {
    let title: String
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Martian.body.font(11))
                .kerning(Theme.tracking(-7, size: 11))
                .foregroundStyle(Theme.fg.opacity(0.2))
                .padding(.leading, 10)
                .padding(.top, 12)
            VStack(alignment: .leading, spacing: 2) { rows() }
                .padding(.horizontal, 10)
                .padding(.top, 15)
            Spacer(minLength: 0)
        }
    }
}

// Круглая кнопка 32×32 с иконкой (компонент «кнопка/иконка»): белый 45 %, мягкая тень.
// Иконка в круглой кнопке 32×32 — без действия, чтобы ставить в свои Button.
struct IconButtonLabel: View {
    let glyph: DotGlyph
    var body: some View {
        DotIcon(glyph: glyph)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Theme.bg.opacity(0.45)))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
            .contentShape(Circle())
    }
}

struct IconButton: View {
    let glyph: DotGlyph
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DotIcon(glyph: glyph)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.bg.opacity(0.45)))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct StaticSlats: View, Equatable {
    let width: CGFloat
    var body: some View {
        GlassSlats(slatWidth: Layout.finalSlatWidth).drawingGroup()
    }
}
