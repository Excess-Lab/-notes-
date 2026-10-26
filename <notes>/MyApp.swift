import AppKit
import SwiftUI

@main struct MyApp: App {
    @State private var onboarding = OnboardingModel()

    init() {
        FontRegistrar.registerBundledFonts()
        #if DEBUG
        // Снимать тёмную тему, не переключая систему: `--args -appearance dark`.
        if UserDefaults.standard.string(forKey: "appearance") == "dark" {
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        #endif
    }

    var body: some Scene {
        // Обычная полоса заголовка macOS: кнопки окна слева, по центру «<notes>».
        // Сцена 560×440 из макета идёт под ней.
        WindowGroup("<notes>") {
            OnboardingView(model: onboarding)
                // Папка уже выбрана и под git — история ведётся с первой секунды, даже пока открыт онбординг.
                .task { if let vault = onboarding.vaultURL { SyncController.shared.start(vault: vault) } }
                // Закрываем заметки, когда Mac заблокировали или приложение долго не трогали.
                .task { AppLock.shared.start(model: onboarding) }
                // Надиктовка работает с запуска приложения, из любого окна (⌥ space).
                .task {
                    DictationController.shared.start()
                    #if DEBUG
                    if let name = UserDefaults.standard.string(forKey: "orbPreview") {
                        await DictationController.shared.debugShowOrb(name)
                    }
                    if let path = UserDefaults.standard.string(forKey: "dictationTestFile") {
                        await DictationController.shared.debugRun(file: URL(fileURLWithPath: path))
                    }
                    #endif
                }
        }
        .windowResizability(.contentSize)
        .commands {
            // Чтобы смотреть анимацию загрузки много раз подряд, не перезапуская приложение.
            CommandMenu("Отладка") {
                Button("Повторить загрузку") { onboarding.restart() }
                    .keyboardShortcut("r")
                Button("Следующий шаг") { onboarding.debugNext() }
                    .keyboardShortcut("]")
            }
        }
    }
}
