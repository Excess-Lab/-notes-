import SwiftUI

// Состояние первого входа. Шаги и ветки — по docs/ONBOARDING.md, номера совпадают с кадрами в Figma.
@Observable
final class OnboardingModel {
    enum Phase { case loading, steps }

    enum Step: Int, CaseIterable {
        case welcome = 1, git, github, githubCode, githubDone, models
    }

    var phase: Phase = .loading
    var step: Step = .welcome
    // Папка хранилища, которую выбрали или создали на шаге 1.
    var vaultURL: URL?
    // Пользователь согласился сделать git-репозиторий в папке (сам git init — этап 2 в ROADMAP).
    var wantsGit = false
    // Меняется при каждом перезапуске, чтобы SwiftUI пересоздал сцену с нуля.
    var runID = UUID()

    init() {
        #if DEBUG
        // Запуск сразу с нужного шага, без загрузки: `open <notes>.app --args -onboardingStep 4`.
        // Нужно, чтобы снимать каждый шаг для сверки с Figma.
        let start = UserDefaults.standard.integer(forKey: "onboardingStep")
        if let step = Step(rawValue: start) {
            phase = .steps
            self.step = step
        }
        #endif
    }

    func go(to step: Step) {
        withAnimation(.smooth(duration: 0.8)) { self.step = step }
    }

    func restart() {
        phase = .loading
        step = .welcome
        vaultURL = nil
        wantsGit = false
        runID = UUID()
    }

    // Только для меню «Отладка»: пролистать шаги без настоящих действий.
    func debugNext() {
        if phase == .loading { phase = .steps; return }
        let next = Step(rawValue: step.rawValue + 1) ?? .welcome
        go(to: next)
    }
}
