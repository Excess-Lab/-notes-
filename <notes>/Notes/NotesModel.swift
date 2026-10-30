import AppKit
import NotesCore
import SwiftUI

// Состояние главного экрана: что выбрано, текст открытой заметки, поиск. Файлы читает и пишет
// NotesCore.NoteLibrary; здесь — только то, что нужно экрану, и автосохранение.
@Observable final class NotesModel {
    enum Selection: Hashable {
        case folder(URL)   // корень хранилища — тоже папка: «все заметки»
        case note(URL)
    }

    let library: NoteLibrary
    private(set) var tree: NoteLibrary.Folder
    var selection: Selection
    var expanded: Set<URL> = []

    // Открытая заметка: текст, как он сейчас в редакторе.
    var text = "" { didSet { if text != savedText { scheduleSave() } } }
    private var savedText = ""
    // Номер последней правки: запись через полсекунды делает только последняя из них.
    private var editGeneration = 0

    // Раздел окна: шапка переключает заметки, задачи, календарь и видео; настройки — по ⌘,.
    enum Section: Hashable { case notes, tasks, calendar, video, settings }
    var section: Section = .notes
    let tasks: TasksModel
    let video: VideoModel

    enum SettingsPage: String, CaseIterable {
        case sync = "синхронизация", dictation = "надиктовка", search = "поиск", lock = "вход", calendar = "календарь"
        var glyph: DotGlyph {
            switch self {
            case .sync: .git
            case .dictation: .microphone
            case .search: .search
            case .lock: .check
            case .calendar: .calendar
            }
        }
    }
    var settingsPage: SettingsPage = .sync

    // Поиск по смыслу: встроенная модель Apple + индекс в Application Support (кэш, не в хранилище).
    private(set) var indexReady = false
    // Поиск по смыслу — бета, включается в настройках → поиск (30.10.2026). Выключен — индекс не строим.
    static let semanticKey = "semanticSearch"
    var semanticOn: Bool { UserDefaults.standard.bool(forKey: Self.semanticKey) }
    private let embedder = AppleEmbedder()
    private let index = SemanticIndex(store: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("semantic-index.json"))

    var searchShown = false
    // Окно пинкода из настроек («задать» / «сменить»).
    var pinEntryShown = false
    var query = "" { didSet { runSearch() } }
    private(set) var hits: [NoteLibrary.Hit] = []
    var highlighted = 0

    private var watcher: FolderWatcher?
    private var observer: NSObjectProtocol?
    nonisolated private static let changed = Notification.Name("notes.vaultChanged")

    init(vault: URL) {
        library = NoteLibrary(root: vault)
        tree = library.tree()
        selection = .folder(library.root)
        tasks = TasksModel(library: library)
        defer { refreshIndex() }
        video = VideoModel(library: library)
        // Слежка идёт не на главном потоке: оттуда только сигнал, а разбираемся уже на главном.
        watcher = FolderWatcher(folder: vault) {
            NotificationCenter.default.post(name: NotesModel.changed, object: nil)
        }
        observer = NotificationCenter.default.addObserver(forName: Self.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.externalChange() }
        }
    }

    // MARK: - Выбор

    var currentFolder: NoteLibrary.Folder {
        switch selection {
        case .folder(let url): find(url, in: tree) ?? tree
        case .note(let url): find(url.deletingLastPathComponent(), in: tree) ?? tree
        }
    }

    var openNote: URL? {
        if case .note(let url) = selection { url } else { nil }
    }

    func open(_ selection: Selection) {
        flush()
        section = .notes
        self.selection = selection
        if case .note(let url) = selection {
            let loaded = (try? library.read(url)) ?? ""
            savedText = loaded
            text = loaded
            // Папки на пути к заметке раскрыты — видно, где она лежит.
            var folder = url.deletingLastPathComponent().standardizedFileURL
            while folder.path.count > library.root.path.count {
                expanded.insert(folder)
                folder = folder.deletingLastPathComponent().standardizedFileURL
            }
        }
    }

    func toggle(_ folder: URL) {
        if expanded.contains(folder) { expanded.remove(folder) } else { expanded.insert(folder) }
    }

    // «проекты / план приложения»; на корне — «все заметки».
    var breadcrumb: String {
        switch selection {
        case .folder(let url) where url.standardizedFileURL == library.root: "все заметки"
        case .folder(let url), .note(let url): library.breadcrumb(for: url).joined(separator: " / ")
        }
    }

    // MARK: - Действия

    func newNote() {
        guard let url = try? library.createNote(in: currentFolder.url) else { return NSSound.beep() }
        reloadTree()
        open(.note(url))
    }

    func newFolder(named name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = try? library.createFolder(in: currentFolder.url, name: name) else { return }
        reloadTree()
        open(.folder(url))
    }

    func rename(to title: String) {
        guard let url = openNote else { return }
        flush()
        guard let renamed = try? library.rename(url, to: title), renamed != url else { return }
        reloadTree()
        selection = .note(renamed)
    }

    // MARK: - Сохранение

    // Пишем через полсекунды после последней правки: на каждую букву диск дёргать незачем,
    // а потерять можно максимум полсекунды текста. Git-коммит — раз в час, отдельно (SyncController).
    private func scheduleSave() {
        editGeneration += 1
        let generation = editGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.editGeneration == generation else { return }
                self.flush()
            }
        }
    }

    func flush() {
        guard let url = openNote, text != savedText else { return }
        do {
            try library.write(text, to: url)
            savedText = text
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // Файлы поменяли снаружи (другой редактор, pull с другого Mac): обновляем дерево, а открытую
    // заметку перечитываем, только если в ней нет несохранённых правок.
    private func externalChange() {
        reloadTree()
        tasks.reload()
        refreshIndex()
        guard let url = openNote, text == savedText else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return open(.folder(library.root)) }
        if let disk = try? library.read(url), disk != savedText {
            savedText = disk
            text = disk
        }
    }

    private func reloadTree() { tree = library.tree() }

    private func find(_ url: URL, in folder: NoteLibrary.Folder) -> NoteLibrary.Folder? {
        if folder.url.standardizedFileURL == url.standardizedFileURL { return folder }
        for child in folder.folders { if let hit = find(url, in: child) { return hit } }
        return nil
    }

    // MARK: - Поиск

    // Смесь: по смыслу (модель Apple) + по словам. Где совпали слова — выше; найденное только словами
    // не теряем. Пока индекс собирается — только по словам. Решение Макара: «делаем микс» (30.10.2026).
    private func runSearch() {
        let words = library.search(query, limit: 20)
        guard semanticOn, indexReady, let embedder else { hits = Array(words.prefix(8)); highlighted = 0; return }
        let notes = Dictionary(library.allNotes(in: tree).map { ($0.url.standardizedFileURL, $0) }, uniquingKeysWith: { a, _ in a })
        var merged: [URL: NoteLibrary.Hit] = [:]
        for hit in index.search(query, embedder: embedder, limit: 12) {
            let url = hit.note.standardizedFileURL
            if let note = notes[url] { merged[url] = NoteLibrary.Hit(note: note, snippet: hit.snippet, score: hit.score) }
        }
        for (rank, hit) in words.enumerated() {
            let url = hit.note.url.standardizedFileURL
            let bonus = 0.3 - Double(min(rank, 10)) * 0.01
            merged[url] = NoteLibrary.Hit(note: hit.note, snippet: hit.snippet, score: (merged[url]?.score ?? 0) + 1 + bonus)
        }
        hits = Array(merged.values.sorted { $0.score > $1.score }.prefix(8))
        highlighted = 0
    }

    // Индекс — в фоне: модель считает векторы только для новых и изменённых заметок.
    // Одно обновление за раз: раньше каждое изменение папки запускало своё, и они дёргали модель
    // одновременно — приложение зависало. Пришли правки посреди обновления — ещё один проход после.
    private var indexing = false
    private var indexAgain = false

    func refreshIndex() {
        guard semanticOn, let embedder else { return }
        guard !indexing else { indexAgain = true; return }
        indexing = true
        let library = library, index = index
        Task {
            await Task.detached(priority: .utility) {
                try? await embedder.prepare()
                index.update(library: library, embedder: embedder)
            }.value
            indexReady = true
            indexing = false
            if indexAgain { indexAgain = false; refreshIndex() }
        }
    }

    func openHighlighted() {
        guard hits.indices.contains(highlighted) else { return }
        open(.note(hits[highlighted].note.url))
        searchShown = false
    }
}

#if DEBUG
extension NotesModel {
    // `--args -testVault YES -notesSelfTest YES`, запуск бинарника из терминала: проходит по действиям
    // экрана на тестовой папке и печатает «ok / FAIL» по каждому. Кликать скриптом macOS не даёт.
    func selfTest() async {
        func check(_ name: String, _ ok: Bool) { FileHandle.standardError.write(Data(((ok ? "ok   " : "FAIL ") + name + "\n").utf8)) }
        check("самопроверка началась", true)
        let fm = FileManager.default

        open(.folder(library.root))
        newNote()
        let created = openNote
        check("новая заметка создана и открыта", created.map { fm.fileExists(atPath: $0.path) } ?? false)

        text = "# Заголовок\nпервая строка"
        try? await Task.sleep(for: .milliseconds(800))
        let disk = created.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        check("текст сохранился сам через полсекунды", disk == text)

        rename(to: "проверка")
        check("переименование меняет файл", openNote?.lastPathComponent == "проверка.md"
              && openNote.map { fm.fileExists(atPath: $0.path) } == true)

        newFolder(named: "новая")
        check("новая папка создана и открыта", fm.fileExists(atPath: library.root.appendingPathComponent("новая").path)
              && currentFolder.name == "новая")

        query = "первая"
        check("поиск находит новую заметку", hits.first?.note.title == "проверка")

        // Правка снаружи: другой редактор пишет в открытую заметку — экран подхватывает.
        open(.note(library.root.appendingPathComponent("проверка.md")))
        try? "снаружи".write(to: library.root.appendingPathComponent("проверка.md"), atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .seconds(2))
        check("правка снаружи подхватилась", text == "снаружи")

        tasks.reload()
        check("задачи собраны из заметок (6)", tasks.tasks.count == 6)
        check("группы: сегодня 2, неделя 2, без даты 1, готово 1",
              tasks.count(.today) == 2 && tasks.count(.week) == 2 && tasks.count(.noDate) == 1 && tasks.count(.done) == 1)
        if let bread = tasks.tasks.first(where: { $0.title == "Купить хлеб" }) {
            tasks.toggle(bread)
            let disk = (try? String(contentsOf: bread.note, encoding: .utf8)) ?? ""
            check("отметка «готово» записалась в файл", disk.contains("- [x] Купить хлеб"))
        }
        if UserDefaults.standard.bool(forKey: "liveSelfTest") {
            CalendarSync.shared.selfTest(check)
            CalendarSync.shared.removalSelfTest(check)
            await video.selfTest(check)
        }
        exit(0)
    }
}
#endif
