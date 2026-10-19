import AppKit
import NotesCore
import SwiftUI

// Строка «горячая клавиша» на шаге 8: показывает сочетание и записывает новое по «изменить».
// Запись — через локальный монитор клавиш: окно наше и в фокусе, разрешения не нужны.
struct HotKeyRow: View {
    @State private var combo = DictationController.shared.combo
    @State private var recording = false
    @State private var hint: String?
    @State private var monitor: Any?

    var body: some View {
        GlassRow {
            VStack(alignment: .leading, spacing: 2) {
                Text("горячая клавиша")
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(Theme.ink)
                Text(hint ?? (recording ? "нажми сочетание, esc — отмена" : "надиктовка из любого приложения"))
                    .font(Martian.body.font(11))
                    .kerning(Theme.tracking(-7, size: 11))
                    .foregroundStyle(hint == nil ? .black.opacity(0.3) : Theme.coral)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
            Keycap(text: recording ? "…" : combo.display)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.coral, lineWidth: recording ? 1 : 0))
            Button(recording ? "отмена" : "изменить") { recording ? stop() : start() }
                .buttonStyle(QuietPillStyle())
        }
        .animation(.smooth(duration: 0.3), value: recording)
        .animation(.smooth(duration: 0.3), value: hint)
        .onDisappear { stop() }
    }

    private func start() {
        hint = nil
        recording = true
        DictationController.shared.suspendHotKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil   // клавишу «съедаем»: она для записи, а не для окна
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        DictationController.shared.resumeHotKey()
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { stop(); return }   // esc — отмена
        let flags = event.modifierFlags
        var modifiers: HotKeyCombo.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        let candidate = HotKeyCombo(keyCode: event.keyCode, modifiers: modifiers,
                                    key: HotKeyCombo.label(forKeyCode: Int(event.keyCode),
                                                           characters: event.charactersIgnoringModifiers))
        switch candidate.problem {
        case .needsModifier: hint = "нужен ⌘, ⌥ или ⌃"; return
        case .reserved: hint = "это сочетание занято системой"; return
        case nil: break
        }
        stop()
        if DictationController.shared.changeHotKey(to: candidate) {
            combo = candidate
            hint = nil
        } else {
            hint = "занято другим приложением"
        }
    }
}
