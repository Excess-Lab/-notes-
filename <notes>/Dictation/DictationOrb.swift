import MetalKit
import SwiftUI

// Сфера надиктовки — стеклянный шар, как у новой Siri (кадры Макара, 30.10.2026). Рисует шейдер
// Orb.metal: за стеклом четыре полосы света по частотам голоса; распознаёт — по полосам бежит свет;
// готово — вместо галочки шар заливается зелёным и испаряется (ТЗ 01.11.2026).
struct DictationOrb: View {
    let state: DictationController.State
    let level: SIMD4<Float>
    @Environment(\.colorScheme) private var scheme

    // Холст шейдера с запасом: ореол раньше обрезался краем квадрата 1,3 (ТЗ: «рамка режет»).
    static let canvas: CGFloat = 1.9
    private let size: CGFloat = 96

    var body: some View {
        // Кадры рисует OrbLayer сам, 60 в секунду; SwiftUI пересчитывается только при смене состояния и громкости.
        OrbLayer(state: state, level: level, dark: scheme == .dark)
            .frame(width: size * Self.canvas, height: size * Self.canvas)
    }
}

// Metal-слой сферы: шейдер orbFragment из Orb.metal, ход времени и голоса — OrbClock. В покое — пауза.
private struct OrbLayer: NSViewRepresentable {
    let state: DictationController.State
    let level: SIMD4<Float>
    let dark: Bool

    func makeCoordinator() -> OrbRenderer { OrbRenderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.layer?.isOpaque = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        let renderer = context.coordinator
        renderer.state = state
        renderer.level = level
        renderer.dark = dark
        view.isPaused = state == .idle
    }
}

final class OrbRenderer: NSObject, MTKViewDelegate {
    let device = MTLCreateSystemDefaultDevice()
    private lazy var queue = device?.makeCommandQueue()
    private lazy var pipeline: MTLRenderPipelineState? = {
        guard let device, let library = device.makeDefaultLibrary() else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "orbVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "orbFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }()
    private let clock = OrbClock()
    var state: DictationController.State = .idle
    var level = SIMD4<Float>.zero
    var dark = true

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue?.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let frame = clock.step(now: Date(), state: state, level: level)
        let size = view.drawableSize
        // Голос чуть раздувает шар: меньше холст — крупнее сфера.
        let voice = frame.bands.max()
        var uniforms = OrbUniforms(size: SIMD2(Float(size.width), Float(size.height)), t: frame.t, dark: dark ? 1 : 0,
                                   canvas: Float(DictationOrb.canvas) / (1 + voice * 0.05), think: frame.think,
                                   done: frame.done, pad: 0, bands: frame.bands)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OrbUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

// Раскладка совпадает с OrbUniforms в Orb.metal: float2, шесть float, float4 (с выравниванием по 16).
private struct OrbUniforms {
    var size: SIMD2<Float>
    var t: Float
    var dark: Float
    var canvas: Float
    var think: Float
    var done: Float
    var pad: Float
    var bands: SIMD4<Float>
}

// Ход сферы по кадрам. Громкость сглаживается: вверх быстро (ловит каждый слог), вниз медленнее — без дрожи.
// «Думает» и «готово» въезжают плавно, а не скачком.
final class OrbClock {
    private var last: Date?
    private var phase = 0.0
    private var bands = SIMD4<Float>.zero
    private var think: Float = 0
    private var done: Float = 0

    func step(now: Date, state: DictationController.State, level: SIMD4<Float>) -> (t: Float, bands: SIMD4<Float>, think: Float, done: Float) {
        let dt = Float(min(0.05, last.map { now.timeIntervalSince($0) } ?? 0))
        last = now
        phase = (phase + Double(dt)).truncatingRemainder(dividingBy: 3600)
        let target = state == .listening ? level : .zero
        let rise = target .> bands
        let k = SIMD4<Float>(repeating: min(1, dt * 30)).replacing(with: min(1, dt * 7), where: .!rise)
        bands += (target - bands) * k
        think += ((state == .recognizing ? 1 : 0) - think) * min(1, dt * 5)
        // Заливка и испарение — 1,1 с; панель прячется через 1,2 с после «готово».
        done = state == .copied ? min(1, done + dt / 1.1) : 0
        return (Float(phase), bands, think, done)
    }
}
