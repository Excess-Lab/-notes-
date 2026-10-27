import Foundation

// Расшифровка видео или аудио: куски текста с временем начала. Хранится вне хранилища
// (Application Support); в заметки попадает, только когда человек нажал «сохранить как заметку».
public struct Transcript: Codable, Hashable, Sendable {
    public struct Segment: Codable, Hashable, Sendable {
        public let start: Double
        public let end: Double
        public let text: String
        public init(start: Double, end: Double, text: String) {
            self.start = start
            self.end = end
            self.text = text
        }
    }

    public var segments: [Segment]
    public init(segments: [Segment]) { self.segments = segments }

    public var text: String { segments.map(\.text).joined(separator: " ") }
    public var wordCount: Int { NoteLibrary.wordCount(text) }

    // «12:31», а для часа и больше — «1:02:05».
    public static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    // Субтитры .srt: номер, «00:00:12,000 --> 00:00:31,500», текст, пустая строка.
    public var srt: String {
        func stamp(_ t: Double) -> String {
            let ms = Int((t * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms % 3_600_000 / 60_000, ms % 60_000 / 1000, ms % 1000)
        }
        return segments.enumerated().map { index, s in
            "\(index + 1)\n\(stamp(s.start)) --> \(stamp(s.end))\n\(s.text)\n"
        }.joined(separator: "\n")
    }

    // Заметка с метаданными во frontmatter — блоке «---» в начале, который понимают редакторы Markdown:
    // откуда расшифровка, когда загрузили, сколько длится, чем распознано.
    public func note(title: String, source: String, added: Date, duration: Double, model: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return """
        ---
        источник: \(source)
        загружено: \(formatter.string(from: added))
        длительность: \(Self.clock(duration))
        модель: \(model)
        слов: \(wordCount)
        ---

        """ + "\n" + markdown(title: title)
    }

    // Заметка: заголовок — имя файла, дальше строки с меткой времени. Обычный Markdown.
    public func markdown(title: String) -> String {
        "# \(title)\n\n" + segments.map { "**\(Self.clock($0.start))** \($0.text)" }.joined(separator: "\n\n") + "\n"
    }
}
