import Carbon.HIToolbox
import Foundation

// Сочетание клавиш для надиктовки. Хранится в UserDefaults как JSON, показывается на клавише
// в стиле интерфейса — строчными: «⌥ space», «⌃⌘ d».
public struct HotKeyCombo: Codable, Equatable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public let keyCode: UInt16
    public let modifiers: Modifiers
    // Подпись клавиши, снятая при записи: по коду клавиши букву не узнать — она зависит от раскладки.
    public let key: String

    public init(keyCode: UInt16, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public static let `default` = HotKeyCombo(keyCode: UInt16(kVK_Space), modifiers: .option, key: "space")

    // Как в меню macOS: ⌃⌥⇧⌘, затем клавиша через пробел.
    public var display: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols.isEmpty ? key : "\(symbols) \(key)"
    }

    // Модификаторы в виде, который ждёт Carbon RegisterEventHotKey.
    public var carbonModifiers: UInt32 {
        var value = 0
        if modifiers.contains(.control) { value |= controlKey }
        if modifiers.contains(.option) { value |= optionKey }
        if modifiers.contains(.shift) { value |= shiftKey }
        if modifiers.contains(.command) { value |= cmdKey }
        return UInt32(value)
    }

    public enum Problem: Equatable, Sendable {
        // Без ⌘, ⌥ или ⌃ сочетание перехватит обычный набор текста в любом приложении.
        case needsModifier
        // Эти сочетания система не отдаёт или они нужны всем: ⌘Q, ⌘Tab, ⌘Space (Spotlight)…
        case reserved
    }

    public var problem: Problem? {
        let isFunctionKey = Self.functionKeys.contains(Int(keyCode))
        if !isFunctionKey && modifiers.intersection([.control, .option, .command]).isEmpty { return .needsModifier }
        if Self.reserved.contains(where: { $0.keyCode == keyCode && $0.modifiers == modifiers }) { return .reserved }
        return nil
    }

    // Подписи особых клавиш, у которых нет буквы.
    public static func label(forKeyCode code: Int, characters: String?) -> String {
        switch code {
        case kVK_Space: return "space"
        case kVK_Return: return "return"
        case kVK_Tab: return "tab"
        case kVK_Delete: return "delete"
        case kVK_Escape: return "esc"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            if let index = functionKeys.firstIndex(of: code) { return "f\(index + 1)" }
            // Буква из раскладки — строчная, как весь интерфейс.
            return (characters ?? "?").lowercased()
        }
    }

    static let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                               kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    static let reserved: [HotKeyCombo] = [
        HotKeyCombo(keyCode: UInt16(kVK_Space), modifiers: .command, key: "space"),       // Spotlight
        HotKeyCombo(keyCode: UInt16(kVK_Tab), modifiers: .command, key: "tab"),           // переключение приложений
        HotKeyCombo(keyCode: UInt16(kVK_ANSI_Q), modifiers: .command, key: "q"),          // выход
        HotKeyCombo(keyCode: UInt16(kVK_ANSI_W), modifiers: .command, key: "w"),          // закрыть окно
        HotKeyCombo(keyCode: UInt16(kVK_Space), modifiers: .control, key: "space"),       // смена раскладки
    ]
}

// Где хранится выбранное сочетание.
public enum HotKeyStore {
    static let key = "dictationHotKey"

    public static func load(_ defaults: UserDefaults = .standard) -> HotKeyCombo {
        guard let data = defaults.data(forKey: key),
              let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) else { return .default }
        return combo
    }

    public static func save(_ combo: HotKeyCombo, _ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(combo), forKey: key)
    }
}
