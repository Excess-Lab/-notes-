import SwiftUI
import AppKit
import NotesCore

// Содержимое листа для каждого шага. Все координаты — из кадров Figma, от верха листа (y = 54 в окне).
struct OnboardingStepContent: View {
    let model: OnboardingModel

    var body: some View {
        switch model.step {
        case .welcome:
            StepLayout(title: "привет!",
                       text: "выбери папку куда сохранять заметки",
                       primary: (String(localized: "создать папку"), { VaultPicker.create { model.vaultChosen($0) } }),
                       secondary: (String(localized: "выбрать папку"), { VaultPicker.choose { model.vaultChosen($0) } }))
        case .git:
            StepLayout(title: "git в папке",
                       text: "папка станет git-репозиторием: любую правку можно откатить",
                       primary: (String(localized: "инициализировать"), { model.initializeGit() }),
                       // Без git нечего отправлять на GitHub — сразу к моделям.
                       secondary: (String(localized: "пропустить, настрою потом"), { model.go(to: .models) }))
        case .github:
            StepLayout(title: "отправлять на github?",
                       text: "история хранится в приватном репозитории на github",
                       primary: (String(localized: "войти через github"), { model.startGitHubLogin() }),
                       secondary: (String(localized: "нет, только на этом маке"), { model.go(to: .models) }))
        case .githubCode:
            GitHubCodeStep(model: model)
        case .githubDone:
            StepLayout(title: "готово!",
                       text: String(localized: "создали приватный репозиторий \(model.githubRepository ?? "notes"). история отправляется туда сама раз в день"),
                       primary: (String(localized: "дальше"), { model.go(to: .models) }))
        case .models:
            StepLayout(title: "модели",
                       text: "выбери одну, всегда можно сменить в настройках",
                       primary: (String(localized: "дальше"), { model.startDownload(); model.go(to: .download) }),
                       primaryY: 374) {
                ModelPicker(model: model)
            }
        case .download:
            StepLayout(title: "модели",
                       text: "работают без интернета, скачиваются один раз",
                       // Скачивание идёт в фоне — ждать его конца не нужно.
                       primary: (String(localized: "дальше"), { model.go(to: .permissions) })) {
                DownloadRow(model: model)
            }
        case .permissions:
            StepLayout(title: "пару моментиков",
                       text: "нужны для стабильной работы",
                       primary: (String(localized: "дальше"), { model.go(to: .password) }),
                       primaryY: 374) {
                PermissionRows()
            }
        case .password:
            StepLayout(title: "установим пароль?",
                       text: nil,
                       primary: (String(localized: "дальше"), { model.finish() }),
                       primaryY: 359) {
                PasswordRows(model: model)
            }
        }
    }
}

private extension OnboardingModel {
    func vaultChosen(_ url: URL) {
        if VaultStore.isInICloud(url), !VaultPicker.confirmICloud() { return }
        do {
            try VaultStore.save(url)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        vaultURL = url
        go(to: .git)
    }

    // git init в папке: .gitignore и первый коммит «начало истории» (NotesCore.GitVault).
    func initializeGit() {
        guard let vaultURL else {
            // Папки нет только в отладке, когда шаг открыли напрямую.
            wantsGit = true
            go(to: .github)
            return
        }
        Task {
            do {
                // libgit2 работает с диском синхронно — уводим с главного потока, чтобы не замер UI.
                try await Task.detached { _ = try GitVault.prepare(at: vaultURL) }.value
                SyncController.shared.start(vault: vaultURL)
                wantsGit = true
                go(to: .github)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    func startGitHubLogin() {
        guard GitHubApp.clientID != nil else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Вход в GitHub не настроен")
            alert.informativeText = String(localized: "Чтобы отправлять историю на GitHub, приложению нужен client id: его вписывают в GitHubApp.swift. Пока история остаётся только на этом Mac.")
            alert.runModal()
            return
        }
        go(to: .githubCode)
    }
}

// Шаг 4. Код живёт в GitHubLogin; уход с экрана отменяет вход (.task отменяется сам).
private struct GitHubCodeStep: View {
    let model: OnboardingModel
    @State private var login = GitHubLogin()
    @State private var attempt = 0

    var body: some View {
        StepLayout(title: "введи код на github",
                   text: "открой github.com/login/device и введи код. пароль не нужен",
                   primary: primary,
                   back: { model.go(to: .github) }) {
            DeviceCodeCapsule(state: login.state, renew: { attempt += 1 })
        }
        .task(id: attempt) {
            await login.run(vault: model.vaultURL) { repository in
                model.githubRepository = repository
                model.go(to: .githubDone)
            }
        }
    }

    private var primary: (String, () -> Void) {
        if case .waiting(let code, let url) = login.state {
            return ("открыть github", { DeviceCode.copy(code); NSWorkspace.shared.open(url) })
        }
        return ("открыть github", { DeviceCode.openGitHub() })
    }
}

// Общий каркас шага: заголовок, текст, своё содержимое посередине, кнопка и ссылка внизу.
struct StepLayout<Middle: View>: View {
    let title: String
    let text: String?
    var primary: (String, () -> Void)
    // Кнопка в разных кадрах стоит на разной высоте: 343 по умолчанию, 359 и 374 — где список длиннее.
    var primaryY: CGFloat = 343
    var secondary: (String, () -> Void)? = nil
    var back: (() -> Void)? = nil
    @ViewBuilder var middle: () -> Middle

    var body: some View {
        ZStack(alignment: .top) {
            if let back {
                Button("назад", action: back)
                    .buttonStyle(QuietLinkStyle())
                    .offset(y: 86 - Layout.sheetTop)
            }

            Text(LocalizedStringKey(title))
                .font(Martian.heading.font(26))
                .kerning(Theme.tracking(-7, size: 26))
                .foregroundStyle(Theme.ink)
                .offset(y: 96 - Layout.sheetTop)

            if let text {
                Text(LocalizedStringKey(text))
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(Theme.fg.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .frame(width: 380)
                    .offset(y: 137 - Layout.sheetTop)
            }

            middle()

            Button(primary.0, action: primary.1)
                .buttonStyle(CoralCapsuleStyle())
                .offset(y: primaryY - Layout.sheetTop)

            if let secondary {
                Button(secondary.0, action: secondary.1)
                    .buttonStyle(QuietLinkStyle())
                    .offset(y: 410 - Layout.sheetTop)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension StepLayout where Middle == EmptyView {
    init(title: String, text: String?, primary: (String, () -> Void),
         secondary: (String, () -> Void)? = nil, back: (() -> Void)? = nil) {
        self.init(title: title, text: text, primary: primary, secondary: secondary, back: back) { EmptyView() }
    }
}

// Капсула с кодом GitHub (кадр 4). Коралловое свечение по краям внутри — пульсирует, пока ждём подтверждения.
struct DeviceCodeCapsule: View {
    let state: GitHubLogin.State
    let renew: () -> Void
    @State private var glow = false
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Color(white: 249 / 255)
                    .shadow(.inner(color: Theme.coral.opacity(glow ? 1 : 0.35), radius: 10.2, x: 3, y: 4))
                    .shadow(.inner(color: Theme.coral.opacity(glow ? 1 : 0.35), radius: 10, x: -3, y: -4)))
                .frame(width: 520, height: 100)

            Text(headline)
                .font(Martian.heading.font(40))
                .kerning(Theme.tracking(2, size: 40))
                .foregroundStyle(Theme.ink.opacity(isWaiting ? 1 : 0.3))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(width: 480)
                .offset(y: 233 - 207)

            caption.offset(y: 281 - 207)
        }
        .offset(y: 207 - Layout.sheetTop)
        // В тёмном кадре «код гитхаба(4)» капсула с кодом остаётся светлой.
        .environment(\.colorScheme, .light)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    private var isWaiting: Bool {
        if case .waiting = state { return true }
        return false
    }

    private var headline: String {
        switch state {
        // GitHub отдаёт код через дефис, в макете — через тире.
        case .waiting(let code, _): code.replacingOccurrences(of: "-", with: "–")
        case .requesting: "····–····"
        case .connecting: String(localized: "подключаем")
        case .expired: String(localized: "код истёк")
        case .failed: String(localized: "не вышло")
        }
    }

    @ViewBuilder
    private var caption: some View {
        switch state {
        case .waiting(let code, _):
            Button(copied ? "скопировано" : "скопировать код") {
                DeviceCode.copy(code)
                copied = true
            }
            .buttonStyle(QuietLinkStyle(size: 10))
        case .expired, .failed:
            Button(failureText) { renew() }
                .buttonStyle(QuietLinkStyle(size: 10))
        case .requesting, .connecting:
            EmptyView()
        }
    }

    private var failureText: String {
        if case .failed(let reason) = state { return String(localized: "\(reason) — попробовать снова") }
        return String(localized: "получить новый код")
    }
}

enum DeviceCode {
    static func copy(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    static func openGitHub() {
        if let url = URL(string: "https://github.com/login/device") { NSWorkspace.shared.open(url) }
    }
}

// Выбор папки хранилища через системные окна Finder.
// Тексты системных окон — обычными предложениями, с заглавной: это окна macOS, а не наш интерфейс.
enum VaultPicker {
    // Предупреждение про iCloud Drive (CONTEXT.md): true — пользователь всё равно хочет эту папку.
    static func confirmICloud() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Папка лежит в iCloud Drive")
        alert.informativeText = String(localized: "iCloud синхронизирует историю git по частям и может её повредить. Лучше выбрать папку вне iCloud Drive.")
        alert.addButton(withTitle: String(localized: "Выбрать другую"))
        alert.addButton(withTitle: String(localized: "Всё равно использовать"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    static func choose(_ done: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Выбрать")
        panel.message = String(localized: "Выбери папку, где будут лежать заметки.")
        panel.begin { if $0 == .OK, let url = panel.url { done(url) } }
    }

    static func create(_ done: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "notes"
        panel.canCreateDirectories = true
        panel.prompt = "Создать"
        panel.message = String(localized: "Новая папка для заметок. Обычные файлы, открываются любым редактором.")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                done(url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
