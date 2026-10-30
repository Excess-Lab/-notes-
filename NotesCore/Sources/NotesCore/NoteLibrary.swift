import Foundation

// Заметки в папке хранилища — то, что показывает главный экран: дерево папок, заметки, счётчики,
// поиск по тексту. Источник правды — файлы: здесь только чтение и запись `.md`, своей базы нет.
// Служебное (`.git`, скрытые папки других программ) не показываем и не трогаем.
public struct NoteLibrary: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root.standardizedFileURL }

    public struct Note: Hashable, Sendable, Identifiable {
        public let url: URL
        public let modified: Date
        public var id: URL { url }
        public var title: String { url.deletingPathExtension().lastPathComponent }
    }

    public struct Folder: Hashable, Sendable, Identifiable {
        public let url: URL
        public let folders: [Folder]
        public let notes: [Note]
        public var id: URL { url }
        public var name: String { url.lastPathComponent }
        // Сколько заметок внутри, со вложенными — «12 заметок» под карточкой папки.
        public var noteCount: Int { notes.count + folders.reduce(0) { $0 + $1.noteCount } }
    }

    // Дерево хранилища. Скрытые файлы и папки (`.git`, `.obsidian`-подобные) пропускаем,
    // заметки — только `.md`. Порядок — по имени, как в Finder.
    public func tree() -> Folder { folder(at: root) }

    private func folder(at url: URL) -> Folder {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .isHiddenKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles])) ?? []
        var folders: [Folder] = []
        var notes: [Note] = []
        for item in items {
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                folders.append(folder(at: item))
            } else if item.pathExtension.lowercased() == "md" {
                notes.append(Note(url: item, modified: values?.contentModificationDate ?? .distantPast))
            }
        }
        let byName: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }
        return Folder(url: url, folders: folders.sorted { byName($0.name, $1.name) },
                      notes: notes.sorted { byName($0.title, $1.title) })
    }

    // «проекты / план приложения» — путь заметки от корня хранилища, без расширения.
    public func breadcrumb(for url: URL) -> [String] {
        let relative = url.standardizedFileURL.path.dropFirst(root.path.count)
        return relative.split(separator: "/").map(String.init).enumerated().map { index, part in
            index == relative.split(separator: "/").count - 1 && part.hasSuffix(".md") ? String(part.dropLast(3)) : part
        }
    }

    public func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    // Текст для поиска и задач: с диска — только если файл поменялся. Раньше каждое изменение в папке
    // и каждая буква в поиске перечитывали все заметки целиком.
    public func text(of note: Note) -> String? {
        if let hit = TextCache.shared.get(note.url, modified: note.modified) { return hit }
        guard let text = try? read(note.url) else { return nil }
        TextCache.shared.set(note.url, modified: note.modified, text: text)
        return text
    }

    // Пишем атомарно: при сбое посреди записи на диске остаётся старая версия, а не половина заметки.
    public func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // Новая заметка «без названия», «без названия 2»… — чтобы не перезаписать существующую.
    public func createNote(in folder: URL, title: String = "без названия") throws -> URL {
        let url = free(name: title, ext: "md", in: folder)
        try "".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func createFolder(in parent: URL, name: String) throws -> URL {
        let url = free(name: name, ext: nil, in: parent)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    // Переименование заметки. Пустое имя и «/» не принимаем: это сломало бы путь.
    public func rename(_ url: URL, to title: String) throws -> URL {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, clean != url.deletingPathExtension().lastPathComponent else { return url }
        let target = free(name: clean, ext: url.pathExtension.isEmpty ? nil : url.pathExtension,
                          in: url.deletingLastPathComponent())
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    private func free(name: String, ext: String?, in folder: URL) -> URL {
        var index = 1
        while true {
            let base = index == 1 ? name : "\(name) \(index)"
            let url = ext.map { folder.appendingPathComponent(base).appendingPathExtension($0) }
                ?? folder.appendingPathComponent(base, isDirectory: true)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }

    // MARK: - Поиск по тексту

    public struct Hit: Hashable, Sendable, Identifiable {
        public let note: Note
        public let snippet: String
        public let score: Double
        public var id: URL { note.url }
    }

    // Все слова запроса должны встретиться в заметке (без учёта регистра и ё/е).
    // Совпадение в названии весит больше, чем в тексте. Отрывок — строка, где нашлось первое слово.
    public func search(_ query: String, limit: Int = 20) -> [Hit] {
        let words = Self.normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var hits: [Hit] = []
        for note in allNotes(in: tree()) {
            guard let text = text(of: note) else { continue }
            let title = Self.normalize(note.title)
            let body = Self.normalize(text)
            guard words.allSatisfy({ title.contains($0) || body.contains($0) }) else { continue }
            let inTitle = Double(words.filter { title.contains($0) }.count)
            let inBody = words.reduce(0.0) { $0 + Double(body.components(separatedBy: $1).count - 1) }
            hits.append(Hit(note: note, snippet: Self.snippet(text, word: words[0]), score: inTitle * 3 + min(inBody, 10)))
        }
        return Array(hits.sorted { $0.score == $1.score ? $0.note.modified > $1.note.modified : $0.score > $1.score }
            .prefix(limit))
    }

    public func allNotes(in folder: Folder) -> [Note] {
        folder.notes + folder.folders.flatMap { allNotes(in: $0) }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    static func snippet(_ text: String, word: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let line = lines.first { normalize($0).contains(word) && !$0.hasPrefix("#") } ?? lines.first { !$0.isEmpty } ?? ""
        // Разметку списка и задач («- [ ] », «📅») в отрывке не показываем — только сам текст.
        var clean = String(line.drop { $0 == "#" || $0 == " " || $0 == "-" || $0 == "—" || $0 == "*" })
        for mark in ["[ ] ", "[x] ", "[X] "] where clean.hasPrefix(mark) { clean.removeFirst(mark.count) }
        if let date = clean.range(of: "📅") { clean = String(clean[..<date.lowerBound]).trimmingCharacters(in: .whitespaces) }
        return String(clean.prefix(140))
    }

    // «312 слов» под заголовком заметки.
    public static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.filter { $0.contains { $0.isLetter || $0.isNumber } }.count
    }
}

final class TextCache: @unchecked Sendable {
    static let shared = TextCache()
    private var items: [URL: (Date, String)] = [:]
    private let lock = NSLock()

    func get(_ url: URL, modified: Date) -> String? {
        lock.withLock { items[url].flatMap { $0.0 == modified ? $0.1 : nil } }
    }

    func set(_ url: URL, modified: Date, text: String) {
        lock.withLock { items[url] = (modified, text) }
    }
}
