import Carbon.HIToolbox
import NotesCore

// Глобальная горячая клавиша надиктовки — работает, даже когда активно другое приложение.
//
// Через старый Carbon API, потому что он, в отличие от перехвата всех клавиш, не требует разрешения
// «Универсальный доступ»: система сама сообщает только о нашей комбинации.
final class GlobalHotKey {
    enum Failure: Error { case taken }

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void

    // Бросает .taken, если сочетание уже занято другим приложением: macOS отдаёт его только первому.
    // Нужно только нажатие: надиктовка включается и выключается повторным нажатием, а не удержанием.
    init(_ combo: HotKeyCombo, onPress: @escaping () -> Void) throws {
        self.onPress = onPress
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
        // C-колбэк без захвата переменных: себя передаём через userData.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) { me.onPress() }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        // 0x6E6F7465 — «note»: подпись, по которой система отличает наши клавиши от чужих.
        let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonModifiers,
                                         EventHotKeyID(signature: 0x6E6F_7465, id: 1),
                                         GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            if let handler { RemoveEventHandler(handler) }
            throw Failure.taken
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
