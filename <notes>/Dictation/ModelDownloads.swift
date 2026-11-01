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

    // Модели голосов для спикеров — отдельно от моделей речи: их не выбирают, а включают.
    private(set) var speakers: Double?

    func downloadSpeakers() async throws {
        guard speakers == nil, !Diarization.isInstalled() else { return }
        speakers = 0
        defer { speakers = nil }
        try await Diarization.download { value in Task { @MainActor in ModelDownloads.shared.speakers = value < 1 ? value : nil } }
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
            alert.messageText = String(localized: "Модель ещё скачивается")
            alert.informativeText = String(localized: "\(model.displayName): скачано \(Int(value * 100)) %. Как закончится, надиктовка заработает сама.")
            alert.runModal()
            return
        }
        // Выбрана нескачанная модель, но другая уже лежит на диске — говорим об этом и даём взять её,
        // чтобы не качать сотни мегабайт ради того, что уже есть.
        let installed = SpeechModel.allCases.filter { $0 != model && ModelStore.standard.isInstalled($0) }
        alert.messageText = String(localized: "Модель \(model.displayName) не скачана")
        var text = String(localized: "Речь распознаётся прямо на этом Mac, модель скачивается один раз, \(model.downloadMB) МБ.")
        if !installed.isEmpty {
            let names = installed.map(\.displayName).joined(separator: ", ")
            text += String(localized: "\n\nУже скачано: \(names). Можно надиктовывать ей прямо сейчас.")
        }
        alert.informativeText = text
        alert.addButton(withTitle: String(localized: "Скачать"))
        if let ready = installed.first { alert.addButton(withTitle: String(localized: "Взять \(ready.displayName)")) }
        alert.addButton(withTitle: String(localized: "Не сейчас"))
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
                failed.messageText = String(localized: "Не получилось скачать модель")
                failed.informativeText = String(localized: "Проверь интернет и нажми \(hotKey) ещё раз.")
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
