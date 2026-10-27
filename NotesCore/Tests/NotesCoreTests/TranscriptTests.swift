import Foundation
import Testing
@testable import NotesCore

@Suite("расшифровка")
struct TranscriptTests {
    let transcript = Transcript(segments: [
        .init(start: 0, end: 12.5, text: "Так, всех слышно?"),
        .init(start: 3725, end: 3731, text: "Окей, до встречи."),
    ])

    // Иначе плееры не узнают субтитры: у .srt строгий формат времени с запятой и миллисекундами.
    @Test("srt: номер, время с миллисекундами через запятую, пустая строка между")
    func srt() {
        #expect(transcript.srt == "1\n00:00:00,000 --> 00:00:12,500\nТак, всех слышно?\n\n2\n01:02:05,000 --> 01:02:11,000\nОкей, до встречи.\n")
    }

    @Test("заметка из расшифровки и метки времени")
    func markdown() {
        #expect(transcript.markdown(title: "Созвон") == "# Созвон\n\n**00:00** Так, всех слышно?\n\n**1:02:05** Окей, до встречи.\n")
        #expect(Transcript.clock(751) == "12:31")
        #expect(transcript.wordCount == 6)
    }

    // Иначе по заметке не понять, откуда расшифровка и когда её сделали.
    @Test("заметка расшифровки с метаданными во frontmatter")
    func noteWithMeta() {
        let added = Date(timeIntervalSince1970: 0)
        let text = transcript.note(title: "Созвон", source: "созвон.mp4", added: added, duration: 3731, model: "GigaAM v3")
        #expect(text.hasPrefix("---\nисточник: созвон.mp4\nзагружено: "))
        #expect(text.contains("длительность: 1:02:11\nмодель: GigaAM v3\nслов: 6\n---\n\n# Созвон"))
    }
}
