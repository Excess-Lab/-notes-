import Foundation
import Security

// Токен GitHub в Связке ключей macOS (Keychain) — системном хранилище секретов.
// В файлы, UserDefaults и .git/config хранилища токен не пишем.
public struct TokenStore: Sendable {
    let service: String
    let account: String

    public init(service: String = "notes.github", account: String = "token") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func save(_ token: String) throws {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        // Запись создана этой сборкой — пересоздавать её при чтении не нужно.
        UserDefaults.standard.set(true, forKey: "keychainRecreated.\(service).\(account)")
    }

    public func load() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let value = String(data: data, encoding: .utf8) else { return nil }
        recreateOnce(value)
        return value
    }

    // Запись в Связке ключей помнит, какая сборка её создала. Записи от сборок без подписи командой
    // macOS считает чужими и при каждом запуске спрашивает пароль. Один раз пересоздаём запись
    // от имени текущей, подписанной сборки — дальше пересборки её не теряют и ничего не спрашивают.
    private func recreateOnce(_ value: String) {
        let key = "keychainRecreated.\(service).\(account)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if (try? save(value)) != nil { UserDefaults.standard.set(true, forKey: key) }
    }

    // Есть ли запись — без чтения самого секрета. Чтение данных macOS может прикрыть окном
    // «разрешить доступ к Связке ключей», а проверка наличия его не вызывает.
    public var exists: Bool {
        var request = query
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(request as CFDictionary, nil) == errSecSuccess
    }

    public func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}
