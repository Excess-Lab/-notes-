import LocalAuthentication

// Pass-key на шаге «установим пароль?»: вход в приложение по Touch ID.
// Сами заметки не шифруем — иначе их не откроет другой редактор (открытый вопрос в ONBOARDING.md),
// поэтому храним только флаг «спрашивать Touch ID при входе».
enum BiometricLock {
    private static let enabledKey = "unlockWithBiometrics"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    // false — на этом Маке нет Touch ID или он не настроен.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    // macOS показывает причину в своём окне после «<notes> пытается …» — поэтому она начинается с глагола.
    // Включаем только после успешной проверки отпечатка: так пользователь сразу видит, что это работает.
    static func enable() async -> Bool {
        let context = LAContext()
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                     localizedReason: String(localized: "включить вход в <notes> по отпечатку пальца"))) ?? false
        if ok { UserDefaults.standard.set(true, forKey: enabledKey) }
        return ok
    }

    static func disable() { UserDefaults.standard.set(false, forKey: enabledKey) }

    // «забыл пинкод»: проверяем, что это хозяин Mac — паролем от учётной записи или Touch ID.
    // Окно macOS: «<notes> пытается сбросить пинкод».
    static func verifyOwner() async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication,
                                                localizedReason: String(localized: "сбросить пинкод"))) ?? false
    }

    // Вход при запуске. Окно macOS: «<notes> пытается открыть заметки».
    static func unlock() async -> Bool {
        let context = LAContext()
        // Без этого в системном окне появилась бы кнопка «Ввести пароль» от учётки Mac — у нас свой пинкод.
        context.localizedFallbackTitle = ""
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                  localizedReason: String(localized: "открыть заметки"))) ?? false
    }
}
