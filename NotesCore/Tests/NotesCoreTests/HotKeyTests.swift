import Carbon.HIToolbox
import Foundation
import Testing
@testable import NotesCore

@Suite("горячая клавиша надиктовки")
struct HotKeyTests {
    @Test("по умолчанию ⌥ space — как на шаге «пару моментиков»")
    func defaultCombo() {
        #expect(HotKeyCombo.default.display == "⌥ space")
        #expect(HotKeyCombo.default.problem == nil)
    }

    @Test("модификаторы в порядке меню macOS: ⌃⌥⇧⌘")
    func displayOrder() {
        let combo = HotKeyCombo(keyCode: UInt16(kVK_ANSI_D), modifiers: [.command, .shift, .control, .option], key: "d")
        #expect(combo.display == "⌃⌥⇧⌘ d")
    }

    @Test("для системы модификаторы переводятся в флаги Carbon")
    func carbonFlags() {
        let combo = HotKeyCombo(keyCode: 0, modifiers: [.option, .command], key: "a")
        #expect(combo.carbonModifiers == UInt32(optionKey | cmdKey))
    }

    @Test("без ⌘, ⌥ или ⌃ нельзя — иначе перехватим обычный набор текста")
    func needsModifier() {
        #expect(HotKeyCombo(keyCode: UInt16(kVK_ANSI_A), modifiers: [], key: "a").problem == .needsModifier)
        // Один ⇧ тоже не считается: ⇧A — это просто заглавная буква.
        #expect(HotKeyCombo(keyCode: UInt16(kVK_ANSI_A), modifiers: .shift, key: "a").problem == .needsModifier)
        // Функциональные клавиши можно и без модификаторов: в тексте их не набирают.
        #expect(HotKeyCombo(keyCode: UInt16(kVK_F5), modifiers: [], key: "f5").problem == nil)
    }

    @Test("системные сочетания не даём: ⌘ space — это Spotlight")
    func reserved() {
        #expect(HotKeyCombo(keyCode: UInt16(kVK_Space), modifiers: .command, key: "space").problem == .reserved)
        #expect(HotKeyCombo(keyCode: UInt16(kVK_ANSI_Q), modifiers: .command, key: "q").problem == .reserved)
    }

    @Test("подписи особых клавиш и букв — строчными")
    func labels() {
        #expect(HotKeyCombo.label(forKeyCode: kVK_Space, characters: " ") == "space")
        #expect(HotKeyCombo.label(forKeyCode: kVK_F12, characters: nil) == "f12")
        #expect(HotKeyCombo.label(forKeyCode: kVK_ANSI_D, characters: "D") == "d")
        // В русской раскладке та же клавиша — «в», подписываем тем, что человек видит.
        #expect(HotKeyCombo.label(forKeyCode: kVK_ANSI_D, characters: "В") == "в")
    }

    @Test("сочетание сохраняется и читается обратно, а без сохранённого — ⌥ space")
    func persistence() throws {
        let defaults = try #require(UserDefaults(suiteName: "notes-hotkey-\(UUID().uuidString)"))
        #expect(HotKeyStore.load(defaults) == .default)

        let combo = HotKeyCombo(keyCode: UInt16(kVK_ANSI_D), modifiers: [.control, .command], key: "d")
        HotKeyStore.save(combo, defaults)

        #expect(HotKeyStore.load(defaults) == combo)
    }
}
