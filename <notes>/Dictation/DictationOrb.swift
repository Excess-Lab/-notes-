import SwiftUI

// Сфера надиктовки — стеклянный шар, как у новой Siri (кадры Макара, 30.10.2026). Рисует шейдер
// Orb.metal: за стеклом полоса света, шар преломляет её, на концах радуга. Слушаем — полоса раскачивается
// и толстеет от голоса; распознаём — бежит быстрее. Светлая и тёмная тема — разная плотность стекла.
struct DictationOrb: View {
    let state: DictationController.State
    let level: Float
    @Environment(\.colorScheme) private var scheme
    @State private var motion = OrbClock()

    // Холст шейдера с запасом: ореол раньше обрезался краем квадрата 1,3 (ТЗ: «рамка режет»).
    static let canvas: CGFloat = 1.9

    var body: some View {
        // В покое анимация стоит: иначе скрытая сфера грела бы Mac.
        TimelineView(.animation(paused: state == .idle)) { timeline in
            let frame = motion.step(now: timeline.date, state: state, level: Double(level))
            OrbFace(t: frame.t, voice: frame.voice, state: state, dark: scheme == .dark)
        }
        .animation(.smooth(duration: 0.4), value: state)
    }
}

private struct OrbFace: View {
    let t: Float
    let voice: Float
    let state: DictationController.State
    let dark: Bool
    private let size: CGFloat = 96

    var body: some View {
        let canvas = DictationOrb.canvas
            ZStack {
                Rectangle().fill(.white)
                    .frame(width: size * canvas, height: size * canvas)
                    .colorEffect(ShaderLibrary.orb(.boundingRect, .float(t), .float(voice), .float(dark ? 1 : 0),
                                                   .float(canvas)))
                if state == .copied {
                    // Галочка — под стеклом: чуть размыта и прикрыта бликом, а не наклейкой сверху.
                    ZStack {
                        CheckMark()
                            .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .frame(width: 26, height: 19)
                            .blur(radius: 1.4)
                            .opacity(0.9)
                        Circle()
                            .fill(LinearGradient(colors: [.white.opacity(0.22), .clear, .white.opacity(0.08)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: size * 0.86, height: size * 0.86)
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .scaleEffect(1 + CGFloat(voice) * 0.04)
    }
}

// Ход сферы по кадрам: голос сглаживается каждый кадр (раньше прыгал с частотой звука — подлагивало),
// а время копится со своей скоростью: после конца речи — быстро, потом плавно замедляется (ТЗ 30.10.2026).
final class OrbClock {
    private var last: Date?
    private var phase = 0.0
    private var voice = 0.0
    private var recognizingSince: Date?

    func step(now: Date, state: DictationController.State, level: Double) -> (t: Float, voice: Float) {
        let dt = min(0.05, last.map { now.timeIntervalSince($0) } ?? 0)
        last = now
        if state == .recognizing { recognizingSince = recognizingSince ?? now } else { recognizingSince = nil }
        let speed: Double
        if let since = recognizingSince {
            speed = 1.2 + 3.8 * exp(-now.timeIntervalSince(since) / 0.9)
        } else {
            speed = 1
        }
        phase = (phase + dt * speed).truncatingRemainder(dividingBy: 3600)
        let target = state == .listening ? level : state == .copied ? 0 : 0.1
        voice += (target - voice) * min(1, dt * 12)
        return (Float(phase), Float(self.voice))
    }
}

// Кривые вращения из Figma (get_motion_context), снятые через каждые 100 мс, в радианах.
// Кадр колец повторяется каждые 4 с; само кольцо внутри кадра делает четыре быстрых оборота
// по секунде в первые 4 с из 16 и стоит остальные 12.
enum OrbMotion {
    static let step = 0.1
    static let cycle = 4.0
    static let timeline = 16.0

    static let outer: [Double] = [0, 0.091, 0.377, 0.866, 1.534, 2.311, 3.088, 3.755, 4.244, 4.53, 4.621, 4.642,
                                  4.708, 4.819, 4.961, 5.108, 5.229, 5.308, 5.34, 5.315, 5.182, 4.933, 4.569, 4.106,
                                  3.58, 3.047, 2.562, 2.168, 1.887, 1.723, 1.671, 1.638, 1.535, 1.358, 1.116, 0.835,
                                  0.555, 0.313, 0.136, 0.033, 0]
    static let middle: [Double] = [0, 0.095, 0.396, 0.875, 1.411, 1.838, 2.07, 2.086, 1.686, 0.781, -0.492, -1.766,
                                   -2.671, -3.071, -3.013, -2.555, -1.681, -0.453, 0.934, 2.208, 3.154, 3.686, 3.811,
                                   3.259, 1.88, 0.261, -0.74, -0.888, -0.363, 0.824, 2.495, 4.165, 5.353, 5.878, 5.794,
                                   5.147, 3.949, 2.449, 1.108, 0.267, 0]
    static let inner: [Double] = [0, -0.175, -0.684, -1.218, -1.433, -1.409, -1.316, -1.15, -0.911, -0.608, -0.258,
                                  0.108, 0.46, 0.766, 1.009, 1.179, 1.277, 1.306, 1.281, 1.209, 1.086, 0.912, 0.687,
                                  0.415, 0.102, -0.238, -0.592, -0.943, -1.273, -1.569, -1.822, -2.026, -2.177,
                                  -2.278, -2.33, -2.317, -2.022, -1.402, -0.674, -0.165, 0]
    static let spin: [Double] = [0, 0.096, 0.325, 0.79, 1.742, 3.461, 4.806, 5.519, 5.922, 6.156, 6.283]

    static func recognizing(frame: [Double], time: TimeInterval) -> Double {
        let inTimeline = time.truncatingRemainder(dividingBy: timeline)
        let ringSpin = inTimeline < cycle ? sample(spin, at: inTimeline.truncatingRemainder(dividingBy: 1)) : 0
        return sample(frame, at: time.truncatingRemainder(dividingBy: cycle)) + ringSpin
    }

    // Линейно между соседними замерами — при шаге 100 мс на глаз не отличить от кривой Figma.
    static func sample(_ values: [Double], at seconds: Double) -> Double {
        let position = max(0, seconds) / step
        let index = min(Int(position), values.count - 2)
        let fraction = min(1, position - Double(index))
        return values[index] + (values[index + 1] - values[index]) * fraction
    }
}

private struct CheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
