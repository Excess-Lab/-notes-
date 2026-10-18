import SwiftUI

// Состояние первого входа. Шаги и ветки — по docs/ONBOARDING.md, номера совпадают с кадрами в Figma.
@Observable
final class OnboardingModel {
    // loading — сцена загрузки, steps — лист с шагами, finished — «все готово» на стекле.
    enum Phase { case loading, steps, finished }

    enum Step: Int, CaseIterable {
        case welcome = 1, git, github, githubCode, githubDone, models, download, permissions, password
    }

    enum SpeechModel: CaseIterable {
        case gigaAM, whisperSmall, whisperLargeTurbo

        var name: String {
            switch self {
            case .gigaAM: "GigaAM v3"
            case .whisperSmall: "Whisper small"
            case .whisperLargeTurbo: "Whisper large-v3 turbo"
            }
        }

        var sizeMB: Double {
            switch self {
            case .gigaAM: 300
            case .whisperSmall: 466
            case .whisperLargeTurbo: 1600
            }
        }
    }

    var phase: Phase = .loading
    var step: Step = .welcome
    // Папка хранилища, которую выбрали или создали на шаге 1.
    var vaultURL: URL?
    // Пользователь согласился сделать git-репозиторий в папке (сам git init — этап 2 в ROADMAP).
    var wantsGit = false
    // По умолчанию выбрана GigaAM: лучше всех понимает русский (CONTEXT.md).
    var speechModel: SpeechModel = .gigaAM
    // Доля скачанной модели, 0…1.
    var downloadProgress: Double = 0
    // Меняется при каждом перезапуске, чтобы SwiftUI пересоздал сцену с нуля.
    var runID = UUID()

    init() {
        #if DEBUG
        // Запуск сразу с нужного шага, без загрузки: `open <notes>.app --args -onboardingStep 4`.
        // 10 — финальный экран. Нужно, чтобы снимать каждый шаг для сверки с Figma.
        let start = UserDefaults.standard.integer(forKey: "onboardingStep")
        if start == 10 {
            phase = .finished
        } else if let step = Step(rawValue: start) {
            phase = .steps
            self.step = step
        }
        #endif
    }

    func go(to step: Step) {
        withAnimation(.smooth(duration: 0.8)) { self.step = step }
    }

    func finish() {
        withAnimation(.smooth(duration: 1.4)) { phase = .finished }
    }

    func restart() {
        phase = .loading
        step = .welcome
        vaultURL = nil
        wantsGit = false
        speechModel = .gigaAM
        downloadProgress = 0
        runID = UUID()
    }

    // Только для меню «Отладка»: пролистать шаги без настоящих действий.
    func debugNext() {
        switch phase {
        case .loading: withAnimation(.smooth(duration: 1.3)) { phase = .steps }
        case .finished: restart()
        case .steps:
            if let next = Step(rawValue: step.rawValue + 1) { go(to: next) } else { finish() }
        }
    }
}
