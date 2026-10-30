import NotesCore
import SwiftUI
import UniformTypeIdentifiers

// Видео — кадры «видео — список» и «видео — расшифровка» (секция «расшифровка видео»).
struct VideoScreen: View {
    let model: NotesModel

    var body: some View {
        if let id = model.video.open, let item = model.video.items.first(where: { $0.id == id }) {
            TranscriptView(model: model, item: item)
        } else {
            VideoList(video: model.video)
        }
    }
}

private struct VideoList: View {
    let video: VideoModel
    @State private var targeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("видео")
                    .font(Martian.heading.font(26))
                    .kerning(Theme.tracking(-7, size: 26))
                    .foregroundStyle(Theme.ink)
                Text("\(video.items.count) \(NoteEditor.plural(video.items.count, "расшифровка", "расшифровки", "расшифровок")) | распознаёт \(SpeechSettings.model.displayName)")
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(NotesLayout.gray)
                    .padding(.top, 6)

                // Зона, куда бросают файл: пунктир, как у «новой папки».
                VStack(spacing: 8) {
                    DotIcon(glyph: .plus, size: 24)
                    Text("перетащи видео или аудио сюда")
                        .font(Martian.heading.font(15))
                        .kerning(Theme.tracking(-7, size: 15))
                        .foregroundStyle(Theme.ink)
                    Text("mp4, mov, m4a или mp3")
                        .font(Martian.body.font(11))
                        .kerning(Theme.tracking(-7, size: 11))
                        .foregroundStyle(NotesLayout.gray)
                }
                .frame(width: 832, height: 132)
                .background(RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(targeted ? Theme.coral : NotesLayout.line, style: StrokeStyle(lineWidth: 2, dash: [6, 6])))
                .padding(.top, 46)
                .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                    for provider in providers {
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            if let url { Task { @MainActor in video.add([url]) } }
                        }
                    }
                    return true
                }

                Button("выбрать файл") { video.choose() }
                    .buttonStyle(CoralCapsuleStyle())
                    .frame(width: 832)
                    .padding(.top, 19)

                group("в работе", video.visible.filter { $0.status == .working || $0.status == .queued })
                group("готово", video.visible.filter { $0.status == .done })
                group("не получилось", video.visible.filter { $0.status == .failed })
            }
            .frame(width: 832, alignment: .leading)
            .padding(.leading, 58)
            .padding(.top, 36)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [VideoModel.Item]) -> some View {
        if !items.isEmpty {
            Text(title)
                .font(Martian.body.font(15))
                .kerning(Theme.tracking(-7, size: 15))
                .foregroundStyle(Theme.ink)
                .padding(.top, 30)
            ForEach(items) { item in VideoRow(video: video, item: item) }
        }
    }
}

private struct VideoRow: View {
    let video: VideoModel
    let item: VideoModel.Item

    var body: some View {
        HStack(spacing: 10) {
            DotIcon(glyph: .video)
            VStack(alignment: .leading, spacing: 3) {
                // Имя файла — как его назвал человек.
                Text(item.name)
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(Theme.ink.opacity(item.status == .queued ? 0.4 : 1))
                    .lineLimit(1)
                Text(meta)
                    .font(Martian.body.font(11))
                    .kerning(Theme.tracking(-7, size: 11))
                    .foregroundStyle(NotesLayout.gray)
            }
            Spacer(minLength: 10)
            switch item.status {
            case .working:
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.sheet)
                    Capsule().fill(Theme.coral).frame(width: 90 * item.progress)
                }
                .frame(width: 90, height: 6)
                Text("\(Int(item.progress * 100))%")
                    .font(Martian.body.font(11)).foregroundStyle(Theme.fg.opacity(0.3)).monospacedDigit()
                    .fixedSize()
            case .queued:
                Text("в очереди").font(Martian.body.font(13)).foregroundStyle(NotesLayout.gray)
            case .done:
                Button("открыть") { video.open = item.id }.buttonStyle(QuietLinkStyle(size: 13, opacity: 0.3))
            case .failed:
                Button("убрать") { video.remove(item.id) }.buttonStyle(QuietLinkStyle(size: 13, opacity: 0.3))
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(NotesLayout.line).frame(height: 1) }
        .padding(.top, 6)
    }

    private var meta: String {
        let size = ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)
        let length = item.duration > 0 ? " · " + Transcript.clock(item.duration) : ""
        switch item.status {
        case .done: return "\(NoteEditor.short(item.added))\(length) · \(item.words) \(NoteEditor.plural(item.words, "слово", "слова", "слов"))"
        case .failed: return "файл больше недоступен — добавь его заново"
        default: return size + length
        }
    }
}

// Расшифровка: заголовок — имя файла, главная кнопка «сохранить как заметку», рядом «копировать текст»
// и «экспорт .srt», ниже строки с метками времени.
private struct TranscriptView: View {
    let model: NotesModel
    let item: VideoModel.Item

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(Martian.heading.font(28))
                    .kerning(Theme.tracking(-7, size: 28))
                    .foregroundStyle(Theme.ink)
                Text("\(Transcript.clock(item.duration)) · \(SpeechSettings.model.displayName) · расшифровано \(NoteEditor.date(item.added))")
                    .font(Martian.body.font(11))
                    .kerning(Theme.tracking(-7, size: 11))
                    .foregroundStyle(NotesLayout.gray)
                    .padding(.top, 10)
                HStack(spacing: 10) {
                    Button("сохранить как заметку") {
                        if let url = model.video.saveAsNote(item.id) { model.open(.note(url)) }
                    }
                    .buttonStyle(CoralCapsuleStyle())
                    Button("копировать текст") { model.video.copy(item.id) }.buttonStyle(WhitePillStyle())
                    Button("экспорт .srt") { model.video.exportSRT(item.id) }.buttonStyle(WhitePillStyle())
                }
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array((model.video.transcript(item.id)?.segments ?? []).enumerated()), id: \.offset) { _, segment in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(Transcript.clock(segment.start))
                                .font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
                                .frame(width: 60, alignment: .leading)
                            Text(segment.text)
                                .font(Martian.body.font(15))
                                .kerning(Theme.tracking(-7, size: 15))
                                .foregroundStyle(Theme.ink)
                                .textSelection(.enabled)
                                .frame(width: 600, alignment: .leading)
                        }
                    }
                }
                .padding(.top, 24)
            }
            .frame(width: 660, alignment: .leading)
            .padding(.leading, 126)
            .padding(.top, 36)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.never)
    }
}
