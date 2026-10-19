import Foundation
import Testing
@testable import NotesSpeech

// Папка с распакованной GigaAM. Модель весит ~230 МБ, в репозиторий её не кладём:
// тест распознавания запускается, только если путь задан —
// NOTES_GIGAAM_DIR=/путь/к/sherpa-onnx-nemo-transducer-punct-giga-am-v3-russian-2025-12-16 swift test
private let gigaAMFolder = ProcessInfo.processInfo.environment["NOTES_GIGAAM_DIR"].map { URL(fileURLWithPath: $0) }

// WAV 16 кГц, 16 бит, моно → Float −1…1. Заголовок пропускаем по поиску блока «data».
private func readWav(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    guard let range = data.range(of: Data("data".utf8)) else { return [] }
    let start = range.upperBound + 4
    return data[start...].withUnsafeBytes { raw in
        raw.bindMemory(to: Int16.self).map { Float($0) / 32768 }
    }
}

@Suite("распознавание речи")
struct SpeechTests {
    @Test("gigaam распознаёт русскую речь с пунктуацией", .enabled(if: gigaAMFolder != nil))
    func gigaAMRecognizesRussian() async throws {
        let folder = try #require(gigaAMFolder)
        let samples = try readWav(folder.appendingPathComponent("test_wavs/example.wav"))

        let text = try await GigaAMTranscriber(folder: folder).transcribe(samples)

        print("GigaAM:", text)
        #expect(text.count > 20)
        // Модель с пунктуацией: в 11 секундах речи должна быть хотя бы одна запятая или точка.
        #expect(text.contains(where: { ",.?!".contains($0) }))
        // Только кириллица и знаки — значит, распознал русский, а не мусор.
        #expect(text.range(of: "[а-яё]", options: [.regularExpression, .caseInsensitive]) != nil)
    }

    @Test("тишина — пустой текст, а не выдумка", .enabled(if: gigaAMFolder != nil))
    func silenceGivesNothing() async throws {
        let folder = try #require(gigaAMFolder)
        let text = try await GigaAMTranscriber(folder: folder).transcribe([Float](repeating: 0, count: 16_000))
        #expect(text.isEmpty)
    }

    @Test("модель считается скачанной только после распаковки целиком")
    func installedMarker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID().uuidString)")
        let store = ModelStore(root: root)
        #expect(!store.isInstalled(.gigaAM))

        // Пустая папка (недокачанная модель) — ещё не установлена.
        try FileManager.default.createDirectory(at: store.folder(for: .gigaAM), withIntermediateDirectories: true)
        #expect(!store.isInstalled(.gigaAM))

        try Data().write(to: store.folder(for: .gigaAM).appendingPathComponent("tokens.txt"))
        #expect(store.isInstalled(.gigaAM))
        try store.remove(.gigaAM)
        #expect(!store.isInstalled(.gigaAM))
    }

    @Test("контрольная сумма считается по файлу целиком")
    func checksum() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sha-\(UUID().uuidString)")
        try Data("notes".utf8).write(to: file)
        // Эталон посчитан `printf notes | shasum -a 256`.
        #expect(try ModelStore.sha256(of: file) == "ab5aa97074c454a0632057e704220d9a6678fbf773a0a5806fc09b8173b07309")
    }

    @Test("у whisper правильные варианты из репозитория whisperkit-coreml")
    func whisperVariants() {
        #expect(SpeechModel.whisperSmall.whisperVariant == "openai_whisper-small")
        #expect(SpeechModel.whisperLargeTurbo.whisperVariant == "openai_whisper-large-v3-v20240930_turbo")
        #expect(SpeechModel.gigaAM.whisperVariant == nil)
    }
}

// Whisper small весит 464 МБ: тест качает его по-настоящему, поэтому включается отдельно —
// NOTES_WHISPER_TEST=1 NOTES_GIGAAM_DIR=… swift test --filter whisper
@Suite("whisper")
struct WhisperTests {
    @Test("whisper скачивается и распознаёт русский",
          .enabled(if: ProcessInfo.processInfo.environment["NOTES_WHISPER_TEST"] == "1" && gigaAMFolder != nil))
    func whisperRecognizesRussian() async throws {
        let store = ModelStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("notes-whisper-models"))
        try await store.download(.whisperSmall) { _ in }
        #expect(store.isInstalled(.whisperSmall))

        let samples = try readWav(try #require(gigaAMFolder).appendingPathComponent("test_wavs/example.wav"))
        let text = try await Transcribers.make(.whisperSmall, store: store).transcribe(samples)

        print("Whisper:", text)
        #expect(text.range(of: "[а-яё]", options: [.regularExpression, .caseInsensitive]) != nil)
    }
}
