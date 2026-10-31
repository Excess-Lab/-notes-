import Foundation
import FoundationModels

// Apple Intelligence — по желанию, выключено по умолчанию (ТЗ 31.10.2026: «интеграция с apple intelligence по апи,
// как доп фича в настройки»). Модель системная и работает на этом mac: в сеть ничего не уходит, своей модели
// в сборке нет. Окно у неё ~4096 токенов, поэтому длинный текст сжимаем по частям, а потом части — в одно.
enum Intelligence {
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "intelligence") }
        set { UserDefaults.standard.set(newValue, forKey: "intelligence") }
    }

    // nil — можно пользоваться; иначе — почему нельзя, обычными словами для строки настроек.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "этот mac не поддерживает apple intelligence"
        case .unavailable(.appleIntelligenceNotEnabled): "включи apple intelligence в системных настройках"
        case .unavailable(.modelNotReady): "модель ещё загружается системой"
        case .unavailable: "сейчас недоступна"
        }
    }

    static var isReady: Bool { enabled && unavailableReason == nil }

    // Перечислять в инструкции «решения, задачи, цифры» нельзя: на коротком тексте модель возвращала сами эти слова.
    private static let instructions = """
        Пользователь присылает расшифровку разговора или заметку. Перескажи её содержание кратко, на языке текста: \
        маркированный список из 2–6 пунктов, каждый пункт — конкретный факт или договорённость из текста. \
        Ничего не добавляй от себя и не пиши вступлений.
        """
    // Кусок текста на один запрос: ~5000 знаков кириллицы помещаются в окно вместе с ответом.
    private static let piece = 5000

    static func summary(of text: String) async throws -> String {
        let parts = split(text)
        if parts.count == 1 { return try await ask(parts[0]) }
        var partial: [String] = []
        for part in parts { partial.append(try await ask(part)) }
        return try await summary(of: partial.joined(separator: "\n"))
    }

    private static func ask(_ text: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: "Текст:\n\"\"\"\n\(text)\n\"\"\"").content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // По границам предложений, чтобы не резать мысль посередине.
    static func split(_ text: String) -> [String] {
        var parts: [String] = [], current = ""
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            if current.count + sentence.count > piece, !current.isEmpty { parts.append(current); current = "" }
            current += sentence
        }
        if !current.isEmpty || parts.isEmpty { parts.append(current) }
        return parts
    }
}
