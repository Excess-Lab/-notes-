import Foundation

// Запрос поиска — один на всё: заметки, задачи, события, видео и расшифровки (ТЗ 30.10.2026).
// Слова без учёта регистра и ё/е; совпало — значит, в тексте есть все слова запроса.
public struct SearchQuery: Sendable {
    public let words: [String]
    public init(_ text: String) {
        words = NoteLibrary.normalize(text).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public var isEmpty: Bool { words.isEmpty }

    // Слова можно найти в разных полях: одно в названии события, другое в его месте.
    public func matches(_ texts: String...) -> Bool {
        let texts = texts.map(NoteLibrary.normalize)
        return !words.isEmpty && words.allSatisfy { word in texts.contains { $0.contains(word) } }
    }
}

extension Transcript {
    // Упоминание в расшифровке: все слова — где угодно в тексте, показываем кусок с первым словом и его время.
    public func mention(of query: SearchQuery) -> Segment? {
        guard query.matches(text), let first = query.words.first else { return nil }
        return segments.first { NoteLibrary.normalize($0.text).contains(first) }
    }
}
