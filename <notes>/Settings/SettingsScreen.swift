import EventKit
import NotesCore
import NotesSpeech
import SwiftUI

// Настройки — кадры «настройки — …» (секция «настройки»): заголовок страницы, серая подпись,
// стеклянные строки 640 с кнопкой справа, внизу пояснение. Всё на настоящих данных.
struct SettingsScreen: View {
    let model: NotesModel

    var body: some View {
        let page = model.settingsPage
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Text(page.rawValue)
                    .font(Martian.heading.font(26))
                    .kerning(Theme.tracking(-7, size: 26))
                    .foregroundStyle(Theme.ink)
                Text(subtitle(page))
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(NotesLayout.gray)
                    .padding(.top, 1)
                    .padding(.bottom, 40)
                switch page {
                case .sync: SyncPage(model: model)
                case .dictation: DictationPage()
                case .search: SearchPage()
                case .lock: LockPage(model: model)
                case .calendar:
                    CalendarPage(sync: model.tasks.calendar, reload: model.tasks.reload)
                    FolderPicks(folders: model.tree.folders.map(\.name), sync: model.tasks.calendar, reload: model.tasks.reload)
                }
            }
            .frame(width: 832, alignment: .leading)
            .padding(.leading, 58)
            .padding(.top, 36)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.never)
    }

    private func subtitle(_ page: NotesModel.SettingsPage) -> String {
        switch page {
        case .sync: "папка, история и github"
        case .dictation: "из любого приложения, текст — в буфер обмена"
        case .search: "по тексту и по смыслу"
        case .lock: "пинкод и touch id"
        case .calendar: "задачи из заметок с датой"
        }
    }
}

// Строка настроек: заголовок, подпись, справа своё (кнопка, «включено», текст).
struct SettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        GlassRow(width: 640) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Martian.body.font(11))
                        .kerning(Theme.tracking(-7, size: 11))
                        .foregroundStyle(Theme.fg.opacity(0.3))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

private struct Note: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Martian.body.font(11))
            .kerning(Theme.tracking(-7, size: 11))
            .foregroundStyle(Theme.fg.opacity(0.3))
            .padding(.top, 14)
    }
}

private struct SyncPage: View {
    let model: NotesModel
    @State private var sync = SyncController.shared
    @State private var sending = false
    @State private var isRepo = false

    var body: some View {
        let vault = model.library.root
        SettingRow(title: "папка хранилища", subtitle: vault.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
            Button("изменить") {
                VaultPicker.choose { url in
                    try? VaultStore.save(url)
                    NotificationCenter.default.post(name: .vaultChosen, object: url)
                }
            }
            .buttonStyle(WhitePillStyle())
        }
        SettingRow(title: "история в git", subtitle: "коммит раз в час, подпись по заметкам") {
            if isRepo {
                GrantedLabel(text: "включено")
            } else {
                Button("включить") {
                    Task {
                        _ = try? await Task.detached { try GitVault.prepare(at: vault) }.value
                        sync.start(vault: vault)
                        isRepo = GitVault.isRepository(vault)
                    }
                }
                .buttonStyle(WhitePillStyle())
            }
        }
        SettingRow(title: "github", subtitle: TokenStore().exists ? "приватный notes, отправка раз в сутки" : "вход по коду — на первом входе") {
            if TokenStore().exists { GrantedLabel(text: "подключено") } else { Text("не подключено").font(Martian.body.font(13)).foregroundStyle(Theme.fg.opacity(0.3)) }
        }
        SettingRow(title: "последний коммит", subtitle: sync.lastCommit.map { NoteEditor.date($0) } ?? "с запуска правок не было") {
            EmptyView()
        }
        SettingRow(title: "последняя отправка",
                   subtitle: SyncController.lastPush.map { NoteEditor.date($0) } ?? "ещё не отправляли") {
            Button(sending ? "отправляем…" : "отправить сейчас") {
                sending = true
                Task { _ = await sync.pushNow(); sending = false }
            }
            .buttonStyle(WhitePillStyle())
            .disabled(sending || !TokenStore().exists || !sync.isRunning)
        }
        // Ошибка — целиком и выделяемой, чтобы её можно было скопировать и прислать.
        if let error = sync.lastError {
            Text(error)
                .font(Martian.body.font(11)).foregroundStyle(Theme.coral)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(width: 640, alignment: .leading).padding(.top, 8)
        }
        Note(text: "конфликты не теряют текст: версия с другого mac ляжет рядом")
            .onAppear { isRepo = GitVault.isRepository(vault) }
    }
}

private struct DictationPage: View {
    @State private var selected = SpeechSettings.model
    @State private var downloads = ModelDownloads.shared

    var body: some View {
        HotKeyRow(width: 640)
        ForEach(SpeechModel.allCases, id: \.self) { model in
            SettingRow(title: model.displayName, subtitle: subtitle(model)) {
                if model == selected {
                    GrantedLabel(text: "выбрана")
                } else if let progress = downloads.progress[model] {
                    Text("\(Int(progress * 100))%").font(Martian.body.font(13)).foregroundStyle(Theme.fg.opacity(0.3))
                } else if ModelStore.standard.isInstalled(model) {
                    Button("выбрать") { SpeechSettings.model = model; selected = model }.buttonStyle(WhitePillStyle())
                } else {
                    Button("скачать") { Task { try? await downloads.download(model) } }.buttonStyle(WhitePillStyle())
                }
            }
        }
        Note(text: "речь распознаётся на этом mac и никуда не отправляется")
    }

    private func subtitle(_ model: SpeechModel) -> String {
        let size = model.downloadMB >= 1000 ? String(format: "%.1f гб", Double(model.downloadMB) / 1000) : "\(model.downloadMB) мб"
        let kind = model == .gigaAM ? "только русский, сразу с пунктуацией" : "99 языков"
        return "\(kind), \(size)" + (ModelStore.standard.isInstalled(model) ? " · скачано" : "")
    }
}

// Поиск по смыслу ещё в работе (TASKS.md) — страница честно говорит, что сейчас поиск по тексту.
private struct SearchPage: View {
    var body: some View {
        SettingRow(title: "поиск по тексту", subtitle: "все слова запроса, ⌘K из любого места") {
            GrantedLabel(text: "работает")
        }
        SettingRow(title: "поиск по смыслу", subtitle: "встроенная в macos модель, ничего не скачивает") {
            Text("в работе").font(Martian.body.font(13)).foregroundStyle(Theme.fg.opacity(0.3))
        }
        Note(text: "индекс будет лежать вне хранилища и в git не попадёт")
    }
}

private struct LockPage: View {
    let model: NotesModel
    @State private var pinSet = PinStore().isSet
    @State private var touchID = BiometricLock.isEnabled

    var body: some View {
        SettingRow(title: "пинкод", subtitle: pinSet ? "4 цифры" : "не задан") {
            Button(pinSet ? "сменить" : "задать") { model.pinEntryShown = true }.buttonStyle(WhitePillStyle())
        }
        SettingRow(title: "touch id", subtitle: "приложи палец вместо пинкода") {
            if !BiometricLock.isAvailable {
                Text("нет touch id").font(Martian.body.font(13)).foregroundStyle(Theme.fg.opacity(0.3))
            } else if touchID {
                Button("выключить") { BiometricLock.disable(); touchID = false }.buttonStyle(WhitePillStyle())
            } else {
                Button("включить") { Task { touchID = await BiometricLock.enable() } }.buttonStyle(WhitePillStyle())
            }
        }
        SettingRow(title: "когда спрашивать", subtitle: "после блокировки mac и 15 минут в фоне") { EmptyView() }
        Note(text: "заметки не шифруются — их можно открыть любым редактором")
            .onChange(of: model.pinEntryShown) { _, shown in if !shown { pinSet = PinStore().isSet } }
    }
}

private struct CalendarPage: View {
    let sync: CalendarSync
    let reload: () -> Void
    @State private var access = false
    @State private var calendarID = ""
    @State private var minutes = 30

    var body: some View {
        SettingRow(title: "доступ к календарю") {
            if access {
                GrantedLabel(text: "разрешено")
            } else {
                Button("разрешить") { Task { access = await sync.requestAccess(); reload() } }.buttonStyle(WhitePillStyle())
            }
        }
        SettingRow(title: "календарь для задач", subtitle: sync.tasksCalendar?.title ?? "—") {
            Menu("изменить") {
                ForEach(sync.calendars, id: \.calendarIdentifier) { calendar in
                    Button(calendar.title) { sync.tasksCalendar = calendar; calendarID = calendar.calendarIdentifier; reload() }
                }
            }
            .menuStyle(.button).buttonStyle(WhitePillStyle()).fixedSize()
            .disabled(!access)
        }
        SettingRow(title: "длительность", subtitle: "\(minutes) минут, если в задаче нет конца") {
            Menu("изменить") {
                ForEach([15, 30, 60, 90], id: \.self) { value in
                    Button("\(value) минут") { sync.minutes = value; minutes = value }
                }
            }
            .menuStyle(.button).buttonStyle(WhitePillStyle()).fixedSize()
        }
        Note(text: "событие обновляется вместе с заметкой, а не плодится заново")
            .onAppear { access = sync.hasAccess; minutes = sync.minutes }
    }
}

extension Notification.Name {
    static let vaultChosen = Notification.Name("notes.vaultChosen")
}

// Из каких папок задачи уходят в календарь — по строке на папку верхнего уровня.
private struct FolderPicks: View {
    let folders: [String]
    let sync: CalendarSync
    let reload: () -> Void
    @State private var excluded: Set<String> = []

    var body: some View {
        Text("папки в календаре")
            .font(Martian.body.font(15)).foregroundStyle(Theme.ink).padding(.top, 26)
        ForEach(folders, id: \.self) { name in
            SettingRow(title: name) {
                Toggle("", isOn: Binding(get: { !excluded.contains(name) }, set: { on in
                    if on { excluded.remove(name) } else { excluded.insert(name) }
                    sync.excludedFolders = excluded
                    reload()
                }))
                .toggleStyle(.switch).tint(Theme.coral).labelsHidden()
            }
        }
        .onAppear { excluded = sync.excludedFolders }
    }
}
