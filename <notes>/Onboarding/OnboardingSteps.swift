import SwiftUI
import AppKit

// Содержимое листа для каждого шага. Все координаты — из кадров Figma, от верха листа (y = 54 в окне).
struct OnboardingStepContent: View {
    let model: OnboardingModel

    var body: some View {
        switch model.step {
        case .welcome:
            StepLayout(title: "привет!",
                       text: "выбери папку куда сохранять заметки",
                       primary: ("создать папку", { VaultPicker.create { model.vaultChosen($0) } }),
                       secondary: ("выбрать папку", { VaultPicker.choose { model.vaultChosen($0) } }))
        case .git:
            StepLayout(title: "git в папке",
                       text: "сделаем из папки git-репозиторий — каждая правка сохранится в истории, и любую заметку можно откатить",
                       primary: ("инициализировать", { model.wantsGit = true; model.go(to: .github) }),
                       // Без git нечего отправлять на GitHub — сразу к моделям.
                       secondary: ("пропустить, настрою потом", { model.go(to: .models) }))
        case .github:
            StepLayout(title: "отправлять на github?",
                       text: "история будет храниться ещё и в приватном репозитории на github для синхронизации и восстановлений данных",
                       primary: ("войти через github", { model.go(to: .githubCode) }),
                       secondary: ("нет, только на этом маке", { model.go(to: .models) }))
        case .githubCode:
            StepLayout(title: "введи код на github",
                       text: "открой github.com/login/device и введи этот код, пароль от github приложению не нужен",
                       primary: ("открыть github", { DeviceCode.openGitHub() }),
                       back: { model.go(to: .github) }) {
                DeviceCodeCapsule(code: DeviceCode.placeholder)
            }
        case .githubDone:
            StepLayout(title: "готово!",
                       text: "создали приватный репозиторий makark/notes. история отправляется туда сама раз в день",
                       primary: ("дальше", { model.go(to: .models) }))
        case .models:
            StepLayout(title: "модели",
                       text: "выбери одну, всегда можно сменить в настройках",
                       primary: ("дальше", { model.startDownload(); model.go(to: .download) }),
                       primaryY: 374) {
                ModelPicker(model: model)
            }
        case .download:
            StepLayout(title: "модели",
                       text: "работают на твоём маке без интернета,  скачиваются один раз",
                       // Скачивание идёт в фоне — ждать его конца не нужно.
                       primary: ("дальше", { model.go(to: .permissions) })) {
                DownloadRow(model: model)
            }
        case .permissions:
            StepLayout(title: "пару моментиков",
                       text: "нужны  для того, что бы все работало стабильно",
                       primary: ("дальше", { model.go(to: .password) }),
                       primaryY: 374) {
                PermissionRows()
            }
        case .password:
            StepLayout(title: "установим пароль?",
                       text: nil,
                       primary: ("дальше", { model.finish() }),
                       primaryY: 359) {
                PasswordRows()
            }
        }
    }
}

private extension OnboardingModel {
    func vaultChosen(_ url: URL) {
        vaultURL = url
        go(to: .git)
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

            Text(title)
                .font(Martian.heading.font(26))
                .kerning(Theme.tracking(-7, size: 26))
                .foregroundStyle(Theme.ink)
                .offset(y: 96 - Layout.sheetTop)

            if let text {
                Text(text)
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(.black.opacity(0.3))
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
    let code: String
    @State private var glow = false
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Color(white: 249 / 255)
                    .shadow(.inner(color: Theme.coral.opacity(glow ? 1 : 0.35), radius: 10.2, x: 3, y: 4))
                    .shadow(.inner(color: Theme.coral.opacity(glow ? 1 : 0.35), radius: 10, x: -3, y: -4)))
                .frame(width: 520, height: 100)

            Text(code)
                .font(Martian.heading.font(40))
                .kerning(Theme.tracking(2, size: 40))
                .foregroundStyle(Theme.ink)
                .offset(y: 233 - 207)

            Button(copied ? "скопировано" : "скопировать код") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.replacingOccurrences(of: "–", with: "-"), forType: .string)
                copied = true
            }
            .buttonStyle(QuietLinkStyle(size: 10))
            .offset(y: 281 - 207)
        }
        .offset(y: 207 - Layout.sheetTop)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}

enum DeviceCode {
    // Настоящий код выдаст GitHub Device Flow (CONTEXT.md). Пока приложение не зарегистрировано
    // на GitHub, показываем код из макета.
    static let placeholder = "WDJB–MJHT"

    static func openGitHub() {
        if let url = URL(string: "https://github.com/login/device") { NSWorkspace.shared.open(url) }
    }
}

// Выбор папки хранилища через системные окна Finder.
enum VaultPicker {
    static func choose(_ done: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "выбрать"
        panel.message = "папка, где будут лежать заметки"
        panel.begin { if $0 == .OK, let url = panel.url { done(url) } }
    }

    static func create(_ done: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "notes"
        panel.canCreateDirectories = true
        panel.prompt = "создать"
        panel.message = "новая папка для заметок"
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
