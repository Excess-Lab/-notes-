import Foundation

// Разделы, которые дописывает Apple Intelligence по кнопке: «## Кратко» сразу под заголовком заметки
// и «## Задачи» в конце. Повторное нажатие заменяет свой раздел, а не плодит второй.
public enum NoteSections {
    // Кратко — после frontmatter и первого заголовка «# …»; нет заголовка — в самое начало.
    public static func setSummary(_ summary: String, in text: String) -> String {
        var lines = remove("Кратко", from: text, upToBlank: true).components(separatedBy: "\n")
        var at = 0
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { at = end + 1 }
        while at < lines.count, lines[at].trimmingCharacters(in: .whitespaces).isEmpty { at += 1 }
        if at < lines.count, lines[at].hasPrefix("# ") { at += 1 } else if at == lines.count { at = lines.count }
        let block = ["", "## Кратко", "", summary.trimmingCharacters(in: .whitespacesAndNewlines), ""]
        lines.insert(contentsOf: block, at: at)
        return lines.joined(separator: "\n").replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    // Задачи строками «- [ ] что 📅 2026-11-03» — дальше их подхватывают список задач и календарь.
    public static func setTasks(_ tasks: [(title: String, date: String?)], in text: String) -> String {
        guard !tasks.isEmpty else { return text }
        let body = remove("Задачи", from: text).trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = tasks.map { "- [ ] \($0.title)" + ($0.date.map { " 📅 \($0)" } ?? "") }
        return body + "\n\n## Задачи\n\n" + lines.joined(separator: "\n") + "\n"
    }

    // Свой раздел: от «## Имя» до следующего заголовка. «Кратко» стоит над текстом заметки без своего
    // заголовка, поэтому он кончается первой пустой строкой после пунктов — дальше уже текст человека.
    public static func remove(_ name: String, from text: String, upToBlank: Bool = false) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "## \(name)") else { return text }
        var end = start + 1
        var content = false
        while end < lines.count, !(lines[end].hasPrefix("## ") || lines[end].hasPrefix("# ")) {
            let blank = lines[end].trimmingCharacters(in: .whitespaces).isEmpty
            if upToBlank, blank, content { end += 1; break }
            content = content || !blank
            end += 1
        }
        lines.removeSubrange(start..<end)
        return lines.joined(separator: "\n")
    }
}
