import SwiftUI

@Observable
final class OnboardingModel {
    enum Phase { case loading, welcome }

    var phase: Phase = .loading
    // Меняется при каждом перезапуске сцены, чтобы SwiftUI пересоздал её с нуля.
    var runID = UUID()

    func restart() {
        phase = .loading
        runID = UUID()
    }
}

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

    private var isWelcome: Bool { model.phase == .welcome }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let sheetY = isWelcome ? Layout.sheetTop : size.height
            ZStack(alignment: .top) {
                // Слои как в макете: шапка из полос (на загрузке на весь экран, потом 66 px),
                // поверх неё стеклянный лист. Лист наезжает на шапку на 12 px и размывает её край.
                slats(height: isWelcome ? Layout.headerHeight : size.height)
                    .mask(alignment: .top) { Rectangle().frame(height: sheetY) }

                // То, что под листом, видно через стекло размытым.
                slats(height: isWelcome ? Layout.headerHeight : size.height)
                    .blur(radius: Layout.sheetBlur)
                    .mask(alignment: .top) {
                        RoundedRectangle(cornerRadius: 18).offset(y: sheetY)
                    }

                WelcomeSheet(contentVisible: contentVisible)
                    .frame(height: size.height - Layout.sheetTop)
                    .offset(y: sheetY)

                logo
                    .position(x: size.width / 2, y: isWelcome ? Layout.logoTop : size.height / 2)
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
            // В шапке логотип вдвое меньше (15 вместо 30).
            .scaleEffect(isWelcome ? 0.5 : (logoVisible ? 1 : 0.92))
            .opacity(logoVisible ? 1 : 0)
            .blur(radius: logoVisible ? 0 : 10)
    }

    private func run() async {
        if reduceMotion {
            slatWidth = Layout.finalSlatWidth
            logoVisible = true
            model.phase = .welcome
            contentVisible = true
            return
        }
        withAnimation(.smooth(duration: 2.4)) { slatWidth = Layout.finalSlatWidth }
        try? await Task.sleep(for: .seconds(0.4))
        withAnimation(.smooth(duration: 1.4)) { logoVisible = true }

        // Пока настоящей загрузки нет, держим сцену фиксированное время.
        try? await Task.sleep(for: .seconds(2.0))
        withAnimation(.smooth(duration: 1.3)) { model.phase = .welcome }
        // Текст начинает проявляться, пока лист ещё едет, — без паузы и без рывка.
        try? await Task.sleep(for: .seconds(0.35))
        contentVisible = true
    }
}

// Стеклянный лист шага 1. Координаты текста — от верха листа (лист начинается на y = 54).
private struct WelcomeSheet: View {
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

            VStack(spacing: 0) {
                Text("привет!")
                    .font(Martian.heading.font(26))
                    .kerning(Theme.tracking(-7, size: 26))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 96 - Layout.sheetTop)
                    .reveal(contentVisible, delay: 0)

                Text("выбери папку куда сохранять заметки")
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(.black.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .frame(width: 380)
                    .padding(.top, 10)
                    .reveal(contentVisible, delay: 0.12)

                Spacer()

                Button("создать папку") {}
                    .buttonStyle(CoralCapsuleStyle())
                    .reveal(contentVisible, delay: 0.26)

                Button("выбрать папку") {}
                    .buttonStyle(.plain)
                    .font(Martian.body.font(8))
                    .kerning(Theme.tracking(-7, size: 8))
                    .foregroundStyle(.black.opacity(0.2))
                    .padding(.top, 31)
                    .padding(.bottom, 20)
                    .reveal(contentVisible, delay: 0.34)
            }
            .frame(maxWidth: .infinity)
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

private extension View {
    // Текст проявляется из размытия и чуть поднимается — по очереди, сверху вниз.
    // Только прозрачность выглядела резко: текст будто включали.
    func reveal(_ visible: Bool, delay: Double) -> some View {
        opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 6)
            .offset(y: visible ? 0 : 10)
            .animation(.smooth(duration: 1.1).delay(delay), value: visible)
    }
}

#Preview {
    OnboardingView(model: OnboardingModel())
}
