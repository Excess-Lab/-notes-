import SwiftUI

// Сфера надиктовки — стеклянный шар, как у новой Siri (кадры Макара, 30.10.2026). Рисует шейдер
// Orb.metal: за стеклом полоса света, шар преломляет её, на концах радуга. Слушаем — полоса раскачивается
// и толстеет от голоса; распознаём — бежит быстрее. Светлая и тёмная тема — разная плотность стекла.
struct DictationOrb: View {
    let state: DictationController.State
    let level: Float
    @Environment(\.colorScheme) private var scheme

    private static let size: CGFloat = 96

    var body: some View {
        // В покое анимация стоит: иначе скрытая сфера грела бы Mac.
        TimelineView(.animation(paused: state == .idle)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600) * (state == .recognizing ? 2.4 : 1)
            let voice = state == .listening ? Double(level) : state == .copied ? 0 : 0.1
            ZStack {
                Rectangle().fill(.white)
                    .frame(width: Self.size * 1.3, height: Self.size * 1.3)
                    .colorEffect(ShaderLibrary.orb(.boundingRect, .float(t), .float(voice), .float(scheme == .dark ? 1 : 0)))
                if state == .copied {
                    CheckMark()
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 16)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .scaleEffect(1 + voice * 0.04)
        }
        .animation(.smooth(duration: 0.4), value: state)
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
