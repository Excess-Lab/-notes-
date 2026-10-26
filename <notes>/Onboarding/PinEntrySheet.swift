import AppKit
import NotesCore
import SwiftUI

// Окно ввода пинкода поверх шага 9 — кадры «пинкод — придумай(9.1)», «повтори(9.2)», «не совпало(9.3)».
// Карточка 300×180 в точке (130, 130) окна, «отмена» сверху — как «назад» на шагах.
// Кнопки «готово» нет: четвёртая цифра сама ведёт дальше.
struct PinEntrySheet: View {
    let onFinish: (_ saved: Bool) -> Void
    @State private var entry = PinEntry()
    @State private var monitor: Any?
    @State private var shake = 0

    var body: some View {
        PinCard(title: title, subtitle: subtitle, isError: entry.stage == .mismatch,
                filled: filledCount, current: current, shake: shake,
                cancel: { close(saved: false) })
            .animation(.smooth(duration: 0.35), value: entry)
            .onAppear(perform: listen)
            .onDisappear(perform: stopListening)
    }

    // Текущая ячейка подсвечена, пока ждём цифру; после ошибки и в конце — ни одна.
    private var current: Int? {
        entry.stage == .create || entry.stage == .confirm ? entry.digits.count : nil
    }

    private var title: String {
        switch entry.stage {
        case .create: "придумай пинкод"
        // Пока карточка закрывается после верного повтора, заголовок не прыгает назад.
        case .confirm, .done: "повтори пинкод"
        case .mismatch: "не совпало"
        }
    }

    private var subtitle: String {
        switch entry.stage {
        case .create: "4 цифры — спросим при входе"
        case .confirm, .done: "ещё раз, чтобы не ошибиться"
        case .mismatch: "придумай заново"
        }
    }

    // Когда пинкод готов, на мгновение показываем все четыре точки, а не пустые ячейки.
    private var filledCount: Int { entry.stage == .done ? PinEntry.length : entry.digits.count }

    private func listen() {
        #if DEBUG
        // `--args -onboardingStep 9 -pinPreview 1234_` открывает окно с уже набранными цифрами
        // («_» — пропуск), чтобы снять каждое состояние для сверки с Figma. 8 цифр подряд сохранят пинкод.
        for character in UserDefaults.standard.string(forKey: "pinPreview") ?? "" { input(character) }
        #endif
        monitor = PinKeys.listen(handle)
    }

    private func stopListening() {
        PinKeys.stop(monitor)
        monitor = nil
    }

    private func handle(_ key: PinKeys.Key) {
        switch key {
        case .escape: close(saved: false)
        case .delete: entry.deleteBackward()
        case .character(let character): input(character)
        }
    }

    private func input(_ character: Character) {
        let before = entry.stage
        entry.type(character)
        if entry.stage == .mismatch, before == .confirm {
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
        }
        if let pin = entry.pin { save(pin) }
    }

    private func save(_ pin: String) {
        do {
            try PinStore().save(pin)
        } catch {
            NSAlert(error: error).runModal()
            close(saved: false)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            close(saved: true)
        }
    }

    private func close(saved: Bool) {
        stopListening()
        onFinish(saved)
    }
}

// Карточка пинкода при настройке (9.1–9.3).
struct PinCard: View {
    let title: String
    let subtitle: String
    var isError = false
    var filled = 0
    var current: Int?
    var shake = 0
    var cancel: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // Карточка: стекло #F9F9F9 55 % и белый лист 85 % поверх. Тень 40 в Figma — это radius 20 в SwiftUI.
            RoundedRectangle(cornerRadius: 30)
                .fill(Color(white: 249 / 255).opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 30).fill(.white.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 12)

            VStack(spacing: 0) {
                Button("отмена", action: cancel)
                    // В кадре 30 %, а не 20 % как у ссылок под кнопкой.
                    .buttonStyle(QuietLinkStyle(size: 11, opacity: 0.3))
                    .frame(height: 13)
                    .padding(.top, 18)
                Text(title)
                    .font(Martian.heading.font(20))
                    .kerning(Theme.tracking(-7, size: 20))
                    .foregroundStyle(.black)
                    .frame(height: 24)
                    .padding(.top, 9)
                Text(subtitle)
                    .font(Martian.body.font(11))
                    .kerning(Theme.tracking(-7, size: 11))
                    .foregroundStyle(isError ? Theme.coral : .black.opacity(0.3))
                    .frame(height: 13)
                    .padding(.top, 6)
                PinCells(filled: filled, current: current, isError: isError, shake: shake)
                    .padding(.top, 21)
            }
            .contentTransition(.opacity)
        }
        .frame(width: 300, height: 180)
        // В тёмных кадрах карточка пинкода остаётся светлой — как в макете.
        .environment(\.colorScheme, .light)
    }
}

// Ячейки 46×46 через 12: в карточке настройки и на листе входа. Заполненная — точка 10,
// текущая — с коралловой внутренней тенью, при ошибке все обведены коралловым и качаются.
struct PinCells: View {
    var filled = 0
    var current: Int?
    var isError = false
    var shake = 0

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<PinEntry.length, id: \.self) { index in
                ZStack {
                    // Чёрный 4,5 % на белом, но непрозрачным цветом: внутренняя тень
                    // в SwiftUI умножается на прозрачность заливки и на 4,5 % её не видно.
                    // Тень 8 в Figma — radius 4 в SwiftUI.
                    Circle()
                        .fill(Color(light: Color(white: 0.955), dark: Color(white: 0.1))
                            .shadow(.inner(color: Theme.coral.opacity(index == current ? 0.6 : 0), radius: 4, y: 2)))
                    Circle()
                        .strokeBorder(Theme.coral, lineWidth: isError ? 1 : 0)
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 10, height: 10)
                        .scaleEffect(index < filled ? 1 : 0.2)
                        .opacity(index < filled ? 1 : 0)
                }
                .frame(width: 46, height: 46)
            }
        }
        .modifier(Shake(phase: CGFloat(shake)))
    }
}

// Клавиши ловим локальным монитором, как при записи хоткея: окно наше, фокус не нужен.
enum PinKeys {
    enum Key { case escape, delete, character(Character) }

    static func listen(_ handle: @escaping (Key) -> Void) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ⌘-сочетания (меню «Отладка», ⌘Q) пропускаем дальше.
            if event.modifierFlags.contains(.command) { return event }
            switch event.keyCode {
            case 53: handle(.escape)
            case 51, 117: handle(.delete)   // delete, forward delete
            default: if let character = event.characters?.first { handle(.character(character)) }
            }
            return nil
        }
    }

    static func stop(_ monitor: Any?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

// Ячейки качаются из стороны в сторону, когда пинкод не тот — как поле пароля на macOS.
private struct Shake: GeometryEffect {
    var phase: CGFloat
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(phase * .pi * 6), y: 0))
    }
}
