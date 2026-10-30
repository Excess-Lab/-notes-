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
    }
}
