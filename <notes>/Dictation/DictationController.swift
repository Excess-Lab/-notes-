import AppKit
import AVFoundation
import NotesSpeech
import os
import SwiftUI

// Надиктовка из любого приложения: держишь ⌥ space — пишем, отпустил — распознаём локально
// и кладём текст в буфер обмена. Вставляет человек сам (⌘V) — так приложению не нужен доступ
// к чужим окнам («Универсальный доступ»).
@Observable
final class DictationController {
    enum State: Equatable { case idle, listening, recognizing, copied }

    static let shared = DictationController()

    private(set) var state: State = .idle
    private(set) var level: Float = 0

    private let recorder = AudioRecorder()
    private let log = Logger(subsystem: "notes", category: "dictation")
    private var hotKey: GlobalHotKey?
    private var panel: DictationPanel?
    // Модель загружается в память секунды — держим одну, пока не сменили в настройках.
    private var transcriber: (model: SpeechModel, engine: Transcriber)?

    // Короче этого — случайное нажатие, а не фраза: не распознаём.
    private static let minimumSeconds = 0.4

    func start() {
        guard hotKey == nil else { return }
        panel = DictationPanel(controller: self)
        hotKey = GlobalHotKey(onPress: { [weak self] in self?.begin() },
                              onRelease: { [weak self] in Task { await self?.finish() } })
        log.info("надиктовка готова: ⌥ space")
    }

    private func begin() {
        guard state == .idle || state == .copied else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            // Разрешение дают на шаге «пару моментиков»; без него просто спрашиваем систему.
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return
        }
        do {
            try recorder.start { value in
                // Сглаживаем, чтобы волны не дёргались от каждого всплеска.
                Task { @MainActor in
                    let shared = DictationController.shared
                    shared.level = shared.level * 0.6 + value * 0.4
                }
            }
            state = .listening
            panel?.show()
        } catch {
            log.error("микрофон не включился: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    private func finish() async {
        guard state == .listening else { return }
        let samples = recorder.stop()
        level = 0
        guard Double(samples.count) / Double(Transcribers.sampleRate) >= Self.minimumSeconds else {
            hide()
            return
        }
        state = .recognizing
        do {
            let engine = try await loadTranscriber()
            // Распознавание — секунда-две работы процессора: не на главном потоке, чтобы не замер интерфейс.
            let text = try await Task.detached { try await engine.transcribe(samples) }.value
            guard !text.isEmpty else { hide(); return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            state = .copied
            try? await Task.sleep(for: .seconds(1.2))
            hide()
        } catch {
            log.error("не распознали: \(String(describing: error), privacy: .public)")
            NSSound.beep()
            hide()
        }
    }

    private func loadTranscriber() async throws -> Transcriber {
        let model = SpeechSettings.model
        if let transcriber, transcriber.model == model { return transcriber.engine }
        let engine = try await Transcribers.make(model)
        transcriber = (model, engine)
        return engine
    }

    private func hide() {
        state = .idle
        panel?.hide()
    }

    #if DEBUG
    // Прогон без микрофона и без клавиш: запись из WAV-файла (16 кГц, 16 бит, моно) идёт тем же путём —
    // сфера слушает (громкость из файла), распознаёт, кладёт текст в буфер, показывает галочку.
    // Запуск: `open <notes>.app --args -dictationTestFile /путь/к/файлу.wav`.
    func debugRun(file: URL) async {
        guard let data = try? Data(contentsOf: file), let range = data.range(of: Data("data".utf8)) else { return }
        let samples: [Float] = data[(range.upperBound + 4)...].withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Float($0) / 32768 }
        }
        state = .listening
        panel?.show()
        // Проигрываем громкость файла в реальном времени, но не дольше трёх секунд.
        let chunk = Transcribers.sampleRate / 10
        for start in stride(from: 0, to: min(samples.count, Transcribers.sampleRate * 3), by: chunk) {
            let slice = samples[start..<min(start + chunk, samples.count)]
            let rms = (slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count)).squareRoot()
            level = level * 0.6 + min(1, rms * 12) * 0.4
            try? await Task.sleep(for: .milliseconds(100))
        }
        level = 0
        state = .recognizing
        do {
            let engine = try await loadTranscriber()
            let text = try await Task.detached { try await engine.transcribe(samples) }.value
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            log.info("тест надиктовки: \(text, privacy: .public)")
            state = .copied
            try? await Task.sleep(for: .seconds(1.2))
        } catch {
            log.error("тест надиктовки: \(String(describing: error), privacy: .public)")
        }
        hide()
    }
    #endif
}

// Плавающая панель со сферой: поверх всех окон и на всех рабочих столах, фокус не забирает
// и клики пропускает насквозь — человек продолжает работать там, где был.
private final class DictationPanel {
    private let panel: NSPanel
    private static let side: CGFloat = 200   // со стороной сферы 96 и запасом под тень

    init(controller: DictationController) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: OrbHost(controller: controller))
    }

    // Внизу по центру экрана, где сейчас курсор: туда человек и смотрит.
    func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: area.midX - Self.side / 2, y: area.minY + 40))
        panel.orderFrontRegardless()
    }

    func hide() {
        // Даём сфере доиграть исчезновение, потом убираем панель.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [panel] in panel.orderOut(nil) }
    }
}

private struct OrbHost: View {
    let controller: DictationController

    var body: some View {
        let visible = controller.state != .idle
        DictationOrb(state: controller.state, level: controller.level)
            .scaleEffect(visible ? 1 : 0.6)
            .opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 8)
            .animation(.spring(duration: 0.35, bounce: 0.25), value: visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(.light)
    }
}
