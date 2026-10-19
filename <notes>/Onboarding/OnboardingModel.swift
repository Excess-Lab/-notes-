import NotesCore
import NotesSpeech
import SwiftUI

// Состояние первого входа. Шаги и ветки — по docs/ONBOARDING.md, номера совпадают с кадрами в Figma.
@Observable
final class OnboardingModel {
    // loading — сцена загрузки, steps — лист с шагами, finished — «все готово» на стекле.
    // locked — повторный запуск с пинкодом или Touch ID: та же загрузка, потом карточка входа;
    // unlocked — вход пройден (основного экрана пока нет, остаются планки с логотипом).
    enum Phase { case loading, steps, finished, locked, unlocked }

    enum Step: Int, CaseIterable {
        case welcome = 1, git, github, githubCode, githubDone, models, download, permissions, password
    }

    var phase: Phase = .loading
    var step: Step = .welcome
    // Папка хранилища, которую выбрали или создали на шаге 1.
    var vaultURL: URL?
    // Пользователь согласился сделать git-репозиторий в папке (сам git init — этап 2 в ROADMAP).
    var wantsGit = false
    // Полное имя репозитория на GitHub после входа, например makark/notes.
    var githubRepository: String?
    // Модель распознавания: выбор сразу сохраняется — его же берёт надиктовка.
    var speechModel: SpeechModel = SpeechSettings.model {
        didSet { SpeechSettings.model = speechModel }
    }
    // Доля скачанной модели, 0…1, и когда скачивание началось — для «осталось N мин».
    var downloadProgress: Double = 0
    var downloadStarted: Date?
    var downloadFailed = false
    // Окно ввода пинкода поверх шага 9.
    var pinEntryShown = false
    // Меняется при каждом перезапуске, чтобы SwiftUI пересоздал сцену с нуля.
    var runID = UUID()

    init() {
        vaultURL = VaultStore.restore()
        if UserDefaults.standard.bool(forKey: Self.completedKey), PinStore().isSet || BiometricLock.isEnabled {
            phase = .locked
        }
        #if DEBUG
        // Запуск сразу с нужного шага, без загрузки: `open <notes>.app --args -onboardingStep 4`.
        // 10 — финальный экран. Нужно, чтобы снимать каждый шаг для сверки с Figma.
        let start = UserDefaults.standard.integer(forKey: "onboardingStep")
        if start == 10 {
            phase = .finished
        } else if start == 11 {
            phase = .locked
        } else if let step = Step(rawValue: start) {
            phase = .steps
            self.step = step
        }
        pinEntryShown = step == .password && phase == .steps && UserDefaults.standard.string(forKey: "pinPreview") != nil
        #endif
    }

    func go(to step: Step) {
        withAnimation(.smooth(duration: 0.8)) { self.step = step }
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        withAnimation(.smooth(duration: 1.4)) { phase = .finished }
    }

    // Первый вход пройден. Пока основного экрана нет, только запоминаем; потом по этому флагу
    // при запуске сразу откроются заметки.
    static let completedKey = "onboardingCompleted"

    func restart() {
        phase = .loading
        step = .welcome
        vaultURL = nil
        wantsGit = false
        githubRepository = nil
        downloadProgress = 0
        downloadStarted = nil
        downloadFailed = false
        runID = UUID()
    }

    // Только для меню «Отладка»: пролистать шаги без настоящих действий.
    func debugNext() {
        switch phase {
        case .loading: withAnimation(.smooth(duration: 1.3)) { phase = .steps }
        case .finished, .locked, .unlocked: restart()
        case .steps:
            if let next = Step(rawValue: step.rawValue + 1) { go(to: next) } else { finish() }
        }
    }
}
