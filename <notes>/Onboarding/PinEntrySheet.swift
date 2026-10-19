import AppKit
import NotesCore
import SwiftUI

// Окно ввода пинкода поверх шага 9 — кадры «пинкод — придумай(9.1)», «повтори(9.2)», «не совпало(9.3)».
// Карточка 300×180 в точке (130, 130) окна, «отмена» сверху — как «назад» на шагах. Кнопки «готово» нет: четвёртая цифра сама ведёт дальше.
struct PinEntrySheet: View {
    let onFinish: (_ saved: Bool) -> Void
    @State private var entry = PinEntry()
    @State private var monitor: Any?
    @State private var shake = 0

    var body: some View {
        ZStack(alignment: .top) {
            // Карточка: стекло #F9F9F9 55 % и белый лист 85 % поверх. Тень 40 в Figma — это radius 20 в SwiftUI.
            RoundedRectangle(cornerRadius: 30)
                .fill(Color(white: 249 / 255).opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 30).fill(.white.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 12)

            VStack(spacing: 0) {
                Button("отмена") { close(saved: false) }
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
                    .foregroundStyle(entry.stage == .mismatch ? Theme.coral : .black.opacity(0.3))
                    .frame(height: 13)
                    .padding(.top, 6)
                cells
                    .padding(.top, 21)
                    .modifier(Shake(phase: CGFloat(shake)))
            }
            .contentTransition(.opacity)
        }
        .frame(width: 300, height: 180)
        .animation(.smooth(duration: 0.35), value: entry)
        .onAppear(perform: listen)
        .onDisappear(perform: stopListening)
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

    // Ячейки 46×46 через 12. Заполненная — точка 10, текущая — с коралловой внутренней тенью,
    // при ошибке все обведены коралловым.
    private var cells: some View {
        HStack(spacing: 12) {
            ForEach(0..<PinEntry.length, id: \.self) { index in
                let current = index == entry.digits.count && entry.stage != .mismatch && entry.stage != .done
                ZStack {
                    // Чёрный 4,5 % на белом карточки, но непрозрачным цветом: внутренняя тень
                    // в SwiftUI умножается на прозрачность заливки и на 4,5 % её не видно.
                    // Тень 8 в Figma — radius 4 в SwiftUI.
                    Circle()
                        .fill(Color(white: 0.955)
                            .shadow(.inner(color: Theme.coral.opacity(current ? 0.6 : 0), radius: 4, y: 2)))
                    Circle()
                        .strokeBorder(Theme.coral, lineWidth: entry.stage == .mismatch ? 1 : 0)
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 10, height: 10)
                        .scaleEffect(index < filledCount ? 1 : 0.2)
                        .opacity(index < filledCount ? 1 : 0)
                }
                .frame(width: 46, height: 46)
            }
        }
    }

    // Когда пинкод готов, на мгновение показываем все четыре точки, а не пустые ячейки.
    private var filledCount: Int { entry.stage == .done ? PinEntry.length : entry.digits.count }

    // Клавиши ловим локальным монитором, как при записи хоткея: окно наше, фокус не нужен.
    private func listen() {
        #if DEBUG
        // `--args -onboardingStep 9 -pinPreview 1234_` открывает окно с уже набранными цифрами
        // («_» — пропуск), чтобы снять каждое состояние для сверки с Figma. 8 цифр подряд сохранят пинкод.
        for character in UserDefaults.standard.string(forKey: "pinPreview") ?? "" { input(character) }
        #endif
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ⌘-сочетания (меню «Отладка», ⌘Q) пропускаем дальше.
            if event.modifierFlags.contains(.command) { return event }
            handle(event)
            return nil
        }
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.keyCode {
        case 53: close(saved: false)          // esc
        case 51, 117: entry.deleteBackward()  // delete, forward delete
        default:
            if let character = event.characters?.first { input(character) }
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

// Ячейки качаются из стороны в сторону, когда повтор не совпал — как поле пароля на macOS.
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
