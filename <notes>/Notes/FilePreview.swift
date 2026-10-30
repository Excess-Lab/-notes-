import Quartz
import SwiftUI

// Файл из хранилища — PDF, Word, таблица, фото, видео — показываем прямо в листе встроенным
// просмотром macOS (Quick Look), без своих движков и зависимостей (ТЗ 30.10.2026). Только просмотр:
// править — в своей программе, кнопка «открыть в программе».
struct FilePreview: View {
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(url.lastPathComponent)
                    .font(Martian.heading.font(20))
                    .kerning(Theme.tracking(-7, size: 20))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer()
                Button("открыть в программе") { NSWorkspace.shared.open(url) }.buttonStyle(WhitePillStyle())
            }
            .padding(.horizontal, 56)
            .padding(.top, 36)
            QuickLook(url: url)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }
}

private struct QuickLook: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}
