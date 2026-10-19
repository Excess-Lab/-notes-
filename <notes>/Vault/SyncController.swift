import Foundation
import NotesCore
import os

// Фоновая синхронизация хранилища. Раз в час (и сразу при запуске):
// 1) коммитим всё, что накопилось — кто бы ни правил: мы, другой редактор или Finder;
// 2) забираем правки с другого Мака (pull); конфликты не теряют текст — см. GitVault+Pull;
// 3) отправляем на GitHub, если прошли сутки с прошлой отправки.
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
                await self?.tick()
                try? await Task.sleep(for: Self.commitInterval)
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
        await pull()
        await pushIfDue()
    }

    // Первую отправку делает вход в GitHub — с неё и отсчитываем сутки.
    static func markPushed(_ date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: lastPushKey)
    }

    // Чтение токена может ждать окна macOS «разрешить доступ к Связке ключей» — не на главном потоке,
    // иначе всё приложение замирает, пока окно не закрыли.
    private static func token() async -> String? {
        await Task.detached { TokenStore().load() }.value
    }

    // Без входа в GitHub забирать неоткуда — пропускаем.
    private func pull() async {
        guard let engine, let token = await Self.token() else { return }
        do {
            switch try await engine.pull(token: token) {
            case .merged(let conflicts) where !conflicts.isEmpty:
                log.info("слили с другого мака, конфликтов: \(conflicts.count) — обе версии сохранены")
            default:
                break
            }
        } catch {
            log.error("не забрали с github: \(String(describing: error), privacy: .public)")
        }
    }

    private func pushIfDue() async {
        // Без входа в GitHub токена нет — история остаётся на этом Маке.
        guard let engine, let token = await Self.token() else { return }
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
