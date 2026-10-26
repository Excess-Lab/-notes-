import SwiftUI

// Полоса стеклянных планок поверх шахматки — фон загрузки и шапки онбординга.
// Зазора между планками нет никогда: при анимации растёт ширина каждой планки, а не расстояние.
//
// Рисуем сами, а не системным .glassEffect: эффект Glass в Figma увеличивает и сдвигает шахматку
// под каждой планкой, а системное стекло её размывает, и вместо макета выходят белые полосы со швами.
struct GlassSlats: View, Animatable {
    var slatWidth: CGFloat

    // Ширина анимируется покадрово, чтобы на каждом кадре заново считать число планок:
    // с фиксированным числом в начале анимации по бокам оставались пустые края.
    var animatableData: CGFloat {
        get { slatWidth }
        set { slatWidth = newValue }
    }

    // Шахматка 16 клеток на ширину окна (текстура 256 px растянута на 560), цвета сняты со скриншота Figma.
    private static let cellsAcross: CGFloat = 16
    // В тёмной теме шахматка почти чёрная (сняты с кадра 99:10847).
    private static let dark = Color(light: Color(white: 0.902), dark: Color(white: 0.012))
    private static let light = Color(light: Color(white: 0.965), dark: Color(white: 0.05))
    private static let glint = Color(light: .white.opacity(0.7), dark: .white.opacity(0.12))
    // Во сколько раз планка увеличивает шахматку под собой по горизонтали.
    private static let magnification: CGFloat = 1.8
    // Матовость стекла — radius 4 у эффекта Glass в Figma.
    private static let frost: CGFloat = 3

    var body: some View {
        // rendersAsynchronously: слоёв с размытием много (по одному на планку), рисуем вне главного потока.
        Canvas(rendersAsynchronously: true) { context, size in
            let cell = size.width / Self.cellsAcross
            let rows = Int((size.height / cell).rounded(.up))
            let width = max(slatWidth, 1)
            let count = Int((size.width / width).rounded(.up)) / 2 * 2 + 3
            var left = (size.width - CGFloat(count) * width) / 2

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.light))

            for _ in 0..<count {
                let center = left + width / 2
                let m = Self.magnification
                let slat = CGRect(x: left, y: 0, width: width, height: size.height)
                // Каждая планка — свой слой: обрезаем по её краям, а потом матуем. Так шахматка внутри
                // мягкая (матовость radius 4 у Glass в макете), а края планок остаются чёткими.
                context.drawLayer { layer in
                    layer.clip(to: Path(slat))
                    layer.addFilter(.blur(radius: Self.frost))
                    layer.fill(Path(slat.insetBy(dx: -Self.frost * 2, dy: -Self.frost * 2)), with: .color(Self.light))
                    // Какой кусок шахматки видно сквозь планку: середина та же, ширина в m раз меньше.
                    var sample = center - width / (2 * m)
                    let sampleEnd = center + width / (2 * m)
                    while sample < sampleEnd - 0.001 {
                        let column = (sample / cell).rounded(.down)
                        let next = min(sampleEnd, (column + 1) * cell)
                        // Края куска тянем за планку, чтобы размытие не светлело у её краёв.
                        let x0 = sample <= center - width / (2 * m) + 0.001 ? left - Self.frost * 2 : center + (sample - center) * m
                        let x1 = next >= sampleEnd - 0.001 ? left + width + Self.frost * 2 : center + (next - center) * m
                        for row in 0..<rows where (Int(column) + row).isMultiple(of: 2) {
                            let rect = CGRect(x: x0, y: CGFloat(row) * cell, width: x1 - x0, height: cell)
                            layer.fill(Path(rect), with: .color(Self.dark))
                        }
                        sample = next
                    }
                }
                // Блик по левому краю планки — как кромка стекла в макете.
                context.fill(Path(CGRect(x: left, y: 0, width: 1, height: size.height)),
                             with: .color(Self.glint))
                left += width
            }
        }
        // Маска из макета: полоса непрозрачна до 57,7 % своей высоты и гаснет к низу.
        // Маска считается от высоты самой полосы, поэтому работает и на весь экран, и в шапке 66 px.
        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                     .init(color: .black, location: 0.577),
                                     .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }
}
