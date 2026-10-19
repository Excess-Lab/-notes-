import AVFoundation

// Пишет микрофон и сразу переводит в формат моделей: 16 кГц, моно, Float.
//
// Колбэк записи приходит не с главного потока, а с аудиопотока системы, поэтому класс не привязан
// к главному актору (в проекте он по умолчанию), а общие данные защищены замком.
nonisolated final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    // level — громкость 0…1 для волн в сфере; вызывается примерно 10 раз в секунду.
    func start(level: @escaping @Sendable (Float) -> Void) throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: source, to: target) else {
            throw NSError(domain: "notes.audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "микрофон в неподдерживаемом формате"])
        }
        // С macOS 27 подключение к микрофону сообщает об ошибке, а не падает молча. Метод помечен
        // NS_REFINED_FOR_SWIFT, но Swift-обёртки в SDK пока нет: импортёр делает его бросающим
        // и оставляет пустой параметр error: () — отсюда странный вызов.
        try input.__installTap(onBus: 0, bufferSize: 4096, format: source, error: ()) { [weak self] buffer, _ in
            guard let self else { return }
            level(Self.level(of: buffer))
            self.append(buffer, using: converter, from: source)
        }
        engine.prepare()
        try engine.start()
    }

    // Останавливает запись и отдаёт всё записанное.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock { samples }
    }

    private func append(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, from source: AVAudioFormat) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / source.sampleRate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return }
        let chunk = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))
        lock.withLock { samples.append(contentsOf: chunk) }
    }

    // Громкость как среднеквадратичное, растянутое так, чтобы обычная речь давала 0.3–0.8.
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += channel[i] * channel[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        return min(1, rms * 12)
    }
}
