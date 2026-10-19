import CryptoKit
import Foundation
import WhisperKit

// Модели распознавания, из которых выбирают на шаге «модели». В сборку они не входят: качаются один раз
// в Application Support приложения (CLAUDE.md, «лёгкая сборка»).
public enum SpeechModel: String, CaseIterable, Sendable {
    case gigaAM = "gigaam-v3-punct"
    case whisperSmall = "whisper-small"
    case whisperLargeTurbo = "whisper-large-v3-turbo"

    // Сколько качать, в мегабайтах — показываем на экране.
    public var downloadMB: Int {
        switch self {
        case .gigaAM: 176
        case .whisperSmall: 464
        case .whisperLargeTurbo: 1563
        }
    }

    // GigaAM знает только русский; Whisper — 99 языков, ему подсказываем русский по умолчанию.
    public var language: String { "ru" }

    // Вариант модели в репозитории argmaxinc/whisperkit-coreml на Hugging Face.
    var whisperVariant: String? {
        switch self {
        case .gigaAM: nil
        case .whisperSmall: "openai_whisper-small"
        case .whisperLargeTurbo: "openai_whisper-large-v3-v20240930_turbo"
        }
    }
}

// GigaAM v3 с пунктуацией, сконвертированная для sherpa-onnx. Архив с релиза k2-fsa/sherpa-onnx;
// контрольную сумму проверяем, чтобы подменённый файл не запустился.
enum GigaAMArchive {
    static let url = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-transducer-punct-giga-am-v3-russian-2025-12-16.tar.bz2")!
    static let sha256 = "f9620a0099019c6afcee26525ef9ed3297fa50dd5691c1902af0c948fc1a470b"
    static let folderName = "sherpa-onnx-nemo-transducer-punct-giga-am-v3-russian-2025-12-16"
}

public enum ModelError: Error, Equatable {
    case checksumMismatch
    case extractFailed(Int32)
    case notInstalled(SpeechModel)
    case recognizerFailed
}

// Где лежат скачанные модели и как их скачать.
public struct ModelStore: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    // В песочнице это папка внутри контейнера приложения, а не общая ~/Library.
    public static var standard: ModelStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ModelStore(root: base.appendingPathComponent("models", isDirectory: true))
    }

    public func folder(for model: SpeechModel) -> URL {
        root.appendingPathComponent(model.rawValue, isDirectory: true)
    }

    public func isInstalled(_ model: SpeechModel) -> Bool {
        let folder = folder(for: model)
        let marker = model.whisperVariant == nil ? "tokens.txt" : "AudioEncoder.mlmodelc"
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(marker).path)
    }

    public func remove(_ model: SpeechModel) throws {
        let folder = folder(for: model)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    // Качает модель; progress — доля от 0 до 1. Уже скачанную не качает второй раз.
    public func download(_ model: SpeechModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        if isInstalled(model) { progress(1); return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let variant = model.whisperVariant {
            try await downloadWhisper(model, variant: variant, progress: progress)
        } else {
            try await downloadGigaAM(progress: progress)
        }
        progress(1)
    }

    private func downloadWhisper(_ model: SpeechModel, variant: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        let staging = root.appendingPathComponent(".whisperkit", isDirectory: true)
        let downloaded = try await WhisperKit.download(variant: variant, downloadBase: staging) { value in
            progress(value.fractionCompleted)
        }
        try? FileManager.default.removeItem(at: folder(for: model))
        try FileManager.default.moveItem(at: downloaded, to: folder(for: model))
    }

    private func downloadGigaAM(progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = ProgressDelegate(progress)
        let (archive, _) = try await URLSession.shared.download(from: GigaAMArchive.url, delegate: delegate)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard try Self.sha256(of: archive) == GigaAMArchive.sha256 else { throw ModelError.checksumMismatch }

        // Распаковываем во временную папку рядом и только потом переносим: недокачанная или
        // недораспакованная модель не должна выглядеть установленной.
        let unpack = root.appendingPathComponent(".unpack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: unpack, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unpack) }
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["xjf", archive.path, "-C", unpack.path]
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else { throw ModelError.extractFailed(tar.terminationStatus) }

        let target = folder(for: .gigaAM)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: unpack.appendingPathComponent(GigaAMArchive.folderName), to: target)
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// Прогресс скачивания одного файла: URLSession сообщает его через делегат конкретной задачи.
private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let report: @Sendable (Double) -> Void
    init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        // До 0.99: последний процент — проверка суммы и распаковка.
        report(min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
