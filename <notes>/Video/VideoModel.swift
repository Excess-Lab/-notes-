import AppKit
import AVFoundation
import NotesCore
import NotesSpeech

// Расшифровка видео и аудио: очередь файлов, распознавание по одному той же моделью, что надиктовка,
// результат — в Application Support (не в хранилище). В заметки — только по «сохранить как заметку».
@Observable final class VideoModel {
    enum Filter: String, CaseIterable {
        case all = "все расшифровки", working = "в работе", queued = "в очереди", done = "готово"
    }

    struct Item: Codable, Identifiable, Hashable {
        enum Status: String, Codable { case queued, working, done, failed }
        let id: UUID
        let name: String
        let bytes: Int64
        var duration: Double
        var status: Status
        var progress: Double
        let added: Date
        var words: Int
        // Папка расшифровки (ТЗ 30.10.2026). Нет — лежит в «без папки»; в старом index.json поля нет.
        var folder: String?
    }

    let library: NoteLibrary
    private(set) var items: [Item] = []
    var filter: Filter = .all
    // Выбранная папка в боковой панели; nil — все.
    var folderFilter: String?
    // Свои папки — список имён в настройках приложения; в хранилище это подпапки «расшифровки/».
    private(set) var folders: [String] = UserDefaults.standard.stringArray(forKey: "videoFolders") ?? []
    var open: UUID?
    private(set) var transcripts: [UUID: Transcript] = [:]
    // Файлы, которые человек выбрал или бросил в этом запуске: доступ к ним песочница даёт до выхода.
    private var sources: [UUID: URL] = [:]
    private var running = false

    private static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("transcripts", isDirectory: true)
    private static var indexURL: URL { folder.appendingPathComponent("index.json") }

    init(library: NoteLibrary) {
        self.library = library
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        items = (try? JSONDecoder().decode([Item].self, from: Data(contentsOf: Self.indexURL))) ?? []
        // Файл из прошлого запуска недоступен: песочница не помнит выбранные тогда файлы. Честно помечаем.
        for index in items.indices where items[index].status != .done { items[index].status = .failed }
        save()
    }

    var crumb: String {
        if let open, let item = items.first(where: { $0.id == open }) { return "видео / " + item.title }
        return "видео"
    }

    func count(_ filter: Filter) -> Int { items.filter { matches($0, filter) }.count }
    var visible: [Item] { items.filter { matches($0, filter) && (folderFilter == nil || $0.folder == folderFilter) } }

    func count(folder: String) -> Int { items.filter { $0.folder == folder }.count }

    func createFolder(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, !folders.contains(clean) else { return }
        folders.append(clean)
        UserDefaults.standard.set(folders, forKey: "videoFolders")
    }

    // Убрать папку: расшифровки остаются, просто без папки.
    func removeFolder(_ name: String) {
        folders.removeAll { $0 == name }
        UserDefaults.standard.set(folders, forKey: "videoFolders")
        for index in items.indices where items[index].folder == name { items[index].folder = nil }
        if folderFilter == name { folderFilter = nil }
        save()
    }

    func move(_ id: UUID, to folder: String?) {
        update(id) { $0.folder = folder }
        save()
    }

    private func matches(_ item: Item, _ filter: Filter) -> Bool {
        switch filter {
        case .all: true
        case .working: item.status == .working
        case .queued: item.status == .queued
        case .done: item.status == .done
        }
    }

    func transcript(_ id: UUID) -> Transcript? {
        if let cached = transcripts[id] { return cached }
        let loaded = try? JSONDecoder().decode(Transcript.self, from: Data(contentsOf: Self.folder.appendingPathComponent("\(id).json")))
        transcripts[id] = loaded
        return loaded
    }

    // MARK: - Очередь

    static let types = ["mp4", "mov", "m4v", "m4a", "m4b", "mp3", "wav", "aac", "aiff", "aif", "caf", "flac", "3gp"]

    func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.types.compactMap { .init(filenameExtension: $0) }
        panel.message = "Выбери видео или аудио — расшифровка пройдёт прямо на этом Mac."
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func add(_ urls: [URL]) {
        for url in urls where Self.types.contains(url.pathExtension.lowercased()) {
            let id = UUID()
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            sources[id] = url
            items.insert(Item(id: id, name: url.lastPathComponent, bytes: bytes, duration: 0, status: .queued,
                              progress: 0, added: Date(), words: 0), at: 0)
        }
        save()
        Task { await run() }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent("\(id).json"))
        if open == id { open = nil }
        save()
    }

    private func run() async {
        guard !running else { return }
        let model = SpeechSettings.model
        guard ModelStore.standard.isInstalled(model) else {
            ModelDownloadOffer.present(model, hotKey: DictationController.shared.combo.display)
            return
        }
        running = true
        defer { running = false }
        while let index = items.firstIndex(where: { $0.status == .queued }) {
            let id = items[index].id
            guard let url = sources[id] else { update(id) { $0.status = .failed }; continue }
            update(id) { $0.status = .working; $0.progress = 0 }
            do {
                let engine = try await Transcribers.make(model)
                let pieces = try await MediaTranscription.transcribe(url: url, engine: engine) { [model = self] progress, duration in
                    Task { @MainActor in model.update(id) { $0.progress = progress; $0.duration = duration } }
                }
                let transcript = Transcript(segments: pieces.map { .init(start: $0.start, end: $0.end, text: $0.text) })
                try JSONEncoder().encode(transcript).write(to: Self.folder.appendingPathComponent("\(id).json"))
                transcripts[id] = transcript
                update(id) { $0.status = .done; $0.progress = 1; $0.words = transcript.wordCount }
                // Расшифровка сразу ложится заметкой в хранилище: «расшифровки/<имя>.md» с метаданными.
                _ = writeNote(id)
            } catch {
                update(id) { $0.status = .failed }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        save()
    }

    private func save() {
        try? JSONEncoder().encode(items).write(to: Self.indexURL)
    }

    // MARK: - Действия с готовой расшифровкой

    // Заметка расшифровки: если уже есть — открываем её, а не плодим копию.
    func saveAsNote(_ id: UUID) -> URL? { writeNote(id) }

    private func writeNote(_ id: UUID) -> URL? {
        guard let item = items.first(where: { $0.id == id }), let transcript = transcript(id) else { return nil }
        var folder = library.root.appendingPathComponent("расшифровки", isDirectory: true)
        if let name = item.folder { folder = folder.appendingPathComponent(name, isDirectory: true) }
        let url = folder.appendingPathComponent(item.title + ".md")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? library.write(transcript.note(title: item.title, source: item.name, added: item.added,
                                           duration: item.duration, model: SpeechSettings.model.displayName), to: url)
        return url
    }

    func copy(_ id: UUID) {
        guard let transcript = transcript(id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript.text, forType: .string)
    }

    func exportSRT(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), let transcript = transcript(id) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.title + ".srt"
        panel.message = "Куда сохранить субтитры?"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? transcript.srt.write(to: url, atomically: true, encoding: .utf8)
    }
}

extension VideoModel.Item {
    // Имя файла без расширения — так и в заголовке, и в названии заметки.
    var title: String { (name as NSString).deletingPathExtension }
}

#if DEBUG
extension VideoModel {
    // Живая проверка расшифровки: речь синтезирует сам Mac в файл внутри контейнера (песочница его пускает),
    // дальше — весь путь: очередь, нарезка, распознавание выбранной моделью.
    func selfTest(_ log: @escaping (String, Bool) -> Void) async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("проверка расшифровки.caf")
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "Привет. Это проверка расшифровки видео. Синхронизацию делаем через гит раз в час.")
        utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        var file: AVAudioFile?
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            var finished = false
            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    if !finished { finished = true; done.resume() }
                    return
                }
                if file == nil { file = try? AVAudioFile(forWriting: url, settings: pcm.format.settings) }
                try? file?.write(from: pcm)
            }
        }
        file = nil
        log("речь записана в файл", FileManager.default.fileExists(atPath: url.path))
        add([url])
        for _ in 0..<120 {
            if let item = items.first(where: { $0.name == url.lastPathComponent }), item.status == .done || item.status == .failed { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard let item = items.first(where: { $0.name == url.lastPathComponent }) else { return log("файл не попал в очередь", false) }
        let text = transcript(item.id)?.text ?? ""
        log("расшифровано: «\(text)»", item.status == .done && text.lowercased().contains("расшифров"))
        log("метки времени есть", (transcript(item.id)?.segments.first?.start ?? -1) == 0)
        let note = library.root.appendingPathComponent("расшифровки/\(item.title).md")
        let saved = (try? String(contentsOf: note, encoding: .utf8)) ?? ""
        log("заметка в хранилище с метаданными", saved.hasPrefix("---\nисточник: ") && saved.contains("модель: "))
        // Папки: создать, переложить, показать только её, заметка — в подпапку; удалить — расшифровка остаётся.
        let folder = "проверка папки \(UUID().uuidString.prefix(4))"
        createFolder(folder)
        move(item.id, to: folder)
        folderFilter = folder
        log("папка: расшифровка переложена и видна в ней", visible.map(\.id) == [item.id] && count(folder: folder) == 1)
        let inFolder = saveAsNote(item.id)
        log("заметка из папки — в «расшифровки/\(folder)/»", inFolder?.deletingLastPathComponent().lastPathComponent == folder)
        if let inFolder { try? FileManager.default.removeItem(at: inFolder.deletingLastPathComponent()) }
        removeFolder(folder)
        log("папка удалена, расшифровка осталась без папки",
            !folders.contains(folder) && folderFilter == nil && items.first { $0.id == item.id }?.folder == nil)
        remove(item.id)
    }
}
#endif
