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
    @Environment(\.pageWidth) private var page
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

                // Зона, куда бросают файл — кадр 151:32745: стеклянные планки поверх живого фона (DropZone.metal); клик — выбрать
                // файл. Отдельной кнопки «выбрать файл» нет (ТЗ 30.10.2026).
                Button { video.choose() } label: {
                    VStack(spacing: 8) {
                        DotIcon(glyph: .plus, size: 24).environment(\.colorScheme, .dark)
                        Text(targeted ? "отпусти — начнём расшифровку" : "перетащи видео или аудио")
                            .font(Martian.heading.font(15))
                            .kerning(Theme.tracking(-7, size: 15))
                            .foregroundStyle(.white)
                            .contentTransition(.interpolate)
                        Text("или нажми, чтобы выбрать · mp4, mov, mp3, wav, flac и другие")
                            .font(Martian.body.font(11))
                            .kerning(Theme.tracking(-7, size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(width: min(832, page), height: 148)
                    .background {
                        TimelineView(.animation) { context in
                            Rectangle().fill(.white)
                                .colorEffect(ShaderLibrary.dropzone(.boundingRect,
                                    .float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)),
                                    .float(targeted ? 1 : 0)))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                    .overlay(RoundedRectangle(cornerRadius: 30)
                        .strokeBorder(targeted ? Theme.coral : Theme.edge.opacity(0.6), lineWidth: 1))
                    .scaleEffect(targeted ? 1.015 : 1)
                    .animation(.smooth(duration: 0.3), value: targeted)
                    .contentShape(RoundedRectangle(cornerRadius: 30))
                }
                .buttonStyle(.plain)
                .padding(.top, 46)
                .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                    for provider in providers {
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            if let url { Task { @MainActor in video.add([url]) } }
                        }
                    }
                    return true
                }

                group("в работе", video.visible.filter { $0.status == .working || $0.status == .queued })
                group("готово", video.visible.filter { $0.status == .done })
                group("не получилось", video.visible.filter { $0.status == .failed })
            }
            .frame(width: min(832, page), alignment: .leading)
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
                Button("удалить") { VideoModel.confirmRemove(item, video: video) }.buttonStyle(QuietLinkStyle(size: 13, opacity: 0.3))
            case .failed:
                Button("убрать") { video.remove(item.id) }.buttonStyle(QuietLinkStyle(size: 13, opacity: 0.3))
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(NotesLayout.line).frame(height: 1) }
        .contentShape(Rectangle())
        // В папку — правым кликом или перетащить строку на папку слева.
        .contextMenu {
            Menu("в папку") {
                ForEach(video.folders, id: \.self) { name in Button(name) { video.move(item.id, to: name) } }
                if item.folder != nil { Divider(); Button("без папки") { video.move(item.id, to: nil) } }
            }
            .disabled(video.folders.isEmpty)
        }
        .draggable(item.id.uuidString)
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

extension VideoModel {
    // Удалить расшифровку — с подтверждением: текст пропадёт, сам видеофайл не трогаем.
    static func confirmRemove(_ item: Item, video: VideoModel) {
        let alert = NSAlert()
        alert.messageText = "Удалить расшифровку «\(item.name)»?"
        alert.informativeText = "Текст пропадёт. Сам файл и заметки, уже сохранённые из него, останутся."
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn { video.remove(item.id) }
    }
}

// Расшифровка: заголовок — имя файла, главная кнопка «сохранить как заметку», рядом «копировать текст»
// и «экспорт .srt», ниже строки с метками времени.
private struct TranscriptView: View {
    @Environment(\.pageWidth) private var page
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
                    if Intelligence.isReady {
                        Button(model.video.summarizing.contains(item.id) ? "сжимаю…" : "кратко") {
                            Task { await model.video.summarize(item.id) }
                        }
                        .buttonStyle(WhitePillStyle())
                        .disabled(model.video.summarizing.contains(item.id))
                    }
                    Button("копировать текст") { model.video.copy(item.id) }.buttonStyle(WhitePillStyle())
                    Button("экспорт .srt") { model.video.exportSRT(item.id) }.buttonStyle(WhitePillStyle())
                    Button("удалить") { VideoModel.confirmRemove(item, video: model.video) }.buttonStyle(QuietLinkStyle(size: 13, opacity: 0.3))
                }
                .padding(.top, 16)

                if let summary = model.video.transcript(item.id)?.summary {
                    Text(summary)
                        .font(Martian.body.font(15))
                        .kerning(Theme.tracking(-7, size: 15))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .frame(width: min(600, page - 60), alignment: .leading)
                        .padding(.leading, 60)
                        .padding(.top, 24)
                }

                VStack(alignment: .leading, spacing: 16) {
                    let transcript = model.video.transcript(item.id)
                    ForEach(Array((transcript?.segments ?? []).enumerated()), id: \.offset) { index, segment in
                        if let transcript, let speaker = segment.speaker,
                           index == 0 || transcript.segments[index - 1].speaker != speaker {
                            SpeakerName(transcript: transcript, speaker: speaker) { model.video.rename(item.id, speaker: speaker, to: $0) }
                                .padding(.leading, 60)
                                .padding(.top, index == 0 ? 0 : 8)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(Transcript.clock(segment.start))
                                .font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
                                .frame(width: 60, alignment: .leading)
                            Text(segment.text)
                                .font(Martian.body.font(15))
                                .kerning(Theme.tracking(-7, size: 15))
                                .foregroundStyle(Theme.ink)
                                .textSelection(.enabled)
                                .frame(width: min(600, page - 60), alignment: .leading)
                        }
                        .contextMenu {
                            // Разметка ошиблась — переотметить реплику: другой спикер или новый.
                            if let transcript, segment.speaker != nil {
                                ForEach(transcript.speakers, id: \.self) { speaker in
                                    Button(transcript.name(speaker)) { model.video.mark(item.id, segment: index, as: speaker) }
                                        .disabled(speaker == segment.speaker)
                                }
                                Divider()
                                Button("новый спикер") { model.video.mark(item.id, segment: index, as: transcript.nextSpeaker) }
                            }
                        }
                    }
                }
                .padding(.top, 24)
            }
            .frame(width: min(660, page), alignment: .leading)
            .padding(.leading, 126)
            .padding(.top, 36)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.never)
    }
}

// Имя спикера над его репликами; щелчок — переименовать на месте, Return или уход фокуса сохраняет.
private struct SpeakerName: View {
    let transcript: Transcript
    let speaker: Int
    let rename: (String) -> Void
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { editing = false }
                    .onChange(of: focused) { if !focused { editing = false } }
                    .onDisappear { rename(text) }
                    .onAppear { focused = true }
            } else {
                Text(transcript.name(speaker))
                    .onTapGesture { text = transcript.names[speaker] ?? ""; editing = true }
                    .help("переименовать")
            }
        }
        .font(Martian.body.font(11))
        .kerning(Theme.tracking(-7, size: 11))
        .foregroundStyle(Theme.coral)
        .frame(width: 240, alignment: .leading)
    }
}
