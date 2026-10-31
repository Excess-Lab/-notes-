import AVFoundation
import Foundation

// Расшифровка файла видео или аудио: звук из файла → куски по 20 с → распознавание каждого.
// Отдельно от экрана, чтобы проверять тестом: в песочнице приложения чужой файл для проверки не открыть.
public enum MediaTranscription {
    public struct Piece: Equatable, Sendable {
        public let start: Double
        public let end: Double
        public let text: String
        // Номер голоса из разметки дикторов; nil — спикеров не определяли.
        public var speaker: Int? = nil
    }

    // Звук из файла — сразу 16 кГц моно (так ждёт модель), кусками по 20 с: длинную запись целиком
    // в память не берём, а у каждого куска есть время начала — оно и становится меткой в расшифровке.
    // С diarize запись берётся целиком (разметке голосов нужен весь звук, час — ~230 МБ) и режется не по 20 с,
    // а по репликам: кусок — один голос, поэтому смена спикера посреди куска не теряется.
    public static func transcribe(url: URL, engine: Transcriber, chunkSeconds: Int = 20,
                                  diarize: (@Sendable ([Float]) throws -> [SpeakerTurn])? = nil,
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
        var whole: [Float] = []
        while let ready = try await provider.next() {
            let floats: [Float] = ready.withUnsafeSampleBuffer { sample in
                guard let block = CMSampleBufferGetDataBuffer(sample) else { return [] }
                let length = CMBlockBufferGetDataLength(block)
                var floats = [Float](repeating: 0, count: length / 4)
                floats.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
                return floats
            }
            if diarize != nil { whole += floats; continue }
            buffer += floats
            while buffer.count >= chunk {
                try await flush(Array(buffer.prefix(chunk)))
                buffer.removeFirst(chunk)
            }
        }
        guard reader.status != .failed else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
        if let diarize {
            let turns = try diarize(whole)
            // Голоса не нашлись (музыка, тишина) — обычные куски по 20 с без спикеров.
            guard !turns.isEmpty else {
                for start in stride(from: 0, to: whole.count, by: chunk) where whole.count - start > Transcribers.sampleRate / 2 {
                    try await flush(Array(whole[start..<min(start + chunk, whole.count)]))
                }
                return segments
            }
            for window in windows(turns, longest: Double(chunkSeconds)) {
                let from = max(0, Int(window.start * Double(Transcribers.sampleRate)))
                let to = min(whole.count, Int(window.end * Double(Transcribers.sampleRate)))
                guard to - from > Transcribers.sampleRate / 4 else { continue }
                let text = try await engine.transcribe(Array(whole[from..<to])).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { segments.append(Piece(start: window.start, end: window.end, text: text, speaker: window.speaker)) }
                progress(duration > 0 ? min(window.end / duration, 1) : 0, duration)
            }
            return segments
        }
        if buffer.count > Transcribers.sampleRate / 2 { try await flush(buffer) }
        return segments
    }

    // Реплики → куски для распознавания: подряд идущие отрезки одного голоса с паузой меньше 1,5 с склеиваем
    // (модели нужен контекст), длинные режем на куски не длиннее longest.
    static func windows(_ turns: [SpeakerTurn], longest: Double) -> [SpeakerTurn] {
        var merged: [SpeakerTurn] = []
        for turn in turns.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, last.speaker == turn.speaker, turn.start - last.end < 1.5 {
                merged[merged.count - 1] = SpeakerTurn(start: last.start, end: max(last.end, turn.end), speaker: last.speaker)
            } else {
                merged.append(turn)
            }
        }
        return merged.flatMap { turn -> [SpeakerTurn] in
            let parts = max(1, Int((turn.end - turn.start) / longest) + ((turn.end - turn.start).truncatingRemainder(dividingBy: longest) > 0 ? 1 : 0))
            let step = (turn.end - turn.start) / Double(parts)
            return (0..<parts).map { SpeakerTurn(start: turn.start + Double($0) * step, end: turn.start + Double($0 + 1) * step, speaker: turn.speaker) }
        }
    }
}
