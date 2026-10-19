import NotesSpeech
import SwiftUI

// Строки списков шагов 6–9. Размеры из Figma: капсула 440×53, поля 11/14, промежуток 12,
// между строками 5. Координаты строк — от верха листа (y = 54 в окне).

// Стеклянная капсула на белом листе: в макете Glass на белом даёт лёгкую серость слева,
// которая растворяется к правому краю, и светлый кант по верхней кромке.
struct GlassRow<Content: View>: View {
    var height: CGFloat = 53
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 12, content: content)
            .padding(.horizontal, 14)
            .frame(width: 440, height: height, alignment: .leading)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: [.black.opacity(0.045), .black.opacity(0.018), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(
                        LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1))
                    .blur(radius: 0.6)
            }
    }
}

private struct RowTexts: View {
    let title: Text
    let subtitle: String
    var subtitleOpacity: Double = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(Martian.body.font(13))
                .kerning(Theme.tracking(-7, size: 13))
            Text(subtitle)
                .font(Martian.body.font(11))
                .kerning(Theme.tracking(-7, size: 11))
                .foregroundStyle(.black.opacity(subtitleOpacity))
        }
    }
}

// Шаг 6. Выбранная модель яркая, остальные — 30 % (так в макете). Выбор переключается плавно.
struct ModelPicker: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 5) {
            ForEach(SpeechModel.allCases, id: \.self) { option in
                let selected = model.speechModel == option
                GlassRow {
                    RowTexts(title: title(for: option), subtitle: subtitle(for: option),
                             subtitleOpacity: selected ? 1 : 0.3)
                    Spacer(minLength: 0)
                }
                .opacity(selected ? 1 : 0.3)
                .contentShape(Capsule())
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.5)) { model.speechModel = option }
                }
            }
        }
        .offset(y: 183 - Layout.sheetTop)
    }

    private func title(for option: SpeechModel) -> Text {
        switch option {
        case .gigaAM:
            Text("GigaAM v3 \(Text("(300 мб, лучше отключить впн)").foregroundStyle(.black.opacity(0.3)))").foregroundStyle(.black)
        case .whisperSmall:
            Text("Whisper small (466 мб)").foregroundStyle(.black)
        case .whisperLargeTurbo:
            Text("Whisper large-v3 turbo \(Text("(1,6 гб.)").foregroundStyle(.black.opacity(0.3)))").foregroundStyle(.black)
        }
    }

    private func subtitle(for option: SpeechModel) -> String {
        switch option {
        // В макете под GigaAM подпись от Whisper («whisper small · 466 мб · 2 мин») — похоже на
        // остаток от копирования. Пишем про саму GigaAM; если подпись задумана, поменять здесь.
        case .gigaAM: "только русский, сразу с пунктуацией"
        case .whisperSmall: "99 языков, быстрее"
        case .whisperLargeTurbo: "99 языков, точнее, но тяжелее"
        }
    }
}

// Шаг 7. Прогресс скачивания выбранной модели.
struct DownloadRow: View {
    let model: OnboardingModel

    var body: some View {
        GlassRow {
            DotIcon(glyph: .microphone, size: 18)
            RowTexts(title: Text("распознавание речи").foregroundStyle(Theme.ink),
                     subtitle: "\(model.speechModel.displayName.lowercased()), \(remaining)")
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 249 / 255))
                    Capsule().fill(Theme.coral)
                        .frame(width: 90 * model.downloadProgress)
                }
                .frame(width: 90, height: 6)
                Text("\(Int(model.downloadProgress * 100))%")
                    .font(Martian.body.font(11))
                    .foregroundStyle(.black.opacity(0.3))
                    .monospacedDigit()
                    .frame(width: 30, alignment: .leading)
            }
        }
        .offset(y: 199 - Layout.sheetTop)
        // Если на шаг пришли не с «дальше» на моделях (например, из меню «Отладка»), запускаем сами.
        .onAppear { if model.downloadProgress == 0 { model.startDownload() } }
    }

    private var remaining: String {
        if model.downloadFailed { return "не скачалось — проверь интернет" }
        if model.downloadProgress >= 1 { return "скачано" }
        // Оценка по уже скачанному: сколько ушло на долю p, столько же уйдёт на остаток.
        guard let started = model.downloadStarted, model.downloadProgress > 0.02 else { return "считаем время" }
        let elapsed = Date().timeIntervalSince(started)
        let left = elapsed * (1 - model.downloadProgress) / model.downloadProgress
        return left < 60 ? "меньше минуты" : "осталось \(Int((left / 60).rounded(.up))) мин"
    }
}

// Шаг 8. Разрешения — настоящие, статус берётся у macOS.
struct PermissionRows: View {
    @State private var permissions = Permissions()

    var body: some View {
        VStack(spacing: 5) {
            GlassRow {
                DotIcon(glyph: .microphone, size: 18)
                RowTexts(title: Text("микрофон").foregroundStyle(Theme.ink), subtitle: "для надиктовки")
                Spacer(minLength: 0)
                status(granted: permissions.microphone) { await permissions.requestMicrophone() }
            }
            GlassRow {
                DotIcon(glyph: .calendar, size: 18)
                RowTexts(title: Text("календарь").foregroundStyle(Theme.ink), subtitle: "чтобы задачи попадали в календарь")
                Spacer(minLength: 0)
                status(granted: permissions.calendar) { await permissions.requestCalendar() }
            }
            HotKeyRow()
        }
        // В макете список стоит на x = 48, а не по центру (60) — повторяем как есть.
        .offset(x: 48 - 60, y: 183 - Layout.sheetTop)
        .onAppear { permissions.refresh() }
    }

    @ViewBuilder
    private func status(granted: Bool, request: @escaping () async -> Void) -> some View {
        if granted {
            GrantedLabel(text: "разрешено")
        } else {
            Button("разрешить") { Task { await request() } }
                .buttonStyle(WhitePillStyle())
        }
    }
}

// Шаг 9. Окно ввода пинкода автор ещё рисует, поэтому «настроить» у пинкода пока ничего не делает.
// Pass-key — вход по Touch ID: работает уже сейчас.
struct PasswordRows: View {
    @State private var biometricsOn = BiometricLock.isEnabled

    var body: some View {
        VStack(spacing: 5) {
            GlassRow {
                RowTexts(title: Text("пинкод").foregroundStyle(Theme.ink), subtitle: "4 символа")
                Spacer(minLength: 0)
                Button("настроить") {}
                    .buttonStyle(WhitePillStyle())
            }
            GlassRow(height: 50) {
                Text("pass-key")
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if biometricsOn {
                    GrantedLabel(text: "включено")
                } else if BiometricLock.isAvailable {
                    Button("настроить") {
                        Task { biometricsOn = await BiometricLock.enable() }
                    }
                    .buttonStyle(WhitePillStyle())
                } else {
                    Text("нет touch id")
                        .font(Martian.body.font(13))
                        .kerning(Theme.tracking(-7, size: 13))
                        .foregroundStyle(.black.opacity(0.3))
                }
            }
        }
        .offset(x: 48 - 60, y: 157 - Layout.sheetTop)
    }
}

// Зелёная галочка и серый текст — «разрешено» на шаге 8, «включено» на шаге 9.
struct GrantedLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            DotIcon(glyph: .check, color: Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255))
            Text(text)
                .font(Martian.body.font(13))
                .kerning(Theme.tracking(-7, size: 13))
                .foregroundStyle(Color(red: 134 / 255, green: 134 / 255, blue: 139 / 255))
        }
    }
}

// Вторичная кнопка в строке: белая капсула, поля 6/14, текст 13.
struct WhitePillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Martian.body.font(13))
            .kerning(Theme.tracking(-7, size: 13))
            .foregroundStyle(Theme.ink)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.8 : 0.55)))
            .background(Capsule().fill(.white).blur(radius: 2).opacity(0.6))
    }
}

// Тихая кнопка в строке («изменить»): только серый текст.
struct QuietPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Martian.body.font(13))
            .kerning(Theme.tracking(-7, size: 13))
            .foregroundStyle(.black.opacity(configuration.isPressed ? 0.5 : 0.3))
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .contentShape(Capsule())
    }
}

struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Martian.body.font(11))
            .kerning(Theme.tracking(-7, size: 11))
            .foregroundStyle(.black.opacity(0.55))
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.8)))
    }
}

extension OnboardingModel {
    // Качает выбранную модель в Application Support (NotesSpeech.ModelStore). Шаг 7 не ждёт конца:
    // «дальше» можно нажать сразу, скачивание продолжится в фоне.
    func startDownload() {
        let model = speechModel
        downloadProgress = 0
        downloadFailed = false
        downloadStarted = Date()
        Task {
            do {
                try await ModelStore.standard.download(model) { value in
                    Task { @MainActor in self.downloadProgress = value }
                }
            } catch {
                downloadFailed = true
            }
        }
    }
}
