import Foundation
import Testing
@testable import NotesCore

@Suite("поиск по сущностям")
struct SearchQueryTests {
    @Test("все слова, без регистра и ё/е, в любом из полей")
    func matches() {
        let query = SearchQuery("Ёж  созвон")
        #expect(query.words == ["еж", "созвон"])
        #expect(query.matches("Созвон про ежа"))
        #expect(query.matches("Созвон", "у ёжика"))
        #expect(!query.matches("Созвон"))
        #expect(!SearchQuery("  ").matches("что угодно"))
    }

    @Test("упоминание в расшифровке — кусок с первым словом и его время")
    func mention() {
        let transcript = Transcript(segments: [
            .init(start: 0, end: 5, text: "Привет всем."),
            .init(start: 65, end: 70, text: "Обсудим бюджет на ноябрь."),
            .init(start: 90, end: 95, text: "Бюджет утвердим завтра."),
        ])
        #expect(transcript.mention(of: SearchQuery("бюджет"))?.start == 65)
        #expect(transcript.mention(of: SearchQuery("бюджет завтра"))?.start == 65)
        #expect(transcript.mention(of: SearchQuery("отпуск")) == nil)
    }
}
