import Foundation
import SherpaOnnxC

// Кто говорит в расшифровке (ТЗ 31.10.2026: «спикеры, конечно, делаем»). Две модели с релизов
// k2-fsa/sherpa-onnx, ~35 МБ вместе, качаются по кнопке: pyannote режет запись на куски по голосам,
// CAM++ (китайский и английский, но голоса различает на любом языке) даёт «отпечаток» голоса,
// кластеризация собирает куски одного человека. Контрольные суммы проверяем, как у GigaAM.

// Отрезок речи одного голоса; приложение переводит его в Transcript.Turn.
public struct SpeakerTurn: Equatable, Sendable {
    public let start: Double, end: Double, speaker: Int
    public init(start: Double, end: Double, speaker: Int) { self.start = start; self.end = end; self.speaker = speaker }
}

public enum Diarization {
    static let segmentationURL = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2")!
    static let segmentationSHA = "24615ee884c897d9d2ba09bb4d30da6bb1b15e685065962db5b02e76e4996488"
    static let segmentationFolder = "sherpa-onnx-pyannote-segmentation-3-0"
    static let embeddingURL = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx")!
    static let embeddingSHA = "aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2"
    public static let downloadMB = 35

    static func folder(_ store: ModelStore) -> URL { store.root.appendingPathComponent("speakers", isDirectory: true) }
    static func segmentation(_ store: ModelStore) -> URL { folder(store).appendingPathComponent("segmentation.onnx") }
    static func embedding(_ store: ModelStore) -> URL { folder(store).appendingPathComponent("embedding.onnx") }

    public static func isInstalled(_ store: ModelStore = .standard) -> Bool {
        FileManager.default.fileExists(atPath: segmentation(store).path) && FileManager.default.fileExists(atPath: embedding(store).path)
    }

    public static func remove(_ store: ModelStore = .standard) throws {
        if FileManager.default.fileExists(atPath: folder(store).path) { try FileManager.default.removeItem(at: folder(store)) }
    }

    // Качает обе модели; progress — доля от 0 до 1 (сегментация — первые 20 %).
    public static func download(_ store: ModelStore = .standard, progress: @escaping @Sendable (Double) -> Void) async throws {
        if isInstalled(store) { progress(1); return }
        let target = folder(store)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let (archive, _) = try await URLSession.shared.download(from: segmentationURL, delegate: ProgressDelegate { progress($0 * 0.2) })
        defer { try? FileManager.default.removeItem(at: archive) }
        guard try ModelStore.sha256(of: archive) == segmentationSHA else { throw ModelError.checksumMismatch }
        let unpack = store.root.appendingPathComponent(".unpack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: unpack, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unpack) }
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["xjf", archive.path, "-C", unpack.path]
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else { throw ModelError.extractFailed(tar.terminationStatus) }

        let (model, _) = try await URLSession.shared.download(from: embeddingURL, delegate: ProgressDelegate { progress(0.2 + $0 * 0.8) })
        defer { try? FileManager.default.removeItem(at: model) }
        guard try ModelStore.sha256(of: model) == embeddingSHA else { throw ModelError.checksumMismatch }

        // Отпечаток голоса — последним: пока его нет, модели не считаются установленными.
        try? FileManager.default.removeItem(at: segmentation(store))
        try FileManager.default.moveItem(at: unpack.appendingPathComponent(segmentationFolder).appendingPathComponent("model.onnx"),
                                         to: segmentation(store))
        try? FileManager.default.removeItem(at: embedding(store))
        try FileManager.default.moveItem(at: model, to: embedding(store))
        progress(1)
    }

    // Разметка записи 16 кГц: отрезки «кто когда говорит». speakers — сколько людей, если известно (0 — само).
    public static func turns(_ samples: [Float], speakers: Int = 0, store: ModelStore = .standard) throws -> [SpeakerTurn] {
        guard isInstalled(store) else { throw ModelError.recognizerFailed }
        var config = SherpaOnnxOfflineSpeakerDiarizationConfig()
        var strings: [UnsafeMutablePointer<CChar>?] = []
        func c(_ value: String) -> UnsafePointer<CChar>? {
            let pointer = strdup(value)
            strings.append(pointer)
            return UnsafePointer(pointer)
        }
        defer { strings.forEach { free($0) } }
        let threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount / 2)))
        config.segmentation.pyannote.model = c(segmentation(store).path)
        config.segmentation.num_threads = threads
        config.segmentation.provider = c("cpu")
        config.embedding.model = c(embedding(store).path)
        config.embedding.num_threads = threads
        config.embedding.provider = c("cpu")
        config.clustering.num_clusters = Int32(speakers)
        // Порог расстояния между голосами: меньше — дробит одного человека, больше — сливает разных.
        config.clustering.threshold = 0.5
        config.min_duration_on = 0.3
        config.min_duration_off = 0.5

        guard let sd = SherpaOnnxCreateOfflineSpeakerDiarization(&config) else { throw ModelError.recognizerFailed }
        defer { SherpaOnnxDestroyOfflineSpeakerDiarization(sd) }
        guard let result = samples.withUnsafeBufferPointer({
            SherpaOnnxOfflineSpeakerDiarizationProcess(sd, $0.baseAddress, Int32($0.count))
        }) else { return [] }
        defer { SherpaOnnxOfflineSpeakerDiarizationDestroyResult(result) }
        let count = Int(SherpaOnnxOfflineSpeakerDiarizationResultGetNumSegments(result))
        guard count > 0, let list = SherpaOnnxOfflineSpeakerDiarizationResultSortByStartTime(result) else { return [] }
        defer { SherpaOnnxOfflineSpeakerDiarizationDestroySegment(list) }
        return (0..<count).map { SpeakerTurn(start: Double(list[$0].start), end: Double(list[$0].end), speaker: Int(list[$0].speaker)) }
    }
}
