import Foundation
import Testing
@testable import NotesCore

@Suite("умный вход")
struct LockPolicyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("перезапуск сразу после работы — без пинкода, через 6 минут — с пинкодом")
    func relaunchGrace() {
        #expect(!LockPolicy.needsUnlockAtLaunch(lastSeenUnlocked: now.addingTimeInterval(-60), now: now))
        #expect(LockPolicy.needsUnlockAtLaunch(lastSeenUnlocked: now.addingTimeInterval(-6 * 60), now: now))
    }

    // Mac заблокировали — отметку стираем, и даже быстрый перезапуск спрашивает пинкод.
    @Test("после блокировки Mac (отметки нет) — всегда спрашиваем")
    func noMarkAsksAlways() {
        #expect(LockPolicy.needsUnlockAtLaunch(lastSeenUnlocked: nil, now: now))
    }

    // Иначе перевод часов назад давал бы бесконечную «свежую» отметку.
    @Test("отметка из будущего — спрашиваем")
    func clockMovedBack() {
        #expect(LockPolicy.needsUnlockAtLaunch(lastSeenUnlocked: now.addingTimeInterval(3600), now: now))
    }

    @Test("вернулся в приложение через 14 минут — без пинкода, через 15 — с пинкодом")
    func idleReturn() {
        #expect(!LockPolicy.needsUnlockOnReturn(inactiveSince: now.addingTimeInterval(-14 * 60), now: now))
        #expect(LockPolicy.needsUnlockOnReturn(inactiveSince: now.addingTimeInterval(-15 * 60), now: now))
        #expect(!LockPolicy.needsUnlockOnReturn(inactiveSince: nil, now: now))
    }

    @Test("пять ошибок без паузы, шестая ждёт 30 с, дальше дольше, но не больше 15 минут")
    func attemptDelays() {
        var limiter = AttemptLimiter()
        for _ in 0..<4 { limiter.recordFailure(now: now) }
        #expect(limiter.remaining(now: now) == nil)
        limiter.recordFailure(now: now)
        #expect(limiter.remaining(now: now) == 30)
        limiter.recordFailure(now: now)
        #expect(limiter.remaining(now: now) == 60)
        for _ in 0..<20 { limiter.recordFailure(now: now) }
        #expect(limiter.remaining(now: now) == TimeInterval(900))
        #expect(limiter.remaining(now: now.addingTimeInterval(15 * 60)) == nil)
        limiter.reset()
        #expect(limiter.failures == 0)
    }

    // Иначе перезапуск приложения обнулял бы паузу, и перебор шёл бы без задержек.
    @Test("пауза переживает перезапуск")
    func limiterPersists() throws {
        let defaults = try #require(UserDefaults(suiteName: "lock-test-\(UUID())"))
        let memory = LockMemory(defaults: defaults)
        var limiter = memory.limiter
        for _ in 0..<5 { limiter.recordFailure(now: now) }
        memory.limiter = limiter
        #expect(LockMemory(defaults: defaults).limiter.remaining(now: now) == 30)
    }
}
