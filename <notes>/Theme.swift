import SwiftUI
import CoreText

// Шрифты и цвета из макета. Числа взяты из Figma, а не на глаз.
enum Theme {
    static let coral = Color(red: 229 / 255, green: 77 / 255, blue: 51 / 255)
    static let ink = Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255)

    // Трекинг в макете задан в процентах от кегля, а SwiftUI ждёт пункты.
    static func tracking(_ percent: CGFloat, size: CGFloat) -> CGFloat { size * percent / 100 }
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
