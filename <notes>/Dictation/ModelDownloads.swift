import AppKit
import NotesSpeech

// Одно скачивание модели на всё приложение: его запускают и шаг 7 онбординга, и надиктовка,
// когда модели нет. Без общего места одна и та же модель могла качаться дважды в одну папку.
@Observable final class ModelDownloads {
    static let shared = ModelDownloads()

    // Доля скачанного, 0…1, для моделей, которые качаются прямо сейчас.
    private(set) var progress: [SpeechModel: Double] = [:]

    func isDownloading(_ model: SpeechModel) -> Bool { progress[model] != nil }

    // Повторный вызов для той же модели не начинает второе скачивание, а ждёт первое.
    func download(_ model: SpeechModel, onProgress: ((Double) -> Void)? = nil) async throws {
        // Уже скачанная — сразу 100 %. Раньше «готово» приходило отложенно, когда подписчиков
        // уже убрали, и на экране оставалось 0 %.
        if ModelStore.standard.isInstalled(model) {
            onProgress?(1)
            return
        }
        if let onProgress { watchers[model, default: []].append(onProgress) }
        if let running = tasks[model] { return try await running.value }
        progress[model] = 0
        let task = Task {
            defer {
                progress[model] = nil
                tasks[model] = nil
                watchers[model] = nil
            }
            try await ModelStore.standard.download(model) { value in
                Task { @MainActor in
                    let shared = ModelDownloads.shared
                    shared.progress[model] = value
                    shared.watchers[model]?.forEach { $0(value) }
                }
            }
            // Последнее «готово» — до того, как defer уберёт подписчиков.
            watchers[model]?.forEach { $0(1) }
        }
        tasks[model] = task
        try await task.value
    }

    private var tasks: [SpeechModel: Task<Void, Error>] = [:]
    private var watchers: [SpeechModel: [(Double) -> Void]] = [:]
}

// Надиктовку нажали, а модели нет. Выводим приложение вперёд и предлагаем скачать — системным окном:
// своего экрана для этого в макете пока нет (CLAUDE.md, п. 6). Тексты системных окон — обычным языком.
// Что бы ни ответили, возвращаем человека в приложение, из которого он нажал хоткей.
enum ModelDownloadOffer {
    static func present(_ model: SpeechModel, hotKey: String) {
        let origin = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        defer { goBack(to: origin) }

        let alert = NSAlert()
        if let value = ModelDownloads.shared.progress[model] {
            alert.messageText = "Модель ещё скачивается"
            alert.informativeText = "\(model.displayName): скачано \(Int(value * 100)) %. Как закончится, надиктовка заработает сама."
            alert.runModal()
            return
        }
        // Выбрана нескачанная модель, но другая уже лежит на диске — говорим об этом и даём взять её,
        // чтобы не качать сотни мегабайт ради того, что уже есть.
        let installed = SpeechModel.allCases.filter { $0 != model && ModelStore.standard.isInstalled($0) }
        alert.messageText = "Модель \(model.displayName) не скачана"
        var text = "Речь распознаётся прямо на этом Mac, для этого модель нужно один раз скачать — \(model.downloadMB) МБ. Потом интернет не понадобится."
        if !installed.isEmpty {
            let names = installed.map(\.displayName).joined(separator: ", ")
            text += "\n\nУже скачано: \(names). Можно надиктовывать ей прямо сейчас."
        }
        alert.informativeText = text
        alert.addButton(withTitle: "Скачать")
        if let ready = installed.first { alert.addButton(withTitle: "Взять \(ready.displayName)") }
        alert.addButton(withTitle: "Не сейчас")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            break
        case .alertSecondButtonReturn where !installed.isEmpty:
            SpeechSettings.model = installed[0]
            return
        default:
            return
        }

        // Качаем в фоне. Готово — сфера на секунду показывает галочку, окно не выскакивает:
        // человек уже вернулся к своей работе, выдёргивать его оттуда незачем.
        Task {
            do {
                try await ModelDownloads.shared.download(model)
                DictationController.shared.flashReady()
            } catch {
                let origin = NSWorkspace.shared.frontmostApplication
                NSApp.activate()
                let failed = NSAlert()
                failed.messageText = "Не получилось скачать модель"
                failed.informativeText = "Проверь интернет и нажми \(hotKey) ещё раз — предложим скачать заново."
                failed.runModal()
                goBack(to: origin)
            }
        }
    }

    private static func goBack(to app: NSRunningApplication?) {
        guard let app, app != NSRunningApplication.current else { return }
        app.activate()
    }
}
