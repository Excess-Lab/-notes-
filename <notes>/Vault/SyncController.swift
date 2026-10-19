import Foundation
import NotesCore
import os

// Фоновая синхронизация хранилища: раз в час коммитим всё, что накопилось (кто бы ни правил —
// мы, Obsidian или Finder), и проверяем, не пора ли отправлять на GitHub (раз в сутки).
// Логика — в NotesCore.SyncEngine.
@Observable
final class SyncController {
    static let shared = SyncController()

    // Коммит раз в час, а не на каждую паузу в правках: история читается по часам, а не по словам.
    static let commitInterval: Duration = .seconds(3600)

    private static let lastPushKey = "lastPush"
    private let log = Logger(subsystem: "notes", category: "sync")
    private var engine: SyncEngine?
    private var loop: Task<Void, Never>?

    // Запускаем, только если папка уже git-репозиторий: без «инициализировать» историю не ведём.
    func start(vault: URL) {
        guard engine == nil, GitVault.isRepository(vault) else { return }
        let engine = SyncEngine(folder: vault)
        self.engine = engine
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.commitInterval)
                await self?.tick()
            }
        }
        log.info("синхронизация запущена: \(vault.path, privacy: .private)")
    }

    private func tick() async {
        guard let engine else { return }
        do {
            if let message = try await engine.commitNow() {
                log.info("коммит: \(message, privacy: .private)")
            }
        } catch {
            log.error("не закоммитили: \(String(describing: error), privacy: .public)")
        }
        await pushIfDue()
    }

    // Первую отправку делает вход в GitHub — с неё и отсчитываем сутки.
    static func markPushed(_ date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastPushKey)
    }

    private func pushIfDue() async {
        // Без входа в GitHub токена нет — история остаётся на этом Маке.
        guard let engine, let token = TokenStore().load() else { return }
        let lastPush = UserDefaults.standard.object(forKey: Self.lastPushKey) as? Date
        do {
            if try await engine.pushIfDue(token: token, lastPush: lastPush) {
                Self.markPushed()
                log.info("история отправлена на github")
            }
        } catch {
            log.error("не отправили на github: \(String(describing: error), privacy: .public)")
        }
    }
}
