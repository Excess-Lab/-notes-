import Foundation

// Когда спрашивать пинкод или Touch ID. Цель — не мешать, пока человек работает, и закрывать заметки,
// когда он отошёл: Mac заблокирован или уснул, приложение долго не трогали.
public enum LockPolicy {
    // Приложение было в фоне дольше — при возврате спрашиваем снова.
    public static let idleLimit: TimeInterval = 15 * 60
    // Закрыл и сразу открыл (или приложение перезапустилось) — не спрашиваем.
    public static let relaunchGrace: TimeInterval = 5 * 60

    // lastSeenUnlocked — когда приложение последний раз было открытым и разблокированным
    // (ушло в фон, закрылось). nil — не было или с тех пор Mac блокировался.
    public static func needsUnlockAtLaunch(lastSeenUnlocked: Date?, now: Date = Date()) -> Bool {
        guard let lastSeenUnlocked else { return true }
        let elapsed = now.timeIntervalSince(lastSeenUnlocked)
        // Время назад (перевели часы) считаем подозрительным и спрашиваем.
        return elapsed < 0 || elapsed > relaunchGrace
    }

    public static func needsUnlockOnReturn(inactiveSince: Date?, now: Date = Date()) -> Bool {
        guard let inactiveSince else { return false }
        let elapsed = now.timeIntervalSince(inactiveSince)
        return elapsed < 0 || elapsed >= idleLimit
    }
}

// Пауза после неверных пинкодов. Четыре цифры — 10 000 вариантов, без паузы их переберут за минуты.
// Первые 5 ошибок бесплатно (опечатки), дальше 30 с, 1 мин, 2 мин… но не больше 15 минут.
// Хранится между запусками: перезапуск приложения паузу не сбрасывает.
public struct AttemptLimiter: Codable, Equatable, Sendable {
    public static let freeAttempts = 5
    static let firstDelay: TimeInterval = 30
    static let maxDelay: TimeInterval = 15 * 60

    public private(set) var failures = 0
    public private(set) var blockedUntil: Date?

    public init() {}

    // Сколько секунд ещё ждать; nil — можно вводить.
    public func remaining(now: Date = Date()) -> TimeInterval? {
        guard let blockedUntil, blockedUntil > now else { return nil }
        return blockedUntil.timeIntervalSince(now)
    }

    public mutating func recordFailure(now: Date = Date()) {
        failures += 1
        guard failures >= Self.freeAttempts else { return }
        let extra = failures - Self.freeAttempts
        let delay = min(Self.firstDelay * pow(2, Double(min(extra, 10))), Self.maxDelay)
        blockedUntil = now.addingTimeInterval(delay)
    }

    public mutating func reset() {
        failures = 0
        blockedUntil = nil
    }
}

// Где правила входа помнят своё между запусками. UserDefaults, а не Связка ключей: здесь нет секретов,
// только время и счётчик.
public struct LockMemory {
    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private static let lastSeenKey = "lock.lastSeenUnlocked"
    private static let limiterKey = "lock.attempts"

    public var lastSeenUnlocked: Date? {
        get { defaults.object(forKey: Self.lastSeenKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.lastSeenKey) }
    }

    public var limiter: AttemptLimiter {
        get {
            defaults.data(forKey: Self.limiterKey)
                .flatMap { try? JSONDecoder().decode(AttemptLimiter.self, from: $0) } ?? AttemptLimiter()
        }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.limiterKey) }
    }
}
