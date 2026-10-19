import Foundation
import Testing
@testable import NotesCore

// Два Мака и общий «GitHub»: bare-репозиторий во временной папке. Протокол тот же, сеть не нужна.
private struct TwoMacs {
    let server: URL
    let a: URL
    let b: URL

    init(note: String = "общий текст") throws {
        func temp(_ name: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-pull-\(name)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        server = try temp("server")
        a = try temp("a")
        b = FileManager.default.temporaryDirectory.appendingPathComponent("notes-pull-b-\(UUID().uuidString)")
        _ = try GitVault.prepareBare(at: server)

        try write(note, "план.md", on: a)
        let (vaultA, _) = try GitVault.prepare(at: a)
        try vaultA.setRemote(server.path)
        try vaultA.push(token: nil)
        _ = try GitVault.clone(from: server.path, to: b, token: nil)
    }

    func write(_ text: String, _ name: String, on mac: URL) throws {
        try text.write(to: mac.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func read(_ name: String, on mac: URL) throws -> String {
        try String(contentsOf: mac.appendingPathComponent(name), encoding: .utf8)
    }

    func exists(_ name: String, on mac: URL) -> Bool {
        FileManager.default.fileExists(atPath: mac.appendingPathComponent(name).path)
    }

    // Мак коммитит своё и отправляет на «GitHub».
    func send(from mac: URL) async throws {
        let engine = SyncEngine(folder: mac)
        _ = try await engine.pull(token: nil)
        _ = try await engine.pushIfDue(token: nil, lastPush: nil)
    }
}

// Полдень по местному времени: имя копии берёт дату в часовом поясе Мака, и ровная секунда
// от 1970 года могла оказаться вчерашним днём.
private let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))!

@Suite("забрать правки с другого мака")
struct PullTests {
    @Test("второй мак забирает хранилище целиком")
    func clonesVault() throws {
        let macs = try TwoMacs()

        #expect(try macs.read("план.md", on: macs.b) == "общий текст")
        // Автор коммитов на втором Маке — тоже локальный, а не из глобального git пользователя.
        #expect(try GitVault.open(at: macs.b).commitCount == 1)
    }

    @Test("здесь ничего не меняли — просто догоняем сервер")
    func fastForwards() async throws {
        let macs = try TwoMacs()
        try macs.write("правка с мака a", "план.md", on: macs.a)
        try await macs.send(from: macs.a)

        #expect(try await SyncEngine(folder: macs.b).pull(token: nil) == .fastForwarded)
        #expect(try macs.read("план.md", on: macs.b) == "правка с мака a")
    }

    @Test("правили разные заметки — сливаем без конфликтов, обе правки на месте")
    func mergesDifferentNotes() async throws {
        let macs = try TwoMacs()
        try macs.write("идеи с мака a", "идеи.md", on: macs.a)
        try await macs.send(from: macs.a)
        try macs.write("план с мака b", "план.md", on: macs.b)

        #expect(try await SyncEngine(folder: macs.b).pull(token: nil) == .merged(conflicts: []))
        #expect(try macs.read("идеи.md", on: macs.b) == "идеи с мака a")
        #expect(try macs.read("план.md", on: macs.b) == "план с мака b")
        // После слияния мак b может отправить — сервер принимает, ничего не отклонено.
        try await macs.send(from: macs.b)
    }

    @Test("одну заметку поменяли на обоих — ни одна версия не теряется")
    func keepsBothVersionsOnConflict() async throws {
        let macs = try TwoMacs()
        try macs.write("версия a", "план.md", on: macs.a)
        try await macs.send(from: macs.a)
        try macs.write("версия b", "план.md", on: macs.b)

        #expect(try await SyncEngine(folder: macs.b).pull(token: nil, date: day) == .merged(conflicts: ["план.md"]))
        // Свой текст остаётся в заметке, чужой — рядом копией. Без маркеров <<<<<<< внутри текста.
        #expect(try macs.read("план.md", on: macs.b) == "версия b")
        #expect(try macs.read("план (конфликт 2026-10-19).md", on: macs.b) == "версия a")
        #expect(try GitVault.open(at: macs.b).changes().isEmpty)
    }

    @Test("там удалили, здесь правили — правка остаётся")
    func editBeatsDelete() async throws {
        let macs = try TwoMacs()
        try FileManager.default.removeItem(at: macs.a.appendingPathComponent("план.md"))
        try await macs.send(from: macs.a)
        try macs.write("важная правка", "план.md", on: macs.b)

        _ = try await SyncEngine(folder: macs.b).pull(token: nil)

        #expect(try macs.read("план.md", on: macs.b) == "важная правка")
    }

    @Test("здесь удалили, там правили — их правка возвращается")
    func theirEditBeatsOurDelete() async throws {
        let macs = try TwoMacs()
        try macs.write("правка с мака a", "план.md", on: macs.a)
        try await macs.send(from: macs.a)
        try FileManager.default.removeItem(at: macs.b.appendingPathComponent("план.md"))

        _ = try await SyncEngine(folder: macs.b).pull(token: nil)

        #expect(try macs.read("план.md", on: macs.b) == "правка с мака a")
    }

    @Test("незакоммиченная правка не теряется при pull")
    func commitsBeforePull() async throws {
        let macs = try TwoMacs()
        try macs.write("новая с мака a", "a.md", on: macs.a)
        try await macs.send(from: macs.a)
        // На маке b правка лежит только на диске, коммита ещё не было (до часового цикла).
        try macs.write("несохранённое в git", "b.md", on: macs.b)

        _ = try await SyncEngine(folder: macs.b).pull(token: nil)

        #expect(try macs.read("b.md", on: macs.b) == "несохранённое в git")
        #expect(macs.exists("a.md", on: macs.b))
    }

    @Test("повторный конфликт в тот же день — вторая копия не затирает первую")
    func numbersConflictCopies() async throws {
        let macs = try TwoMacs()
        for round in 1...2 {
            try macs.write("a\(round)", "план.md", on: macs.a)
            try await macs.send(from: macs.a)
            try macs.write("b\(round)", "план.md", on: macs.b)
            _ = try await SyncEngine(folder: macs.b).pull(token: nil, date: day)
            try await macs.send(from: macs.b)
            _ = try await SyncEngine(folder: macs.a).pull(token: nil, date: day)
        }

        #expect(try macs.read("план (конфликт 2026-10-19).md", on: macs.b) == "a1")
        #expect(try macs.read("план (конфликт 2026-10-19 2).md", on: macs.b) == "a2")
    }
}

@Suite("второй мак входит в github, где notes уже есть")
struct SecondMacTests {
    @Test("своя новая папка и чужая история сливаются, потом push проходит")
    func mergesUnrelatedHistories() async throws {
        let macs = try TwoMacs()
        let fresh = FileManager.default.temporaryDirectory.appendingPathComponent("notes-pull-c-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        try "заметка с нового мака".write(to: fresh.appendingPathComponent("новое.md"), atomically: true, encoding: .utf8)
        let (vault, _) = try GitVault.prepare(at: fresh)
        try vault.setRemote(macs.server.path)

        // Так делает вход в GitHub: сначала забрать и слить, потом отправить.
        // Без pull сервер отклонил бы push: у него своя история, у нового Мака — своя.
        _ = try await SyncEngine(folder: fresh).pull(token: nil)
        try vault.push(token: nil)

        #expect(try String(contentsOf: fresh.appendingPathComponent("план.md"), encoding: .utf8) == "общий текст")
        #expect(try String(contentsOf: fresh.appendingPathComponent("новое.md"), encoding: .utf8) == "заметка с нового мака")
        // Одинаковый .gitignore с обеих сторон — не конфликт, копии не появляется.
        let files = try FileManager.default.contentsOfDirectory(atPath: fresh.path)
        #expect(!files.contains { $0.contains("конфликт") })
    }
}
