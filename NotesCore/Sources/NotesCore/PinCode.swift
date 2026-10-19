import CommonCrypto
import Foundation
import Security

// Ввод нового пинкода на шаге «установим пароль?»: придумать → повторить → готово.
// Не совпало — начинаем с начала, а на экране «не совпало» до первой новой цифры.
// Как form-валидация в вебе, только поле — четыре ячейки, а «отправка» — четвёртая цифра.
public struct PinEntry: Equatable, Sendable {
    public enum Stage: Equatable, Sendable { case create, confirm, mismatch, done }

    public static let length = 4

    public private(set) var stage: Stage = .create
    public private(set) var digits: [Int] = []
    private var first: [Int] = []

    public init() {}

    // Готовый пинкод — только после повтора без ошибки.
    public var pin: String? { stage == .done ? first.map(String.init).joined() : nil }

    public mutating func type(_ character: Character) {
        guard stage != .done, let digit = character.wholeNumberValue, character.isASCII,
              digits.count < Self.length else { return }
        if stage == .mismatch { stage = .create }
        digits.append(digit)
        guard digits.count == Self.length else { return }
        switch stage {
        case .create:
            first = digits
            digits = []
            stage = .confirm
        case .confirm:
            if digits == first {
                stage = .done
            } else {
                first = []
                digits = []
                stage = .mismatch
            }
        case .mismatch, .done:
            break
        }
    }

    public mutating func deleteBackward() {
        guard stage != .done, !digits.isEmpty else { return }
        digits.removeLast()
    }
}

// Ввод пинкода при запуске: четвёртая цифра сразу проверяется. Неверный — ячейки пустеют,
// а «неверный пинкод» висит до первой новой цифры.
public struct PinUnlock: Equatable, Sendable {
    public enum Stage: Equatable, Sendable { case enter, wrong, unlocked }

    public private(set) var stage: Stage = .enter
    public private(set) var digits: [Int] = []

    public init() {}

    public mutating func type(_ character: Character, verify: (String) -> Bool) {
        guard stage != .unlocked, let digit = character.wholeNumberValue, character.isASCII,
              digits.count < PinEntry.length else { return }
        if stage == .wrong { stage = .enter }
        digits.append(digit)
        guard digits.count == PinEntry.length else { return }
        if verify(digits.map(String.init).joined()) {
            stage = .unlocked
        } else {
            digits = []
            stage = .wrong
        }
    }

    public mutating func deleteBackward() {
        guard stage != .unlocked, !digits.isEmpty else { return }
        digits.removeLast()
    }
}

// Пинкод храним не сам, а его производную: PBKDF2-SHA256 с солью. Четыре цифры перебираются
// быстро при любом хеше, поэтому настоящая защита — Связка ключей, а хеш нужен, чтобы пинкод
// не лежал открытым текстом даже там.
public struct PinHash: Equatable, Sendable {
    public let salt: Data
    public let hash: Data

    static let rounds: UInt32 = 200_000

    public init(pin: String, salt: Data = PinHash.randomSalt()) {
        self.salt = salt
        self.hash = Self.derive(pin, salt: salt)
    }

    init(salt: Data, hash: Data) {
        self.salt = salt
        self.hash = hash
    }

    public func matches(_ pin: String) -> Bool {
        Self.derive(pin, salt: salt) == hash
    }

    // В Связке ключей лежит одной строкой: «соль:хеш» в base64.
    public var encoded: String { salt.base64EncodedString() + ":" + hash.base64EncodedString() }

    public init?(encoded: String) {
        let parts = encoded.split(separator: ":")
        guard parts.count == 2, let salt = Data(base64Encoded: String(parts[0])),
              let hash = Data(base64Encoded: String(parts[1])) else { return nil }
        self.init(salt: salt, hash: hash)
    }

    public static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private static func derive(_ pin: String, salt: Data) -> Data {
        var out = [UInt8](repeating: 0, count: 32)
        let password = Array(pin.utf8).map { Int8(bitPattern: $0) }
        salt.withUnsafeBytes { saltBytes in
            _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.count,
                                     saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &out, out.count)
        }
        return Data(out)
    }
}

// Пинкод входа в приложение. Заметки им не шифруются — иначе их не открыл бы Obsidian.
public struct PinStore: Sendable {
    let keychain: TokenStore

    public init(keychain: TokenStore = TokenStore(service: "notes.pin", account: "pin")) {
        self.keychain = keychain
    }

    public var isSet: Bool { keychain.load() != nil }

    public func save(_ pin: String) throws { try keychain.save(PinHash(pin: pin).encoded) }

    public func verify(_ pin: String) -> Bool {
        guard let stored = keychain.load(), let hash = PinHash(encoded: stored) else { return false }
        return hash.matches(pin)
    }

    public func remove() { keychain.delete() }
}
