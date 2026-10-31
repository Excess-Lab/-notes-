import AppKit
import AVFoundation
import NotesCore
import NotesSpeech
import os
import SwiftUI

// Надиктовка из любого приложения: нажал ⌥ space — пишем, нажал ещё раз — распознаём локально
// и кладём текст в буфер обмена (не «держи и говори»: так решил автор — руки свободны). Вставляет человек сам (⌘V) — так приложению не нужен доступ
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
    private var transcriber: (model: SpeechModel, language: String, engine: Transcriber)?

    // Короче этого — случайное нажатие, а не фраза: не распознаём.
    private static let minimumSeconds = 0.4

    // Сочетание, по которому сейчас работает надиктовка (по умолчанию ⌥ space).
    private(set) var combo = HotKeyStore.load()

    func start() {
        guard panel == nil else { return }
        panel = DictationPanel(controller: self)
        if !register(combo) { log.error("сочетание \(self.combo.display, privacy: .public) занято другим приложением") }
    }

    // Меняет сочетание без перезапуска. false — его уже заняло другое приложение; тогда остаётся старое.
    @discardableResult
    func changeHotKey(to newCombo: HotKeyCombo) -> Bool {
        let old = combo
        hotKey = nil
        guard register(newCombo) else {
            register(old)
            return false
        }
        combo = newCombo
        HotKeyStore.save(newCombo)
        log.info("надиктовка: \(newCombo.display, privacy: .public)")
        return true
    }

    // Пока человек записывает новое сочетание, старое не должно запускать надиктовку.
    func suspendHotKey() { hotKey = nil }
    func resumeHotKey() { if hotKey == nil { register(combo) } }

    @discardableResult
    private func register(_ combo: HotKeyCombo) -> Bool {
        hotKey = try? GlobalHotKey(combo, onPress: { [weak self] in self?.toggle() })
        return hotKey != nil
    }

    // Одно сочетание и включает, и выключает. Пока распознаём, нажатия игнорируем.
    // Кнопка микрофона на главном экране — то же, что хоткей.
    func toggleFromApp() { toggle() }

    private func toggle() {
        switch state {
        case .idle, .copied: begin()
        case .listening: Task { await finish() }
        case .recognizing: break
        }
    }

    // Забыли нажать второй раз — через 5 минут останавливаем сами: дальше распознавание было бы
    // долгим, а запись — скорее всего случайной.
    private static var maximumSeconds: Int { AppSettings.maxMinutes * 60 }
    private var limit: Task<Void, Never>?

    private func begin() {
        guard state == .idle || state == .copied else { return }
        guard modelReady() else { return }
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
            limit = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.maximumSeconds))
                guard !Task.isCancelled else { return }
                await self?.finish()
            }
        } catch {
            log.error("микрофон не включился: \(String(describing: error), privacy: .public)")
            NSSound.beep()
        }
    }

    // Без модели записывать бессмысленно: открываем приложение и предлагаем её скачать.
    private func modelReady() -> Bool {
        let model = SpeechSettings.model
        if ModelStore.standard.isInstalled(model) { return true }
        ModelDownloadOffer.present(model, hotKey: combo.display)
        return false
    }

    private func finish() async {
        guard state == .listening else { return }
        limit?.cancel()
        let samples = recorder.stop()
        level = 0
        guard Double(samples.count) / Double(Transcribers.sampleRate) >= Self.minimumSeconds else {
            hide()
            return
        }
        state = .recognizing
        Self.keep(samples)
        do {
            let engine = try await loadTranscriber()
            // Распознавание — секунда-две работы процессора: не на главном потоке, чтобы не замер интерфейс.
            let text = try await Task.detached { try await engine.transcribe(samples) }.value
            Self.forget()
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

    // Запись лежит на диске, пока не распознана: если приложение упадёт посреди распознавания,
    // при следующем запуске она распознается и текст окажется в буфере — сказанное не пропадает.
    private static var pending: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("<notes>/недораспознанная запись.f32")
    }

    private static func keep(_ samples: [Float]) {
        try? FileManager.default.createDirectory(at: pending.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: pending, options: .atomic)
    }

    private static func forget() { try? FileManager.default.removeItem(at: pending) }

    // Запуск: осталась запись с прошлого раза — распознаём, кладём в буфер, показываем галочку.
    func recoverPending() async {
        guard let data = try? Data(contentsOf: Self.pending), !data.isEmpty, state == .idle else { return }
        Self.forget()   // если упадёт снова — второй раз не пробуем, чтобы не падать на каждом запуске
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        guard let engine = try? await loadTranscriber(),
              let text = try? await Task.detached(operation: { try await engine.transcribe(samples) }).value,
              !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        log.info("восстановили надиктовку после сбоя")
        flashReady()
    }

    private func loadTranscriber() async throws -> Transcriber {
        let model = SpeechSettings.model, language = AppSettings.language
        if let transcriber, transcriber.model == model, transcriber.language == language { return transcriber.engine }
        let engine = try await Transcribers.make(model, language: language)
        transcriber = (model, language, engine)
        return engine
    }

    // Модель докачалась в фоне: та же галочка, что после распознавания, — «готово, можно говорить».
    func flashReady() {
        guard state == .idle else { return }
        state = .copied
        panel?.show()
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if state == .copied { hide() }
        }
    }

    private func hide() {
        state = .idle
        panel?.hide()
    }

    #if DEBUG
    // Сфера в нужном состоянии без микрофона и модели: `--args -orbPreview listening` (или recognizing,
    // copied). При «listening» громкость качается сама — чтобы снять, как сфера отвечает на голос.
    func debugShowOrb(_ name: String) async {
        switch name {
        case "recognizing": state = .recognizing
        case "copied": state = .copied
        default: state = .listening
        }
        panel?.show()
        let start = Date()
        while state == .listening {
            let t = Date().timeIntervalSince(start)
            level = Float(0.5 + 0.5 * sin(t * 5)) * Float(0.4 + 0.6 * abs(sin(t * 1.3)))
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // Прогон без микрофона и без клавиш: запись из WAV-файла (16 кГц, 16 бит, моно) идёт тем же путём —
    // сфера слушает (громкость из файла), распознаёт, кладёт текст в буфер, показывает галочку.
    // Запуск: `open <notes>.app --args -dictationTestFile /путь/к/файлу.wav`.
    func debugRun(file: URL) async {
        // Итог — и в stderr: из терминала его видно через `open --stderr файл`.
        func report(_ line: String) { FileHandle.standardError.write(Data("тест надиктовки: \(line)\n".utf8)) }
        guard modelReady() else { return report("модель не скачана") }
        guard let data = try? Data(contentsOf: file), let range = data.range(of: Data("data".utf8)) else {
            return report("не прочитали файл (песочница пускает только в «Загрузки»)")
        }
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
            report("\(samples.count / Transcribers.sampleRate) с → \(text.count) знаков: \(text.prefix(120))…")
            state = .copied
            try? await Task.sleep(for: .seconds(1.2))
        } catch {
            log.error("тест надиктовки: \(String(describing: error), privacy: .public)")
            report("ошибка \(error)")
        }
        hide()
    }
    #endif
}

// Плавающая панель со сферой: поверх всех окон и на всех рабочих столах, фокус не забирает
// и клики пропускает насквозь — человек продолжает работать там, где был.
private final class DictationPanel {
    private let panel: NSPanel
    private static let side: CGFloat = 240   // сфера 96, холст шейдера ×1,9 и запас под пружину появления

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
        // Без .blur: даже с радиусом 0 он гнал каждый кадр шейдера через лишний проход (лаги, 31.10.2026).
        DictationOrb(state: controller.state, level: controller.level)
            .scaleEffect(visible ? 1 : 0.6)
            .opacity(visible ? 1 : 0)
            .animation(.spring(duration: 0.35, bounce: 0.25), value: visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
