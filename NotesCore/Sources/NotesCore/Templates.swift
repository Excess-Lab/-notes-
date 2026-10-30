import Foundation

// Шаблоны заметок — обычные .md в папке «шаблоны» хранилища: их видно и правят где угодно.
// Подстановки: {{дата}} — 2026-10-31, {{время}} — 15:30, {{название}} — имя новой заметки.
// Заметка на каждый день — в папке «дневник», имя — дата, текст — из шаблона «день», если он есть (ТЗ 30.10.2026).
public enum Templates {
    public static let folder = "шаблоны"
    public static let dailyFolder = "дневник"
    public static let dailyTemplate = "день"

    public static func apply(_ text: String, title: String, date: Date = Date()) -> String {
        text.replacingOccurrences(of: "{{дата}}", with: day(date))
            .replacingOccurrences(of: "{{время}}", with: time(date))
            .replacingOccurrences(of: "{{название}}", with: title)
    }

    public static func day(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func time(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    public static func list(in library: NoteLibrary) -> [URL] {
        let dir = library.root.appendingPathComponent(folder, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // Новая заметка из шаблона: имя — имя шаблона (занято — с номером), подстановки заполнены.
    public static func create(from template: URL, in folder: URL, library: NoteLibrary, date: Date = Date()) throws -> URL {
        let url = try library.createNote(in: folder, title: template.deletingPathExtension().lastPathComponent)
        let title = url.deletingPathExtension().lastPathComponent
        try apply(try String(contentsOf: template, encoding: .utf8), title: title, date: date)
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // Заметка дня: есть — возвращаем как есть, нет — создаём. Чужой файл с таким именем не трогаем.
    public static func daily(in library: NoteLibrary, date: Date = Date()) throws -> URL {
        let dir = library.root.appendingPathComponent(dailyFolder, isDirectory: true)
        let url = dir.appendingPathComponent(day(date) + ".md")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let template = library.root.appendingPathComponent(folder).appendingPathComponent(dailyTemplate + ".md")
        let text = (try? String(contentsOf: template, encoding: .utf8)) ?? "# {{дата}}\n\n"
        try apply(text, title: day(date), date: date).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
