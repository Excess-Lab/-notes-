import AppKit
import NotesCore
import SwiftUI

// Действия с заметками и папками из контекстного меню боковой панели: закрепить, копировать, вставить,
// дублировать, показать в Finder, удалить. Удаление — в Корзину (вернуть можно), закреплённые — настройка
// приложения, в хранилище не пишем (CLAUDE.md: только то, что меняет человек).
extension NotesModel {
    private static let pinsKey = "pinnedNotes"

    private func relative(_ url: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(library.root.standardizedFileURL.path.count))
    }

    var pinned: [URL] {
        let _ = tree
        return (UserDefaults.standard.stringArray(forKey: Self.pinsKey) ?? [])
            .map { library.root.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func isPinned(_ url: URL) -> Bool { pinned.contains { $0.standardizedFileURL == url.standardizedFileURL } }

    func togglePin(_ url: URL) {
        var pins = UserDefaults.standard.stringArray(forKey: Self.pinsKey) ?? []
        let key = relative(url)
        if let i = pins.firstIndex(of: key) { pins.remove(at: i) } else { pins.insert(key, at: 0) }
        UserDefaults.standard.set(pins, forKey: Self.pinsKey)
        reloadTree()
    }

    func trash(_ url: URL) {
        flush()
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        let gone = url.standardizedFileURL.path
        switch selection {
        case .note(let open) where open.standardizedFileURL.path.hasPrefix(gone),
             .folder(let open) where open.standardizedFileURL.path.hasPrefix(gone):
            self.open(.folder(url.deletingLastPathComponent()))
        default: break
        }
        reloadTree()
    }

    // Копировать: в буфер кладём сам файл (вставить в Finder или в другую папку) и текст (вставить в любой редактор).
    func copy(_ url: URL) {
        flush()
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([url as NSURL])
        if let text = try? String(contentsOf: url, encoding: .utf8) { board.setString(text, forType: .string) }
    }

    var canPaste: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    // Вставить в папку файлы из буфера; при совпадении имени — «копия».
    func paste(into folder: URL) {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        for url in urls { copyFile(url, into: folder) }
        reloadTree()
    }

    func duplicate(_ url: URL) {
        flush()
        copyFile(url, into: url.deletingLastPathComponent())
        reloadTree()
    }

    private func copyFile(_ url: URL, into folder: URL) {
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var target = folder.appendingPathComponent(url.lastPathComponent)
        var n = 1
        while FileManager.default.fileExists(atPath: target.path) {
            let name = n == 1 ? "\(base) копия" : "\(base) копия \(n)"
            target = folder.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
            n += 1
        }
        do { try FileManager.default.copyItem(at: url, to: target) } catch { NSAlert(error: error).runModal() }
    }

    // Перетаскивание в боковой панели, как в Finder: своё — переносим, файлы из Finder — копируем внутрь.
    // Папку в саму себя или в свою подпапку не кладём; занятое имя — «2», «3».
    @discardableResult
    func drop(_ urls: [URL], into folder: URL) -> Bool {
        flush()
        let root = library.root.standardizedFileURL.path
        var moved = false
        for url in urls {
            let source = url.standardizedFileURL
            guard source.path.hasPrefix(root + "/") else { copyFile(url, into: folder); moved = true; continue }
            let target = folder.standardizedFileURL
            guard source.deletingLastPathComponent() != target,
                  !(target.path + "/").hasPrefix(source.path + "/") else { continue }
            let ext = source.pathExtension, base = source.deletingPathExtension().lastPathComponent
            var destination = target.appendingPathComponent(source.lastPathComponent)
            var n = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                destination = target.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
                n += 1
            }
            do { try FileManager.default.moveItem(at: source, to: destination) } catch { NSAlert(error: error).runModal(); continue }
            moved = true
            // Открытая заметка уехала вместе с файлом или папкой — открываем её на новом месте.
            if let open = openNote?.standardizedFileURL, open.path.hasPrefix(source.path) {
                self.open(.note(URL(fileURLWithPath: destination.path + open.path.dropFirst(source.path.count))))
            }
        }
        if moved { reloadTree(); tasks.reload() }
        return moved
    }
}

// Меню строки боковой панели. Для папки — ещё «вставить сюда».
struct NoteMenu: View {
    let model: NotesModel
    let url: URL
    var folder = false

    var body: some View {
        if !folder {
            Button(model.isPinned(url) ? "Открепить" : "Закрепить") { model.togglePin(url) }
        }
        Button("Копировать") { model.copy(url) }
        if folder {
            Button("Вставить сюда") { model.paste(into: url) }.disabled(!model.canPaste)
            Menu("Новая из шаблона") { TemplateItems(model: model, folder: url) }
        }
        Button("Дублировать") { model.duplicate(url) }
        Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Divider()
        Button("Удалить", role: .destructive) { model.trash(url) }
    }
}

// Шаблоны из папки «шаблоны» пунктами меню; пусто — подсказка, где их взять.
struct TemplateItems: View {
    let model: NotesModel
    let folder: URL?

    var body: some View {
        let templates = Templates.list(in: model.library)
        if templates.isEmpty {
            Button("Шаблонов нет — настройки → шаблоны") { model.flush(); model.settingsPage = .templates; model.section = .settings }
        }
        ForEach(templates, id: \.self) { url in
            Button(url.deletingPathExtension().lastPathComponent) { model.newNote(from: url, in: folder) }
        }
    }
}
