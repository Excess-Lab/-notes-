import AVFoundation
import Foundation
import Testing
@testable import NotesSpeech

// Вместо модели — заглушка: проверяем чтение звука из файла и нарезку, а не качество распознавания
// (его проверяют тесты с настоящими моделями в SpeechTests).
private final class CountingTranscriber: Transcriber, @unchecked Sendable {
    var lengths: [Int] = []
    func transcribe(_ samples: [Float]) async throws -> String {
        lengths.append(samples.count)
        return "кусок \(lengths.count)"
    }
}

@Suite("расшифровка файла")
struct MediaTranscriptionTests {
    // 45 секунд тона в AAC (.m4a) — как обычная запись с диктофона.
    private func makeAudio(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("media-\(UUID()).m4a")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                                AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2])
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 {
            for i in 0..<Int(frames) { buffer.floatChannelData![channel][i] = sin(Float(i) * 0.05) * 0.3 }
        }
        try file.write(from: buffer)
        return url
    }

    // Иначе длинная запись шла бы в модель одним куском, а метки времени в расшифровке были бы неверны.
    @Test("звук из файла: 16 кГц моно, куски по 20 с, время начала у каждого")
    func chunks() async throws {
        let url = try makeAudio(seconds: 45)
        let engine = CountingTranscriber()
        let pieces = try await MediaTranscription.transcribe(url: url, engine: engine) { _, _ in }
        #expect(pieces.map(\.start) == [0, 20, 40])
        #expect(pieces.map(\.text) == ["кусок 1", "кусок 2", "кусок 3"])
        #expect(engine.lengths.prefix(2).allSatisfy { $0 == 16_000 * 20 })
        // Последний кусок — остаток около 5 с (AAC добавляет немного тишины по краям).
        #expect(abs(Double(engine.lengths[2]) / 16_000 - 5) < 0.5)
    }

    // Смена голоса посреди 20-секундного куска иначе терялась бы: кусок — один спикер.
    @Test("со спикерами запись режется по репликам, у каждого куска свой голос")
    func diarized() async throws {
        let url = try makeAudio(seconds: 30)
        let engine = CountingTranscriber()
        let turns = [SpeakerTurn(start: 0.5, end: 4, speaker: 3), SpeakerTurn(start: 4.8, end: 9, speaker: 3),
                     SpeakerTurn(start: 9.5, end: 30, speaker: 1)]
        let pieces = try await MediaTranscription.transcribe(url: url, engine: engine, diarize: { _ in turns }) { _, _ in }
        // Две реплики спикера 3 с паузой 0,8 с склеились; 20,5 с спикера 1 — два куска по ~10 с.
        #expect(pieces.map(\.speaker) == [3, 1, 1])
        #expect(pieces.map(\.start) == [0.5, 9.5, 19.75])
        #expect(abs(Double(engine.lengths[0]) / 16_000 - 8.5) < 0.01)
    }

    @Test("голосов не нашлось — обычные куски без спикеров")
    func noVoices() async throws {
        let url = try makeAudio(seconds: 25)
        let pieces = try await MediaTranscription.transcribe(url: url, engine: CountingTranscriber(), diarize: { _ in [] }) { _, _ in }
        #expect(pieces.map(\.start) == [0, 20])
        #expect(pieces.allSatisfy { $0.speaker == nil })
    }
}

// Настоящая разметка: два голоса macOS по очереди (Milena и Daniel есть в любой системе). Модели (~35 МБ) — из папки в DIARIZATION_MODELS
// (segmentation.onnx и embedding.onnx); без неё тест пропускается, как тесты с моделями речи.
private let diarizationFolder = ProcessInfo.processInfo.environment["DIARIZATION_MODELS"].map { URL(fileURLWithPath: $0) }

@Suite("спикеры")
struct DiarizationTests {
    @Test("два голоса различаются", .enabled(if: diarizationFolder != nil))
    func twoVoices() async throws {
        let store = ModelStore(root: diarizationFolder!)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voices-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = [("Milena", "Привет, это первая реплика разговора, я говорю довольно долго, чтобы голос узнали."),
                     ("Daniel", "А это уже второй человек, у него совсем другой голос и другая манера речи."),
                     ("Milena", "И снова первый голос, который возвращается в разговор после паузы.")]
        var samples: [Float] = []
        for (index, (voice, text)) in lines.enumerated() {
            let file = dir.appendingPathComponent("\(index).wav")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", voice, "-o", file.path, "--data-format=LEF32@16000", text]
            try say.run()
            say.waitUntilExit()
            let audio = try AVAudioFile(forReading: file)
            let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length))!
            try audio.read(into: buffer)
            samples += Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            samples += [Float](repeating: 0, count: 16_000)
        }
        let turns = try Diarization.turns(samples, store: store)
        #expect(Set(turns.map(\.speaker)).count == 2)
        #expect(turns.first?.speaker == turns.last?.speaker)
    }
}
