import AppKit
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
                case .search: SearchPage(model: model)
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
        case .sync: "где лежат заметки и куда уходят"
        case .dictation: "говоришь — текст в буфере"
        case .search: "по тексту и по смыслу"
        case .lock: "пинкод и touch id"
        case .calendar: "задачи со сроком попадают в календарь"
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
    @State private var relogin = false

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
        SettingRow(title: "история в git", subtitle: "каждый час сохраняем версию") {
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
            if TokenStore().exists && !sync.needsLogin {
                GrantedLabel(text: "подключено")
            } else {
                Button("войти заново") { relogin = true }.buttonStyle(WhitePillStyle())
            }
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
        if let error = sync.errorText {
            Text(error)
                .font(Martian.body.font(11)).foregroundStyle(Theme.coral)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(width: 640, alignment: .leading).padding(.top, 8)
        }
        Note(text: "правили на двух mac — сохраним обе версии")
            .onAppear { isRepo = GitVault.isRepository(vault) }
            .sheet(isPresented: $relogin) {
                ReloginSheet(vault: vault) {
                    relogin = false
                    sync.clearError()
                    Task { _ = await sync.pushNow() }
                }
            }
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
        Note(text: "всё распознаётся на этом mac, без интернета")
    }

    private func subtitle(_ model: SpeechModel) -> String {
        let size = model.downloadMB >= 1000 ? String(format: "%.1f гб", Double(model.downloadMB) / 1000) : "\(model.downloadMB) мб"
        let kind = model == .gigaAM ? "только русский, сразу с пунктуацией" : "99 языков"
        return "\(kind), \(size)" + (ModelStore.standard.isInstalled(model) ? " · скачано" : "")
    }
}

// Поиск: по тексту — всегда, по смыслу — бета, включается здесь.
private struct SearchPage: View {
    let model: NotesModel
    @AppStorage(NotesModel.semanticKey) private var semantic = false

    var body: some View {
        SettingRow(title: "поиск по тексту", subtitle: "⌘K из любого места") {
            GrantedLabel(text: "работает")
        }
        GlassRow(width: 640) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("поиск по смыслу").font(Martian.body.font(13)).foregroundStyle(Theme.ink)
                    // Метка «бета»: модель Apple угадывает не всё (3 из 4 в тесте).
                    Text("бета")
                        .font(Martian.body.font(10)).foregroundStyle(NotesLayout.gray)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .overlay(Capsule().strokeBorder(NotesLayout.gray.opacity(0.5), lineWidth: 1))
                }
                Text("найдёт заметку, даже если не помнишь точных слов")
                    .font(Martian.body.font(11)).foregroundStyle(Theme.fg.opacity(0.3))
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $semantic).toggleStyle(.switch).tint(Theme.coral).labelsHidden()
                .onChange(of: semantic) { _, on in if on { model.refreshIndex() } }
        }
        Note(text: "индекс хранится отдельно от заметок и в историю не попадает")
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
        SettingRow(title: "touch id", subtitle: "вход по пальцу") {
            if !BiometricLock.isAvailable {
                Text("нет touch id").font(Martian.body.font(13)).foregroundStyle(Theme.fg.opacity(0.3))
            } else if touchID {
                Button("выключить") { BiometricLock.disable(); touchID = false }.buttonStyle(WhitePillStyle())
            } else {
                Button("включить") { Task { touchID = await BiometricLock.enable() } }.buttonStyle(WhitePillStyle())
            }
        }
        SettingRow(title: "когда спрашивать", subtitle: "после блокировки mac или 15 минут без дела") { EmptyView() }
        Note(text: "пинкод закрывает приложение, сами заметки остаются обычными файлами")
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
        SettingRow(title: "длительность", subtitle: "\(minutes) минут на задачу") {
            Menu("изменить") {
                ForEach([15, 30, 60, 90], id: \.self) { value in
                    Button("\(value) минут") { sync.minutes = value; minutes = value }
                }
            }
            .menuStyle(.button).buttonStyle(WhitePillStyle()).fixedSize()
        }
        Note(text: "поменял задачу — событие в календаре поменяется само")
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

// Повторный вход в GitHub по коду — тот же поток, что на первом входе: код, «открыть github»,
// подтвердил — новый токен в Связке ключей, папка привязана к notes и отправлена.
private struct ReloginSheet: View {
    let vault: URL
    let done: () -> Void
    @State private var login = GitHubLogin()
    @State private var attempt = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("войти в github")
                .font(Martian.heading.font(22)).foregroundStyle(Theme.ink)
            Text("вход устарел. введи код на github — и всё снова уйдёт в облако")
                .font(Martian.body.font(13)).foregroundStyle(NotesLayout.gray)
            DeviceCodeCapsule(state: login.state, renew: { attempt += 1 })
                .offset(y: -(207 - Layout.sheetTop))
                .frame(height: 110)
            HStack(spacing: 10) {
                Button("открыть github") {
                    if case .waiting(let code, let url) = login.state { DeviceCode.copy(code); NSWorkspace.shared.open(url) }
                    else { DeviceCode.openGitHub() }
                }
                .buttonStyle(CoralCapsuleStyle())
                Button("отмена") { dismiss() }.buttonStyle(QuietLinkStyle(size: 13, opacity: 0.4))
            }
        }
        .padding(28)
        .frame(width: 600)
        .task(id: attempt) { await login.run(vault: vault) { _ in done() } }
    }
}
