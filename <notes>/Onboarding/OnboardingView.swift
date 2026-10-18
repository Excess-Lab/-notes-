import SwiftUI

// Окно первого входа 560×440. Сейчас здесь загрузка и шаг 1, остальные шаги — дальше по ONBOARDING.md.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        LoadingScene(model: model)
            .id(model.runID)
            .frame(width: Layout.window.width, height: Layout.window.height)
            .background(.white)
    }
}

enum Layout {
    static let window = CGSize(width: 560, height: 440)
    static let sheetTop: CGFloat = 54
    static let headerHeight: CGFloat = 66
    // Размытие стекла листа (radius 4 у эффекта Glass в Figma).
    static let sheetBlur: CGFloat = 4
    static let logoTop: CGFloat = 27
    static let finalSlatWidth: CGFloat = 20
    // Стартовая ширина: тоньше — больше планок на экране и дороже кадр.
    static let startSlatWidth: CGFloat = 4
}

private struct LoadingScene: View {
    let model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var slatWidth = Layout.startSlatWidth
    @State private var logoVisible = false
    @State private var contentVisible = false
    @State private var finaleVisible = false

    private var isSteps: Bool { model.phase == .steps }
    private var isFinished: Bool { model.phase == .finished }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // На финале лист уезжает вниз, а полосы снова встают на весь экран.
            let sheetY = isSteps ? Layout.sheetTop : size.height
            ZStack(alignment: .top) {
                // Слои как в макете: шапка из полос (на загрузке на весь экран, потом 66 px),
                // поверх неё стеклянный лист. Лист наезжает на шапку на 12 px и размывает её край.
                slats(height: isSteps ? Layout.headerHeight : size.height)
                    .mask(alignment: .top) { Rectangle().frame(height: sheetY) }

                // То, что под листом, видно через стекло размытым.
                slats(height: isSteps ? Layout.headerHeight : size.height)
                    .blur(radius: Layout.sheetBlur)
                    .mask(alignment: .top) {
                        RoundedRectangle(cornerRadius: 18).offset(y: sheetY)
                    }

                StepSheet(model: model, contentVisible: contentVisible)
                    .frame(height: size.height - Layout.sheetTop)
                    .offset(y: sheetY)

                logo
                    .position(x: size.width / 2, y: logoY(in: size))

                finale
                    .position(x: size.width / 2, y: 0)
            }
        }
        .clipped()
        .task { await run() }
    }

    private func slats(height: CGFloat) -> some View {
        GlassSlats(slatWidth: slatWidth)
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    private var logo: some View {
        Text("<notes>")
            .font(Martian.logo.font(30))
            .kerning(Theme.tracking(-5, size: 30))
            .foregroundStyle(.black)
            // В шапке логотип вдвое меньше (15 вместо 30). На финале он улетает вверх и гаснет.
            .scaleEffect(isSteps || isFinished ? 0.5 : (logoVisible ? 1 : 0.92))
            .opacity(logoVisible && !isFinished ? 1 : 0)
            .blur(radius: logoVisible && !isFinished ? 0 : 10)
    }

    private func logoY(in size: CGSize) -> CGFloat {
        switch model.phase {
        case .loading: size.height / 2
        case .steps: Layout.logoTop
        case .finished: -Layout.logoTop
        }
    }

    // Кадр «все круто!(10)»: «все готово» (y = 202) и «листай вниз» (y = 239) проявляются со стекла.
    private var finale: some View {
        VStack(spacing: 1) {
            Text("все готово")
                .font(Martian.logo.font(30))
                .kerning(Theme.tracking(-5, size: 30))
                .foregroundStyle(.black)
            Text("листай вниз")
                .font(Martian.body.font(11))
                .kerning(Theme.tracking(-7, size: 11))
                .foregroundStyle(.black.opacity(0.3))
        }
        .opacity(finaleVisible ? 1 : 0)
        .blur(radius: finaleVisible ? 0 : 14)
        .scaleEffect(finaleVisible ? 1 : 1.04)
        .offset(y: 202 + 25)
        .onChange(of: isFinished) { _, finished in
            guard finished else { finaleVisible = false; return }
            Task {
                // Сначала уезжает лист и встают полосы, потом проявляется текст.
                try? await Task.sleep(for: .seconds(0.7))
                withAnimation(.smooth(duration: 1.6)) { finaleVisible = true }
            }
        }
    }

    private func run() async {
        if model.phase == .finished {
            slatWidth = Layout.finalSlatWidth
            logoVisible = true
            finaleVisible = true
            return
        }
        if reduceMotion || model.phase == .steps {
            slatWidth = Layout.finalSlatWidth
            logoVisible = true
            model.phase = .steps
            contentVisible = true
            return
        }
        withAnimation(.smooth(duration: 2.4)) { slatWidth = Layout.finalSlatWidth }
        try? await Task.sleep(for: .seconds(0.4))
        withAnimation(.smooth(duration: 1.4)) { logoVisible = true }

        // Пока настоящей загрузки нет, держим сцену фиксированное время.
        try? await Task.sleep(for: .seconds(2.0))
        withAnimation(.smooth(duration: 1.3)) { model.phase = .steps }
        // Текст начинает проявляться, пока лист ещё едет, — без паузы и без рывка.
        try? await Task.sleep(for: .seconds(0.35))
        contentVisible = true
    }
}

// Стеклянный лист с содержимым текущего шага.
private struct StepSheet: View {
    let model: OnboardingModel
    var contentVisible: Bool

    var body: some View {
        ZStack(alignment: .top) {
            // Заливка листа из макета: #F9F9F9 с прозрачностью 20 %. Ниже шапки под ним белый фон окна.
            // Поверх затухания шапки у стекла свой край: светлый кант по кромке и лёгкая тень на шапку.
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(white: 249 / 255).opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.07), radius: 10, y: -2)

            OnboardingStepContent(model: model)
                .id(model.step)
                // Старый шаг уходит в размытие, новый из него проявляется.
                .transition(.blurReplace)
                .reveal(contentVisible)
        }
    }
}

struct CoralCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Martian.body.font(13))
            .kerning(Theme.tracking(-7, size: 13))
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 15)
            // В Figma у кнопки стоит Glass, но выглядит она ровной коралловой капсулой.
            // Системное стекло давало глянцевый обод и темнило цвет, поэтому только заливка.
            .background(Capsule().fill(Theme.coral.opacity(0.99)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

// Мелкая серая ссылка под кнопкой («пропустить», «назад»): Std Rg 8, прозрачность 20 %.
struct QuietLinkStyle: ButtonStyle {
    var size: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Martian.body.font(size))
            .kerning(Theme.tracking(-7, size: size))
            .foregroundStyle(.black.opacity(configuration.isPressed ? 0.4 : 0.2))
            .contentShape(Rectangle())
    }
}

private extension View {
    // Содержимое листа при первом появлении проявляется из размытия и чуть поднимается.
    // Только прозрачность выглядела резко: текст будто включали.
    func reveal(_ visible: Bool, delay: Double = 0) -> some View {
        opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 6)
            .offset(y: visible ? 0 : 10)
            .animation(.smooth(duration: 1.1).delay(delay), value: visible)
    }
}

#Preview {
    OnboardingView(model: OnboardingModel())
}
