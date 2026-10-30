// Фон окна установщика: тёмный, с вертикальными полосками как в шапке приложения,
// коралловая стрелка от иконки к «Программам». Запуск: swift Scripts/dmg-background.swift <выход.png>
import AppKit

let w: CGFloat = 640, h: CGFloat = 400, scale: CGFloat = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let fonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("<notes>/Fonts")
for name in ["MartianGrotesk-xWdUlt.otf", "MartianGrotesk-StdRg.otf"] {
    CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent(name) as CFURL, .process, nil)
}

NSColor(white: 0.04, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: w, height: h).fill()
// Полоски: тонкие вертикальные линии, ярче сверху и гаснут книзу.
let fade = NSGradient(colors: [NSColor(white: 1, alpha: 0.07), NSColor(white: 1, alpha: 0)])!
var x: CGFloat = 6
while x < w {
    fade.draw(in: NSRect(x: x, y: h * 0.35, width: 1, height: h * 0.65), angle: 90)
    x += 12
}

func text(_ s: String, font: String, size: CGFloat, alpha: CGFloat, y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont(name: font, size: size) ?? .systemFont(ofSize: size),
                                                .foregroundColor: NSColor(white: 1, alpha: alpha), .kern: -size * 0.05]
    let str = NSAttributedString(string: s, attributes: attrs)
    str.draw(at: NSPoint(x: (w - str.size().width) / 2, y: y))
}
text("<notes>", font: "MartianGrotesk-xWdUlt", size: 26, alpha: 1, y: h - 70)
text("перетащи в «Программы»", font: "MartianGrotesk-StdRg", size: 13, alpha: 0.45, y: 60)

// Стрелка между иконками (иконки Finder ставит в 160 и 480 по x, 200 по y сверху).
let coral = NSColor(red: 0xE5 / 255.0, green: 0x4D / 255.0, blue: 0x33 / 255.0, alpha: 1)
coral.setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 262, y: h - 190)); arrow.line(to: NSPoint(x: 378, y: h - 190))
arrow.move(to: NSPoint(x: 362, y: h - 176)); arrow.line(to: NSPoint(x: 378, y: h - 190)); arrow.line(to: NSPoint(x: 362, y: h - 204))
arrow.stroke()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
