import NotesCore
import SwiftUI

// Вход при запуске — кадры «вход — пинкод(11)» и «вход — неверный(11.1)»: тот же лист, что у шагов,
// заголовок на y = 96, подпись на 137, ячейки на 196 (координаты окна). Включён Touch ID — система
// сразу спрашивает отпечаток, а пинкод остаётся запасным путём.
struct UnlockStep: View {
    let onUnlock: () -> Void
    @State private var unlock = PinUnlock()
    @State private var monitor: Any?
    @State private var shake = 0
    private let store = PinStore()
    private let hasPin = PinStore().isSet

    var body: some View {
        ZStack(alignment: .top) {
            Text(hasPin ? "введи пинкод" : "приложи палец")
                .font(Martian.heading.font(26))
                .kerning(Theme.tracking(-7, size: 26))
                .foregroundStyle(Theme.ink)
                .offset(y: 96 - Layout.sheetTop)
            Text(subtitle)
                .font(Martian.body.font(13))
                .kerning(Theme.tracking(-7, size: 13))
                .foregroundStyle(unlock.stage == .wrong ? Theme.coral : .black.opacity(0.3))
                .contentTransition(.opacity)
                .offset(y: 137 - Layout.sheetTop)
            if hasPin {
                PinCells(filled: unlock.stage == .unlocked ? PinEntry.length : unlock.digits.count,
                         current: unlock.stage == .enter ? unlock.digits.count : nil,
                         isError: unlock.stage == .wrong, shake: shake)
                    .offset(y: 196 - Layout.sheetTop)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .animation(.smooth(duration: 0.35), value: unlock)
        // Нажатие на лист — ещё раз спросить Touch ID, если окно системы закрыли.
        .onTapGesture { askBiometrics() }
        .onAppear {
            if hasPin { monitor = PinKeys.listen(handle) }
            #if DEBUG
            for character in UserDefaults.standard.string(forKey: "pinPreview") ?? "" { input(character) }
            #endif
            askBiometrics()
        }
        .onDisappear { PinKeys.stop(monitor); monitor = nil }
    }

    private var subtitle: String {
        if unlock.stage == .wrong { return "неверный пинкод" }
        if BiometricLock.isEnabled { return hasPin ? "или приложи палец к touch id" : "к touch id, чтобы открыть заметки" }
        return "чтобы открыть заметки"
    }

    private func handle(_ key: PinKeys.Key) {
        switch key {
        case .escape: break   // отменять вход некуда
        case .delete: unlock.deleteBackward()
        case .character(let character): input(character)
        }
    }

    private func input(_ character: Character) {
        unlock.type(character, verify: store.verify)
        switch unlock.stage {
        case .wrong where unlock.digits.isEmpty:
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
        case .unlocked:
            finish()
        default:
            break
        }
    }

    private func askBiometrics() {
        guard BiometricLock.isEnabled, unlock.stage != .unlocked else { return }
        Task {
            if await BiometricLock.unlock() { finish() }
        }
    }

    private func finish() {
        PinKeys.stop(monitor)
        monitor = nil
        Task {
            // Четыре точки успевают показаться, прежде чем карточка уйдёт.
            try? await Task.sleep(for: .seconds(0.3))
            onUnlock()
        }
    }
}
