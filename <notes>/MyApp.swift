import SwiftUI

@main struct MyApp: App {
    @State private var onboarding = OnboardingModel()

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        // Обычная полоса заголовка macOS: кнопки окна слева, по центру «<notes>».
        // Сцена 560×440 из макета идёт под ней.
        WindowGroup("<notes>") {
            OnboardingView(model: onboarding)
                // Папка уже выбрана и под git — история ведётся с первой секунды, даже пока открыт онбординг.
                .task { if let vault = onboarding.vaultURL { SyncController.shared.start(vault: vault) } }
                // Макет только светлый. Без этого в тёмной теме системы стекло и заголовок темнеют.
                .preferredColorScheme(.light)
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
