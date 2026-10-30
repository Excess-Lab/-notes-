import SwiftUI

// Вкладки открытых заметок над листом раздела (ТЗ 30.10.2026): капсулы в стиле пути, выбранная — ярче,
// крестик при наведении. Закрыли открытую — переходим на соседнюю, последнюю — ко всем заметкам.
extension NotesModel {
    func closeTab(_ url: URL) {
        guard let index = tabs.firstIndex(of: url) else { return }
        tabs.remove(at: index)
        guard openNote?.standardizedFileURL == url.standardizedFileURL else { return }
        if tabs.isEmpty { open(.folder(url.deletingLastPathComponent())) } else { open(.note(tabs[min(index, tabs.count - 1)])) }
    }
}

struct NoteTabs: View {
    let model: NotesModel
    @State private var hovered: URL?
    // Можно листать влево / вправо — этот край растворяется (ТЗ 30.10.2026: подсказка горизонтальной прокрутки).
    @State private var more: (left: Bool, right: Bool) = (false, false)

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(model.tabs, id: \.self) { url in
                    let active = model.openNote?.standardizedFileURL == url.standardizedFileURL
                    HStack(spacing: 6) {
                        Text(url.deletingPathExtension().lastPathComponent)
                            .font(Martian.body.font(13))
                            .kerning(Theme.tracking(-7, size: 13))
                            .foregroundStyle(active ? Theme.ink : NotesLayout.gray)
                            .lineLimit(1)
                            .frame(maxWidth: 160, alignment: .leading)
                            .fixedSize()
                        Button { model.closeTab(url) } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(NotesLayout.gray)
                                .frame(width: 14, height: 14)
                        }
                        .buttonStyle(.plain)
                        .opacity(hovered == url || active ? 1 : 0)
                        .help("закрыть")
                    }
                    .padding(.leading, 15).padding(.trailing, 10)
                    .frame(height: 36)
                    .background(Capsule().fill(Theme.bg.opacity(active ? 0.55 : 0.2)))
                    .contentShape(Capsule())
                    .onTapGesture { model.open(.note(url)) }
                    .onHover { inside in if inside { hovered = url } else if hovered == url { hovered = nil } }
                    .transition(.blurReplace)
                }
            }
            .animation(.smooth(duration: 0.3), value: model.tabs)
        }
        .scrollIndicators(.never)
        .onScrollGeometryChange(for: [Bool].self) { geo in
            [geo.contentOffset.x > 1, geo.contentOffset.x + geo.containerSize.width < geo.contentSize.width - 1]
        } action: { _, edges in
            withAnimation(.smooth(duration: 0.25)) { more = (edges[0], edges[1]) }
        }
        .mask(EdgeFade(left: more.left, right: more.right))
    }
}

// Маска с растворёнными краями — там, куда ещё можно листать.
struct EdgeFade: View {
    let left: Bool
    let right: Bool

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: left ? 40 : 0)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: right ? 40 : 0)
        }
    }
}
