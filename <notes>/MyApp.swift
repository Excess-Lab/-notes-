import NotesCore
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
            RootView(onboarding: onboarding)
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

// Первый вход и вход по пинкоду — окно 560×440; после входа — заметки 1200×760.
private struct RootView: View {
    let onboarding: OnboardingModel
    @State private var notes: NotesModel?

    var body: some View {
        Group {
            if onboarding.phase == .unlocked, let notes {
                NotesWindow(model: notes)
                    .transition(.opacity)
            } else {
                OnboardingView(model: onboarding)
            }
        }
        .animation(.smooth(duration: 0.6), value: onboarding.phase == .unlocked)
        // Модель заметок — одна на окно: создаём, когда есть папка хранилища.
        .onChange(of: onboarding.vaultURL, initial: true) { _, vault in
            guard let vault, notes?.library.root != vault.standardizedFileURL else { return }
            let model = NotesModel(vault: vault)
            #if DEBUG
            if let path = UserDefaults.standard.string(forKey: "notesOpen") {
                let url = vault.appendingPathComponent(path)
                model.open(path.hasSuffix(".md") ? .note(url) : .folder(url))
            }
            if let query = UserDefaults.standard.string(forKey: "notesSearch") {
                model.searchShown = true
                model.query = query
            }
            #endif
            notes = model
            if UserDefaults.standard.bool(forKey: "notesSelfTest") { Task { await model.selfTest() } }
        }
    }
}
