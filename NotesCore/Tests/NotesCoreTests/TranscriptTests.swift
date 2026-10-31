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
    @Test("краткое содержание — перед расшифровкой")
    func summary() {
        var t = Transcript(segments: [.init(start: 0, end: 5, text: "текст")])
        t.summary = "- решили"
        #expect(t.markdown(title: "т") == "# т\n\n## Кратко\n\n- решили\n\n## Расшифровка\n\n**00:00** текст\n")
    }

    @Test("имя спикера и переотметка реплики")
    func renameAndMark() {
        var t = Transcript(segments: [.init(start: 0, end: 5, text: "а", speaker: 0), .init(start: 5, end: 9, text: "б", speaker: 0)])
        t.rename(0, to: "  Макар ")
        t.mark(1, as: t.nextSpeaker)
        #expect(t.name(0) == "Макар")
        #expect(t.speakers == [0, 1])
        #expect(t.markdown(title: "в").contains("**00:05 спикер 2:** б"))
        t.rename(0, to: "")
        #expect(t.name(0) == "спикер 1")
    }

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

    // Разметка дикторов отдаёт номера как попало (7, 3) — в расшифровке первый заговоривший — спикер 1.
    @Test("спикеры: по наибольшему пересечению, номера по порядку появления, имя — в заметке при смене голоса")
    func speakers() {
        var t = Transcript(segments: [
            .init(start: 0, end: 4, text: "Привет."),
            .init(start: 4, end: 9, text: "Здравствуй."),
            .init(start: 9, end: 12, text: "Как дела?"),
            .init(start: 30, end: 31, text: "Пока."),
        ])
        t.assign([.init(start: 0, end: 4.5, speaker: 7), .init(start: 4.5, end: 9, speaker: 3), .init(start: 9, end: 12, speaker: 7)])
        #expect(t.segments.map(\.speaker) == [0, 1, 0, 0])
        #expect(t.speakers == [0, 1])
        t.names[0] = "Макар"
        #expect(t.markdown(title: "x") == "# x\n\n**00:00 Макар:** Привет.\n\n**00:04 спикер 2:** Здравствуй.\n\n**00:09 Макар:** Как дела?\n\n**00:30** Пока.\n")
    }

    @Test("старая расшифровка без спикеров читается")
    func oldTranscript() throws {
        let json = #"{"segments":[{"start":0,"end":1,"text":"а"}]}"#
        let t = try JSONDecoder().decode(Transcript.self, from: Data(json.utf8))
        #expect(t.segments.first?.speaker == nil && t.names.isEmpty)
    }
}
