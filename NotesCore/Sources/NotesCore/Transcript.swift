import Foundation

// Расшифровка видео или аудио: куски текста с временем начала. Хранится вне хранилища
// (Application Support); в заметки попадает, только когда человек нажал «сохранить как заметку».
public struct Transcript: Codable, Hashable, Sendable {
    public struct Segment: Codable, Hashable, Sendable {
        public let start: Double
        public let end: Double
        public let text: String
        // Кто говорит — номер спикера с нуля; nil — спикеров не определяли. В старых расшифровках поля нет.
        public var speaker: Int?
        public init(start: Double, end: Double, text: String, speaker: Int? = nil) {
            self.start = start
            self.end = end
            self.text = text
            self.speaker = speaker
        }
    }

    public var segments: [Segment]
    // Имена спикеров, которые дал человек: «0» → «Макар». Нет имени — «спикер 1».
    public var names: [Int: String] = [:]
    public init(segments: [Segment]) { self.segments = segments }

    // В расшифровках до 31.10.2026 поля names нет — читаем без него, иначе старые бы не открылись.
    enum CodingKeys: String, CodingKey { case segments, names }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        segments = try c.decode([Segment].self, forKey: .segments)
        names = try c.decodeIfPresent([Int: String].self, forKey: .names) ?? [:]
    }

    // Отрезок речи одного голоса — то, что отдаёт разметка дикторов.
    public struct Turn: Equatable, Sendable {
        public let start: Double, end: Double, speaker: Int
        public init(start: Double, end: Double, speaker: Int) { self.start = start; self.end = end; self.speaker = speaker }
    }

    // Каждой реплике — спикер, чей голос дольше всех звучит внутри неё. Номера перенумеровываем по порядку
    // появления: первый заговоривший — «спикер 1».
    public mutating func assign(_ turns: [Turn]) {
        var order: [Int: Int] = [:]
        for index in segments.indices {
            let s = segments[index]
            var best: (Int, Double)?
            for turn in turns {
                let overlap = min(s.end, turn.end) - max(s.start, turn.start)
                if overlap > 0, overlap > (best?.1 ?? 0) { best = (turn.speaker, overlap) }
            }
            // Без пересечения (тишина по краям) — ближайший по времени отрезок.
            let raw = best?.0 ?? turns.min { abs($0.start - s.start) < abs($1.start - s.start) }?.speaker
            segments[index].speaker = raw.map { raw in
                if let known = order[raw] { return known }
                order[raw] = order.count
                return order.count - 1
            }
        }
        names = [:]
    }

    public var speakers: [Int] { Array(Set(segments.compactMap(\.speaker))).sorted() }

    // Разметка ошиблась — человек сам говорит, чья реплика. Пустое имя возвращает «спикер N».
    public mutating func rename(_ speaker: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        names[speaker] = trimmed.isEmpty ? nil : trimmed
    }

    public mutating func mark(_ index: Int, as speaker: Int) {
        guard segments.indices.contains(index) else { return }
        segments[index].speaker = speaker
    }

    // Номер для «новый спикер»: следующий после самого большого.
    public var nextSpeaker: Int { (speakers.max() ?? -1) + 1 }

    public func name(_ speaker: Int) -> String { names[speaker] ?? "спикер \(speaker + 1)" }

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
    // Со спикерами — имя перед репликой, когда голос сменился: «**00:12 Макар:** текст».
    public func markdown(title: String) -> String {
        var previous: Int?
        let lines = segments.map { segment -> String in
            var label = Self.clock(segment.start)
            if let speaker = segment.speaker, speaker != previous { label += " \(name(speaker)):" }
            previous = segment.speaker ?? previous
            return "**\(label)** \(segment.text)"
        }
        return "# \(title)\n\n" + lines.joined(separator: "\n\n") + "\n"
    }
}
