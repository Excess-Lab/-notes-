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
        case .unavailable(.deviceNotEligible): String(localized: "этот mac не поддерживает apple intelligence")
        case .unavailable(.appleIntelligenceNotEnabled): String(localized: "включи apple intelligence в системных настройках")
        case .unavailable(.modelNotReady): String(localized: "модель ещё загружается системой")
        case .unavailable: String(localized: "сейчас недоступна")
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

    // Задачи из расшифровки: модель отвечает структурой (guided generation), а не текстом, который надо разбирать.
    @Generable struct Found {
        @Guide(description: "Задачи и поручения, о которых договорились в тексте. Пусто, если их нет.", .maximumCount(10))
        var tasks: [Item]
    }
    @Generable struct Item {
        @Guide(description: "Задача целиком: глагол в неопределённой форме, кому и о чём. Например: «Позвонить Ивану насчёт дизайна»")
        var title: String
        @Guide(description: "Срок из списка дат в инструкции в формате yyyy-MM-dd, если в тексте назван срок; иначе пустая строка")
        var date: String
    }

    static func tasks(from text: String, today: Date = .now) async throws -> [(title: String, date: String?)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        // Считать даты модель не умеет («завтра» превращала в сегодня), поэтому даём ей готовый список дней.
        let named = DateFormatter()
        named.locale = Locale(identifier: "ru_RU")
        named.dateFormat = "yyyy-MM-dd (EEEE)"
        let words = ["сегодня — ", "завтра — ", "послезавтра — "]
        let days = (0..<8).map { i in
            (i < 3 ? words[i] : "") + named.string(from: Calendar.current.date(byAdding: .day, value: i, to: today)!)
        }.joined(separator: "\n")
        var found: [(String, String?)] = []
        for part in split(text) {
            let session = LanguageModelSession(instructions: """
                Найди в тексте задачи, о которых договорились. Не придумывай задач, которых нет. Даты ближайших дней:
                \(days)
                """)
            let answer = try await session.respond(to: "Текст:\n\"\"\"\n\(part)\n\"\"\"", generating: Found.self).content
            for item in answer.tasks where !item.title.trimmingCharacters(in: .whitespaces).isEmpty {
                // Дату берём, только если она настоящая: модель иногда пишет «нет» или «2026-13-40».
                found.append((item.title.trimmingCharacters(in: .whitespaces), formatter.date(from: item.date) != nil ? item.date : nil))
            }
        }
        return found
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
