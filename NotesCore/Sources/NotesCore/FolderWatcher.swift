import CoreServices
import Foundation

// Следит за папкой хранилища через FSEvents — системные уведомления macOS «в папке что-то изменилось».
// Веб-аналог — вебхук. Правки в .git (наши же коммиты) пропускаем, иначе коммит будил бы сам себя.
// Автокоммиту он не нужен (коммит раз в час по таймеру) — пригодится поиску: переиндексировать
// изменённые заметки.
public final class FolderWatcher {
    private var stream: FSEventStreamRef?
    // Пути изменённых файлов (без .git): по ним приложение отличает своё сохранение от правки снаружи.
    private let onChange: @Sendable ([String]) -> Void

    public init(folder: URL, onChange: @escaping @Sendable ([String]) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let changed = list.prefix(count).filter { !FolderWatcher.isInternal($0) }
            if !changed.isEmpty { watcher.onChange(Array(changed)) }
        }
        stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "notes.folder-watcher"))
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    static func isInternal(_ path: String) -> Bool {
        path.contains("/.git/") || path.hasSuffix("/.git")
    }
}
