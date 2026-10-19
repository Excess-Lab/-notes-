import Foundation
import Testing
@testable import NotesCore

@Suite("пинкод")
struct PinCodeTests {
    private func typed(_ text: String, into entry: inout PinEntry) {
        for character in text { entry.type(character) }
    }

    @Test("придумал и повторил — пинкод готов")
    func createAndConfirm() {
        var entry = PinEntry()
        typed("1234", into: &entry)
        #expect(entry.stage == .confirm)
        #expect(entry.digits.isEmpty)
        typed("1234", into: &entry)
        #expect(entry.stage == .done)
        #expect(entry.pin == "1234")
    }

    // Иначе опечатка при повторе молча сохранила бы не тот пинкод, и войти было бы нельзя.
    @Test("повтор не совпал — начинаем заново, пинкода нет")
    func mismatchStartsOver() {
        var entry = PinEntry()
        typed("1234", into: &entry)
        typed("1243", into: &entry)
        #expect(entry.stage == .mismatch)
        #expect(entry.pin == nil)
        entry.type("5")
        #expect(entry.stage == .create)
        #expect(entry.digits == [5])
        typed("555", into: &entry)
        typed("5555", into: &entry)
        #expect(entry.pin == "5555")
    }

    @Test("принимаем только цифры, стирание убирает последнюю")
    func onlyDigits() {
        var entry = PinEntry()
        typed("a1 ٣2", into: &entry)
        #expect(entry.digits == [1, 2])
        entry.deleteBackward()
        #expect(entry.digits == [1])
    }

    @Test("хеш проверяет свой пинкод и не принимает чужой")
    func hashMatches() {
        let hash = PinHash(pin: "0420")
        #expect(hash.matches("0420"))
        #expect(!hash.matches("0421"))
        #expect(PinHash(encoded: hash.encoded) == hash)
    }

    // Без соли одинаковые пинкоды давали бы одинаковый хеш — его можно было бы узнать по таблице.
    @Test("одинаковый пинкод с разной солью — разный хеш")
    func saltedHash() {
        #expect(PinHash(pin: "1111").hash != PinHash(pin: "1111").hash)
    }
}
