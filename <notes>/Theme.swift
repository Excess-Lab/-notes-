import AppKit
import SwiftUI
import CoreText

// Шрифты и цвета из макета. Числа взяты из Figma, а не на глаз.
// Тёмная тема — секция «первый вход» рядом со светлой (99:10846): там всё зеркально — фон и капсулы
// чёрные, текст белый, прозрачности те же, главная кнопка белая. Цвет сам выбирает вариант по теме macOS.
enum Theme {
    static let coral = Color(red: 229 / 255, green: 77 / 255, blue: 51 / 255)
    // Заголовки и иконки: #1D1D1F → белый.
    static let ink = Color(light: Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255), dark: .white)
    // Текст и подписи (прозрачность — своя у каждого места, как в макете).
    static let fg = Color(light: .black, dark: .white)
    // Фон окна, вторичные капсулы, клавиши, затемнение под окном пинкода.
    static let bg = Color(light: .white, dark: .black)
    // Стеклянный лист и строки: #F9F9F9 → #1F1F1F.
    static let sheet = Color(light: Color(white: 249 / 255), dark: Color(white: 31 / 255))
    // Светлый кант по кромке стекла: на тёмном — едва заметный.
    static let edge = Color(light: .white, dark: .white.opacity(0.14))
    // Главная кнопка: коралловая → белая с чёрным текстом.
    static let primary = Color(light: coral, dark: .white)
    static let onPrimary = Color(light: .white, dark: .black)

    // Трекинг в макете задан в процентах от кегля, а SwiftUI ждёт пункты.
    static func tracking(_ percent: CGFloat, size: CGFloat) -> CGFloat { size * percent / 100 }
}

extension Color {
    // Цвет со светлым и тёмным вариантом: macOS сама выбирает по теме системы и перекрашивает
    // на лету, когда тему меняют. Веб-аналог — переменная CSS внутри prefers-color-scheme.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}

enum Martian: String {
    case logo = "MartianGrotesk-xWdUlt"
    case heading = "MartianGrotesk-xWdxBd"
    case body = "MartianGrotesk-StdRg"
    case medium = "MartianGrotesk-StdMd"

    func font(_ size: CGFloat) -> Font { .custom(rawValue, fixedSize: size) }
}

enum FontRegistrar {
    // Регистрируем шрифты из бандла сами, а не через Info.plist: Info.plist генерируется Xcode,
    // и ключ ATSApplicationFontsPath туда без своего plist не добавить.
    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
