import AVFoundation
import Foundation

// Расшифровка файла видео или аудио: звук из файла → куски по 20 с → распознавание каждого.
// Отдельно от экрана, чтобы проверять тестом: в песочнице приложения чужой файл для проверки не открыть.
public enum MediaTranscription {
    public struct Piece: Equatable, Sendable {
        public let start: Double
        public let end: Double
        public let text: String
    }

    // Звук из файла — сразу 16 кГц моно (так ждёт модель), кусками по 20 с: длинную запись целиком
    // в память не берём, а у каждого куска есть время начала — оно и становится меткой в расшифровке.
    public static func transcribe(url: URL, engine: Transcriber, chunkSeconds: Int = 20,
                                  progress: @escaping @Sendable (Double, Double) -> Void) async throws -> [Piece] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw CocoaError(.fileReadCorruptFile) }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Transcribers.sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        ])
        // macOS 27: вместо add / startReading — поставщик кусков звука и start().
        let provider = reader.outputProvider(for: output)
        try reader.start()

        let chunk = Transcribers.sampleRate * chunkSeconds
        var buffer: [Float] = []
        var segments: [Piece] = []
        var position = 0.0
        func flush(_ samples: [Float]) async throws {
            let length = Double(samples.count) / Double(Transcribers.sampleRate)
            let text = try await engine.transcribe(samples).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { segments.append(Piece(start: position, end: position + length, text: text)) }
            position += length
            progress(duration > 0 ? min(position / duration, 1) : 0, duration)
        }
        while let ready = try await provider.next() {
            let floats: [Float] = ready.withUnsafeSampleBuffer { sample in
                guard let block = CMSampleBufferGetDataBuffer(sample) else { return [] }
                let length = CMBlockBufferGetDataLength(block)
                var floats = [Float](repeating: 0, count: length / 4)
                floats.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
                return floats
            }
            buffer += floats
            while buffer.count >= chunk {
                try await flush(Array(buffer.prefix(chunk)))
                buffer.removeFirst(chunk)
            }
        }
        if buffer.count > Transcribers.sampleRate / 2 { try await flush(buffer) }
        guard reader.status != .failed else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
        return segments
    }
}
