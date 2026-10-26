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
}
