import LocalAuthentication

// Pass-key на шаге «установим пароль?»: вход в приложение по Touch ID.
// Сами заметки не шифруем — иначе их не откроет Obsidian (открытый вопрос в ONBOARDING.md),
// поэтому храним только флаг «спрашивать Touch ID при входе».
enum BiometricLock {
    private static let enabledKey = "unlockWithBiometrics"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    // false — на этом Маке нет Touch ID или он не настроен.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    // Включаем только после успешной проверки отпечатка: так пользователь сразу видит, что это работает.
    static func enable() async -> Bool {
        let context = LAContext()
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                     localizedReason: "входить в заметки по отпечатку")) ?? false
        if ok { UserDefaults.standard.set(true, forKey: enabledKey) }
        return ok
    }
}
