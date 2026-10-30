import AppKit
import SwiftUI

// Текст заметки — обычный Markdown, но оформленный прямо при наборе: строка «## Что делаем» —
// полужирный заголовок 20, как в кадре 7:34. Знаки «#» остаются (файл не меняется), только бледнеют.
// SwiftUI-шный TextEditor так не умеет — внутри системный NSTextView (как в Заметках и TextEdit).
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let view = scroll.documentView as! NSTextView
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.typingAttributes = Style.body
        view.string = text
        Style.apply(to: view.textStorage)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let view = scroll.documentView as! NSTextView
        // Текст поменялся не из редактора (открыли другую заметку, файл обновили снаружи).
        if view.string != text {
            view.string = text
            Style.apply(to: view.textStorage)
            // Другая заметка — старые шаги отмены к ней не относятся.
            context.coordinator.undo.removeAllActions()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        // Свой стек отмены у каждого редактора. С общим стеком окна ⌘Z после смены заметки звал
        // уже закрытый редактор — приложение падало (отчёты 30.10.2026, PITFALLS.md).
        let undo = UndoManager()
        init(text: Binding<String>) { self.text = text }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            Style.apply(to: view.textStorage)
            text.wrappedValue = view.string
        }
    }

    enum Style {
        static let ink = NSColor(Theme.ink)
        // Текст — «заметка/текст»: Std Rg 15, трекинг −7 %, межстрочный как в макете.
        static var body: [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = 6
            return [.font: NSFont(name: Martian.body.rawValue, size: 15) ?? .systemFont(ofSize: 15),
                    .kern: Theme.tracking(-7, size: 15), .foregroundColor: ink, .paragraphStyle: paragraph]
        }

        // Заголовки «#», «##», «###» — полужирные 24 / 20 / 17, как «Что делаем» в макете (Semibold 20).
        static func apply(to storage: NSTextStorage?) {
            guard let storage else { return }
            let string = storage.string as NSString
            storage.beginEditing()
            storage.setAttributes(body, range: NSRange(location: 0, length: string.length))
            string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byLines) { line, range, _, _ in
                guard let line, line.hasPrefix("#") else { return }
                let level = line.prefix { $0 == "#" }.count
                guard (1...3).contains(level), line.dropFirst(level).hasPrefix(" ") else { return }
                let size: CGFloat = [24, 20, 17][level - 1]
                storage.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: .semibold),
                                       .kern: Theme.tracking(-2, size: size)], range: range)
                storage.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.25),
                                     range: NSRange(location: range.location, length: level + 1))
            }
            storage.endEditing()
        }
    }
}
