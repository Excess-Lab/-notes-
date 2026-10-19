import SwiftUI

// Сфера надиктовки — компонент «надиктовка/сфера» из Figma (форма «круг»): тёмное стекло 96×96,
// блик сверху, отражение снизу, внутри чёрно-белые светящиеся волны.
struct DictationOrb: View {
    let state: DictationController.State
    let level: Float

    private static let size: CGFloat = 96

    var body: some View {
        ZStack {
            // Тело: радиальный градиент из макета — тёмный центр, светлеющий край.
            Circle()
                .fill(RadialGradient(stops: [
                    .init(color: Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.92), location: 0),
                    .init(color: Color(red: 0.02, green: 0.02, blue: 0.03).opacity(0.88), location: 0.75),
                    .init(color: Color(red: 0.25, green: 0.25, blue: 0.28).opacity(0.7), location: 1),
                ], center: .center, startRadius: 0, endRadius: Self.size / 2))
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.75))

            Group {
                if state == .copied {
                    CheckMark()
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 16)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Waves(state: state, level: level)
                        .transition(.opacity)
                }
            }

            // Блик сверху слева и отражение снизу — как в компоненте.
            Ellipse().fill(.white.opacity(0.22)).frame(width: 44, height: 14).blur(radius: 5)
                .rotationEffect(.degrees(18)).offset(x: -8, y: -29)
            Ellipse().fill(.white.opacity(0.10)).frame(width: 70, height: 10).blur(radius: 6)
                .offset(y: 31)
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
        .animation(.smooth(duration: 0.4), value: state)
    }
}

// Пять синусоид с затуханием к краям. Пока слушаем — амплитуда от громкости голоса;
// пока распознаём — волны схлопываются в светящуюся линию.
private struct Waves: View {
    let state: DictationController.State
    let level: Float

    // amplitude, frequency, phase, opacity, lineWidth — те же, что в компоненте Figma.
    private static let specs: [(CGFloat, CGFloat, CGFloat, Double, CGFloat)] = [
        (10, 1.2, 0, 0.95, 1.6), (7, 1.8, 1.4, 0.6, 1.2), (12, 0.9, 2.6, 0.45, 1.1),
        (5, 2.6, 0.6, 0.7, 1.0), (9, 1.5, 4.1, 0.35, 0.9),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let scale: CGFloat = state == .listening ? 0.25 + CGFloat(level) * 0.9 : 0.15
            ZStack {
                // Ореол и свечение под волнами.
                Ellipse().fill(.white.opacity(state == .listening ? 0.20 : 0.16))
                    .frame(width: state == .listening ? 80 : 60, height: state == .listening ? 34 : 12).blur(radius: 14)
                Ellipse().fill(.white.opacity(state == .listening ? 0.4 : 0.55))
                    .frame(width: state == .listening ? 50 : 40, height: state == .listening ? 10 : 4).blur(radius: 6)
                canvas(time: time, scale: scale).blur(radius: 2.5).opacity(0.85)
                canvas(time: time, scale: scale)
            }
        }
        .frame(width: 70, height: 30)
    }

    private func canvas(time: TimeInterval, scale: CGFloat) -> some View {
        Canvas { context, size in
            let gradient = Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                            .init(color: .white, location: 0.5),
                                            .init(color: .white.opacity(0), location: 1)])
            for (amplitude, frequency, phase, opacity, width) in Self.specs {
                var path = Path()
                for x in stride(from: 0, through: size.width, by: 1.5) {
                    let envelope = pow(sin(.pi * x / size.width), 1.8)
                    let y = size.height / 2 + amplitude * scale * envelope
                        * sin(x / size.width * .pi * 2 * frequency + phase + time * 2.4 * frequency)
                    x == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
                context.opacity = opacity
                context.stroke(path, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
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
