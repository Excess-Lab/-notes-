import Foundation
import SherpaOnnxC
import WhisperKit

// Распознаёт запись целиком: на входе семплы 16 кГц моно в Float (−1…1), на выходе текст.
public protocol Transcriber: Sendable {
    func transcribe(_ samples: [Float]) async throws -> String
}

public enum Transcribers {
    public static let sampleRate = 16_000

    // Куски не длиннее maxSeconds: режем в самой тихой десятой доли секунды между 70 % и 100 % длины
    // куска, чтобы не рвать слово. Обрезки короче 0,3 с отбрасываем — это тишина, а модель на них сбоит.
    public static func pieces(_ samples: [Float], maxSeconds: Double = 20) -> [Range<Int>] {
        let limit = Int(Double(sampleRate) * maxSeconds), window = sampleRate / 10, minimum = sampleRate * 3 / 10
        var result: [Range<Int>] = []
        var start = 0
        while start < samples.count {
            var end = samples.count
            if end - start > limit {
                var best = start + limit, quietest = Float.greatestFiniteMagnitude
                var at = start + limit * 7 / 10
                while at + window <= start + limit {
                    var energy: Float = 0
                    for i in at..<(at + window) { energy += samples[i] * samples[i] }
                    if energy < quietest { quietest = energy; best = at + window / 2 }
                    at += window / 2
                }
                end = best
            }
            if end - start >= minimum { result.append(start..<end) }
            start = end
        }
        return result
    }

    // Готовит распознаватель выбранной модели. Загрузка модели в память занимает секунды —
    // делаем один раз и держим, а не на каждую надиктовку.
    // language — для Whisper: код языка («ru», «en») или «auto» — определить по речи. nil — язык модели.
    public static func make(_ model: SpeechModel, language: String? = nil, store: ModelStore = .standard) async throws -> Transcriber {
        guard store.isInstalled(model) else { throw ModelError.notInstalled(model) }
        if model.whisperVariant != nil {
            return try await WhisperTranscriber(folder: store.folder(for: model), language: language ?? model.language)
        }
        return try GigaAMTranscriber(folder: store.folder(for: model))
    }
}

// GigaAM через C API sherpa-onnx. Распознаватель потокобезопасен для последовательных вызовов,
// параллельно не вызываем — этим заведует DictationController.
public final class GigaAMTranscriber: Transcriber, @unchecked Sendable {
    private let recognizer: OpaquePointer

    public init(folder: URL) throws {
        var config = SherpaOnnxOfflineRecognizerConfig()
        // C-строки живут до создания распознавателя: sherpa-onnx копирует пути к себе.
        var strings: [UnsafeMutablePointer<CChar>?] = []
        func c(_ value: String) -> UnsafePointer<CChar>? {
            let pointer = strdup(value)
            strings.append(pointer)
            return UnsafePointer(pointer)
        }
        defer { strings.forEach { free($0) } }

        config.feat_config.sample_rate = Int32(Transcribers.sampleRate)
        config.feat_config.feature_dim = 64   // GigaAM считает 64 мел-полосы
        config.model_config.transducer.encoder = c(folder.appendingPathComponent("encoder.int8.onnx").path)
        config.model_config.transducer.decoder = c(folder.appendingPathComponent("decoder.onnx").path)
        config.model_config.transducer.joiner = c(folder.appendingPathComponent("joiner.onnx").path)
        config.model_config.tokens = c(folder.appendingPathComponent("tokens.txt").path)
        config.model_config.model_type = c("nemo_transducer")
        config.model_config.provider = c("cpu")
        config.model_config.num_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount / 2)))
        config.decoding_method = c("greedy_search")

        guard let recognizer = SherpaOnnxCreateOfflineRecognizer(&config) else { throw ModelError.recognizerFailed }
        self.recognizer = recognizer
    }

    deinit { SherpaOnnxDestroyOfflineRecognizer(recognizer) }

    // Кодировщик GigaAM падает (исключение C++, его не поймать из Swift) на записи длиннее ~25 с —
    // режем на куски до 20 с по самым тихим местам и склеиваем текст.
    public func transcribe(_ samples: [Float]) async throws -> String {
        Transcribers.pieces(samples).map { decode(Array(samples[$0])) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func decode(_ samples: [Float]) -> String {
        guard !samples.isEmpty, let stream = SherpaOnnxCreateOfflineStream(recognizer) else { return "" }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        samples.withUnsafeBufferPointer { buffer in
            SherpaOnnxAcceptWaveformOffline(stream, Int32(Transcribers.sampleRate), buffer.baseAddress, Int32(buffer.count))
        }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { return "" }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        return result.pointee.text.map { String(cString: $0) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

public final class WhisperTranscriber: Transcriber, @unchecked Sendable {
    private let pipe: WhisperKit
    private let language: String

    public init(folder: URL, language: String) async throws {
        pipe = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, verbose: false, load: true, download: false))
        self.language = language
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        // «auto» — Whisper сам слушает, на каком языке говорят (можно мешать русский и английский по фразам).
        let options = language == "auto" ? DecodingOptions(language: nil, detectLanguage: true)
                                         : DecodingOptions(language: language, detectLanguage: false)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
