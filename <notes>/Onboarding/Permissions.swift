import AVFoundation
import EventKit
import Observation

// Системные разрешения для шага «пару моментиков». Статус всегда берём у macOS, а не храним сами:
// пользователь может включить или выключить доступ в Системных настройках в любой момент.
@MainActor
@Observable
final class Permissions {
    private(set) var microphone = false
    private(set) var calendar = false

    init() { refresh() }

    func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        calendar = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
    }

    func requestCalendar() async {
        _ = try? await EKEventStore().requestFullAccessToEvents()
        refresh()
    }
}
