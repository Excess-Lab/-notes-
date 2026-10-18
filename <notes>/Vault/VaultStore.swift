import Foundation

// Папка хранилища между запусками.
//
// Приложение в песочнице: доступ к папке, выбранной в окне Finder, живёт только до закрытия.
// Чтобы помнить её дальше, храним security-scoped bookmark — «пропуск» к этой папке,
// который macOS признаёт и после перезапуска. Веб-аналог: токен доступа к одной папке.
enum VaultStore {
    private static let bookmarkKey = "vaultBookmark"

    static func save(_ url: URL, defaults: UserDefaults = .standard) throws {
        let data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: bookmarkKey)
    }

    // Открывает доступ к сохранённой папке. nil — папку не выбирали, её удалили или пропуск устарел.
    static func restore(defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource()
        else { return nil }
        // Папку переместили или переименовали — macOS её нашла, но пропуск надо перевыпустить.
        if stale { try? save(url, defaults: defaults) }
        return url
    }

    static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: bookmarkKey)
    }

    // Папка в iCloud Drive: iCloud синхронизирует .git по кусочкам и может сломать историю (CONTEXT.md).
    // В iCloud лежит всё внутри ~/Library/Mobile Documents, включая «Рабочий стол» и «Документы»,
    // если у пользователя включена их синхронизация — тогда у папки стоит признак ubiquitous.
    static func isInICloud(_ url: URL) -> Bool {
        if url.standardizedFileURL.path.contains("/Library/Mobile Documents/") { return true }
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
        return values?.isUbiquitousItem == true
    }
}
