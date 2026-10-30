import AppKit

// Иконка в Доке — тёмная, когда у приложения тёмная тема (ТЗ 30.10.2026). Тёмный вариант в AppIcon.icon
// система берёт, только если тёмные иконки включены у неё самой, поэтому меняем картинку в Доке сами:
// icon-dark.png собрана из bg-dark.png и logo-white.png того же AppIcon.icon. Светлая — системная.
@MainActor final class DockIcon {
    static let shared = DockIcon()
    private var observation: NSKeyValueObservation?
    private lazy var dark = Bundle.main.url(forResource: "icon-dark", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    func start() {
        apply()
        observation = NSApp.observe(\.effectiveAppearance) { _, _ in
            MainActor.assumeIsolated { DockIcon.shared.apply() }
        }
    }

    private func apply() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSApp.applicationIconImage = isDark ? dark : nil
    }
}
