import SwiftUI

// Сфера надиктовки — кадр «распознование» (узел Figma 92:10604): три кольца с угловыми градиентами
// (синий, коралловый, жёлтый ведущий цвет, дальше белый на убыль) под стеклянным кругом.
// Слушаем — кольца медленно плывут и раздуваются от громкости голоса.
// Распознаём — крутятся по кривым из Figma: цикл 4 с, внутри кольца в первые 4 с из 16 — быстрые обороты.
struct DictationOrb: View {
    let state: DictationController.State
    let level: Float

    // Стекло в макете 324 при кольцах 378 / 318 / 266 — здесь то же соотношение при стекле 96.
    private static let size: CGFloat = 96
    private static let rings: [(diameter: CGFloat, color: Color, frame: [Double])] = [
        (378, Color(red: 0, green: 0x71 / 255, blue: 0xE3 / 255), OrbMotion.outer),
        (318, Theme.coral, OrbMotion.middle),
        (266, Color(red: 0xFE / 255, green: 0xBC / 255, blue: 0x2E / 255), OrbMotion.inner),
    ]

    var body: some View {
        // В покое анимация стоит: раньше она крутилась и при скрытой сфере, и приложение грело Mac
        // («Energy Impact: Very High» в Xcode).
        TimelineView(.animation(paused: state == .idle)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // Блум: те же кольца, сильнее размытые и ярче, светятся за краем стекла.
                rings(time: time)
                    .frame(width: Self.size + 40, height: Self.size + 40)
                    // Кольца и их размытие — одним слоем через Metal: иначе каждый кадр дорогой.
                    // Стекло (материал) сюда не попадает: в отдельном слое оно не видит, что под окном.
                    .drawingGroup()
                    .blur(radius: 16)
                    .opacity(0.55)
                    .blendMode(.plusLighter)

                sphere(time: time)
            }
        }
        .animation(.smooth(duration: 0.4), value: state)
    }

    private func sphere(time: TimeInterval) -> some View {
        ZStack {
                // Фона у сферы нет: под ней размытие того, что на экране (как стекло в макете).
                Circle().fill(.ultraThinMaterial)

                rings(time: time)
                    .drawingGroup()
                    // Стекло в макете (Glass, преломление 0,8) размывает кольца в мягкие пятна цвета.
                    .blur(radius: 9)

                // Мягкая тень в середине — как на кадре.
                Circle().fill(RadialGradient(colors: [.black.opacity(0.25), .clear], center: .center,
                                             startRadius: 0, endRadius: Self.size * 0.36))
                Circle().fill(.white.opacity(0.06))
                // Кромка стекла с лёгкой радугой (дисперсия 0,5 в макете).
                Circle().strokeBorder(AngularGradient(colors: [.cyan.opacity(0.5), .white.opacity(0.35),
                                                               .pink.opacity(0.45), .white.opacity(0.3),
                                                               .yellow.opacity(0.4), .cyan.opacity(0.5)],
                                                      center: .center), lineWidth: 0.8)

                if state == .copied {
                    CheckMark()
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 16)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(Circle())
    }

    private func rings(time: TimeInterval) -> some View {
                ZStack {
                    ForEach(Self.rings.indices, id: \.self) { index in
                        let ring = Self.rings[index]
                        Circle()
                            .fill(AngularGradient(stops: Self.stops(ring.color), center: .center,
                                                  angle: .degrees(-90)))
                            .frame(width: Self.scaled(ring.diameter), height: Self.scaled(ring.diameter))
                            .rotationEffect(.radians(angle(ring: ring.frame, index: index, time: time)))
                    }
                }
                // Голос раздувает кольца и делает их ярче.
                .scaleEffect(state == .listening ? 1 + CGFloat(level) * 0.18 : 1)
                .opacity(state == .listening ? 0.75 + Double(level) * 0.25 : 1)
    }

    private static func scaled(_ figma: CGFloat) -> CGFloat { figma / 324 * size }

    // Стопы угловой заливки колец из макета: ведущий цвет, потом белый 25 % → 10 % → 10 % → 25 % → 100 %.
    private static func stops(_ lead: Color) -> [Gradient.Stop] {
        [.init(color: lead, location: 0),
         .init(color: .white.opacity(0.25), location: 0.125),
         .init(color: .white.opacity(0.10), location: 0.25),
         .init(color: .white.opacity(0.10), location: 0.745),
         .init(color: .white.opacity(0.25), location: 0.87),
         .init(color: .white, location: 1)]
    }

    private func angle(ring frame: [Double], index: Int, time: TimeInterval) -> Double {
        switch state {
        case .recognizing:
            return OrbMotion.recognizing(frame: frame, time: time)
        case .listening:
            // Пока слушаем — спокойное вращение в разные стороны, чтобы кольца не слипались.
            return time * [0.35, -0.5, 0.65][index]
        default:
            return 0
        }
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
