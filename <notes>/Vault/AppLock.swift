import AppKit
import NotesCore

// Умный вход: когда закрывать заметки, пока приложение работает (правила — NotesCore.LockPolicy).
// - Mac заблокировали или он уснул — закрываем сразу, и перезапуск тоже спросит пинкод.
// - Приложение было в фоне 15 минут и дольше — спрашиваем при возврате.
// - Ушли из приложения или закрыли его — запоминаем время: перезапуск в течение 5 минут без пинкода.
// Надиктовка от этого не зависит: заметок она не показывает.
final class AppLock {
    static let shared = AppLock()

    private weak var model: OnboardingModel?
    private var inactiveSince: Date?
    private var observers: [NSObjectProtocol] = []

    func start(model: OnboardingModel) {
        guard observers.isEmpty else { return }
        self.model = model
        let workspace = NSWorkspace.shared.notificationCenter
        let app = NotificationCenter.default
        observers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppLock.shared.lockNow() }
            },
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppLock.shared.lockNow() }
            },
            // Блокировка экрана (⌃⌘Q, закрыли крышку) приходит системным распределённым уведомлением.
            DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"),
                                                                object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppLock.shared.lockNow() }
            },
            app.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppLock.shared.wentAway() }
            },
            app.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppLock.shared.wentAway() }
            },
            app.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppLock.shared.cameBack() }
            },
        ]
    }

    private func lockNow() {
        guard OnboardingModel.lockConfigured else { return }
        // Отметку «только что работал» стираем: после блокировки Mac даже быстрый перезапуск спросит пинкод.
        LockMemory().lastSeenUnlocked = nil
        model?.lock()
    }

    private func wentAway() {
        inactiveSince = Date()
        if model?.phase == .unlocked { LockMemory().lastSeenUnlocked = Date() }
    }

    private func cameBack() {
        defer { inactiveSince = nil }
        guard OnboardingModel.lockConfigured,
              LockPolicy.needsUnlockOnReturn(inactiveSince: inactiveSince) else { return }
        model?.lock()
    }
}
