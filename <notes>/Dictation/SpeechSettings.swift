import Foundation
import NotesSpeech

// Какой моделью распознавать. Выбирают на шаге «модели», потом — в настройках.
enum SpeechSettings {
    private static let key = "speechModel"

    // По умолчанию GigaAM: лучше всех понимает русский (CONTEXT.md).
    static var model: SpeechModel {
        get { UserDefaults.standard.string(forKey: key).flatMap(SpeechModel.init(rawValue:)) ?? .gigaAM }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

extension SpeechModel {
    var displayName: String {
        switch self {
        case .gigaAM: "GigaAM v3"
        case .whisperSmall: "Whisper small"
        case .whisperLargeTurbo: "Whisper large-v3 turbo"
        }
    }
}
