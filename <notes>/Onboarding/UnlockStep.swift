import AppKit
import NotesCore
import SwiftUI

// Вход — кадры «вход — пинкод(11)», «неверный(11.1)», «подожди(11.2)»: тот же лист, что у шагов,
// заголовок на y = 96, подпись на 137, ячейки на 196, «забыл пинкод» на 410 (координаты окна).
// Включён Touch ID — система спрашивает отпечаток, а пинкод остаётся запасным путём.
struct UnlockStep: View {
    // Окно сброса пинкода открыто поверх — клавиши ловит оно, а не мы.
    var paused = false
    let onForgot: () -> Void
    let onUnlock: () -> Void

    @State private var unlock = PinUnlock()
    @State private var limiter = LockMemory().limiter
    @State private var monitor: Any?
    @State private var shake = 0
    @State private var biometricsPending = false
    private let store = PinStore()
    private let hasPin = PinStore().isSet

    var body: some View {
        // Раз в секунду — чтобы обратный отсчёт паузы шёл сам.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = limiter.remaining(now: context.date)
            ZStack(alignment: .top) {
                Text(hasPin ? "введи пинкод" : "приложи палец")
                    .font(Martian.heading.font(26))
                    .kerning(Theme.tracking(-7, size: 26))
                    .foregroundStyle(Theme.ink)
                    .offset(y: 96 - Layout.sheetTop)
                Text(subtitle(wait: wait))
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(unlock.stage == .wrong || wait != nil ? Theme.coral : Theme.fg.opacity(0.3))
                    .contentTransition(.opacity)
                    .offset(y: 137 - Layout.sheetTop)
                if hasPin {
                    PinCells(filled: unlock.stage == .unlocked ? PinEntry.length : unlock.digits.count,
                             current: unlock.stage == .enter && wait == nil ? unlock.digits.count : nil,
                             isError: unlock.stage == .wrong && wait == nil, shake: shake)
                        .opacity(wait == nil ? 1 : 0.3)
                        .offset(y: 196 - Layout.sheetTop)
                    Button("забыл пинкод", action: onForgot)
                        .buttonStyle(QuietLinkStyle())
                        .offset(y: 410 - Layout.sheetTop)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .animation(.smooth(duration: 0.35), value: unlock)
        // Нажатие на лист — ещё раз спросить Touch ID, если окно системы закрыли.
        .onTapGesture { askBiometrics() }
        .onAppear {
            listen()
            #if DEBUG
            for character in UserDefaults.standard.string(forKey: "pinPreview") ?? "" { input(character) }
            #endif
            askBiometrics()
        }
        .onDisappear(perform: stopListening)
        .onChange(of: paused) { _, paused in paused ? stopListening() : listen() }
        // Mac проснулся, а приложение в фоне — окно Touch ID появится, когда человек к нему вернётся.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if biometricsPending { askBiometrics() }
        }
    }

    private func subtitle(wait: TimeInterval?) -> String {
        if let wait { return "много попыток — подожди \(Self.format(wait))" }
        if unlock.stage == .wrong { return "неверный пинкод" }
        if BiometricLock.isEnabled { return hasPin ? "или приложи палец к touch id" : "к touch id, чтобы открыть заметки" }
        return "чтобы открыть заметки"
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let value = Int(seconds.rounded(.up))
        return value < 60 ? "\(value) с" : "\(Int((Double(value) / 60).rounded(.up))) мин"
    }

    private func listen() {
        guard hasPin, monitor == nil, !paused else { return }
        monitor = PinKeys.listen(handle)
    }

    private func stopListening() {
        PinKeys.stop(monitor)
        monitor = nil
    }

    private func handle(_ key: PinKeys.Key) {
        switch key {
        case .escape: break   // отменять вход некуда
        case .delete: unlock.deleteBackward()
        case .character(let character): input(character)
        }
    }

    private func input(_ character: Character) {
        // Пока идёт пауза, цифры не принимаем: иначе перебор продолжался бы, просто без ответа.
        guard limiter.remaining() == nil else { return }
        unlock.type(character, verify: store.verify)
        switch unlock.stage {
        case .wrong where unlock.digits.isEmpty:
            limiter.recordFailure()
            LockMemory().limiter = limiter
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
        case .unlocked:
            finish()
        default:
            break
        }
    }

    private func askBiometrics() {
        guard BiometricLock.isEnabled, unlock.stage != .unlocked, !paused else { return }
        guard NSApp.isActive else { biometricsPending = true; return }
        biometricsPending = false
        Task {
            if await BiometricLock.unlock() { finish() }
        }
    }

    private func finish() {
        stopListening()
        limiter.reset()
        LockMemory().limiter = limiter
        Task {
            // Четыре точки успевают показаться, прежде чем лист опустеет.
            try? await Task.sleep(for: .seconds(0.3))
            onUnlock()
        }
    }
}
