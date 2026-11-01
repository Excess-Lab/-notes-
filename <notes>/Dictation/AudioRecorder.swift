import Accelerate
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

    // level — громкость 0…1 по четырём полосам частот (низкие → высокие) для полос света в сфере;
    // вызывается ~40 раз в секунду.
    func start(level: @escaping @Sendable (SIMD4<Float>) -> Void) throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: source, to: target) else {
            throw NSError(domain: "notes.audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "микрофон в неподдерживаемом формате"])
        }
        // С macOS 27 подключение к микрофону сообщает об ошибке, а не падает молча. Метод помечен
        // NS_REFINED_FOR_SWIFT, но Swift-обёртки в SDK пока нет: импортёр делает его бросающим
        // и оставляет пустой параметр error: () — отсюда странный вызов.
        try input.__installTap(onBus: 0, bufferSize: 1024, format: source, error: ()) { [weak self] buffer, _ in
            guard let self else { return }
            level(self.bands(of: buffer, rate: source.sampleRate))
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

    // Полосы: 80–300 Гц, 300–1000, 1–3 кГц, 3–8 кГц. Громкость в децибелах, а не линейно: тихая речь
    // тоже качает сферу (ТЗ 01.11.2026: «чувствительней на звук»). У речи верх тише низа — у каждой
    // полосы свой «потолок», снят по записи голоса; 35 дБ ниже потолка — ноль.
    private static let n = 1024
    private static let edges: [Double] = [80, 300, 1000, 3000, 8000]
    private static let ceilings: SIMD4<Float> = [-38, -45, -55, -64]
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
    private let fft = vDSP.FFT(log2n: 10, radix: .radix2, ofType: DSPSplitComplex.self)!

    private func bands(of buffer: AVAudioPCMBuffer, rate: Double) -> SIMD4<Float> {
        let n = Self.n
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return .zero }
        var frame = [Float](repeating: 0, count: n)
        for i in 0..<min(n, Int(buffer.frameLength)) { frame[i] = channel[i] * window[i] }
        var real = [Float](repeating: 0, count: n / 2), imag = real, power = real
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                frame.withUnsafeBytes { vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2)) }
                fft.forward(input: split, output: &split)
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
            }
        }
        let hz = rate / Double(n)
        var out = SIMD4<Float>.zero
        for b in 0..<4 {
            let lo = max(1, Int(Self.edges[b] / hz)), hi = min(n / 2 - 1, Int(Self.edges[b + 1] / hz))
            let energy = power[lo...hi].reduce(0, +) / Float(hi - lo + 1)
            let db = 10 * log10(energy / Float(n * n) + 1e-12)
            out[b] = min(1, max(0, (db - Self.ceilings[b] + 35) / 35))
        }
        return out
    }
}
