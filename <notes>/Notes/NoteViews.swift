import NotesCore
import SwiftUI

// Открытая заметка — кадр 7:34: заголовок xWd xBd 28 на x = 120 листа, под ним «изменено … · N слов»,
// текст Std Rg 15 шириной 660. Заголовок — имя файла: правка заголовка переименовывает файл.
struct NoteEditor: View {
    let model: NotesModel
    let url: URL
    @State private var title = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            // Заголовок — то, что ввёл человек: регистр не трогаем.
            TextField("без названия", text: $title)
                .textFieldStyle(.plain)
                .font(Martian.heading.font(28))
                .kerning(Theme.tracking(-7, size: 28))
                .foregroundStyle(Theme.ink)
                .focused($titleFocused)
                .onSubmit { model.rename(to: title) }
                .onChange(of: titleFocused) { _, focused in if !focused { model.rename(to: title) } }
            Text(meta)
                .font(Martian.body.font(11))
                .kerning(Theme.tracking(-7, size: 11))
                .foregroundStyle(NotesLayout.gray)
                .padding(.top, 10)
            MarkdownEditor(text: $model.text)
                .padding(.top, 28)
        }
        .frame(width: 660, alignment: .topLeading)
        .padding(.leading, 120 + 6)
        .padding(.top, 36)
        .onAppear {
            title = url.deletingPathExtension().lastPathComponent
            // Новую заметку сразу называем: курсор в заголовке.
            if model.text.isEmpty { titleFocused = true }
        }
    }

    private var meta: String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        return "изменено \(Self.date(modified)) · \(Self.words(NoteLibrary.wordCount(model.text)))"
    }

    // «сегодня в 14:20», «вчера в 9:05», «12 окт в 18:00».
    static func date(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDateInToday(date) { return "сегодня в \(time)" }
        if calendar.isDateInYesterday(date) { return "вчера в \(time)" }
        return "\(short(date)) в \(time)"
    }

    static func short(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "сегодня" }
        if calendar.isDateInYesterday(date) { return "вчера" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU")))
            .replacingOccurrences(of: ".", with: "")
    }

    static func words(_ count: Int) -> String { "\(count) \(plural(count, "слово", "слова", "слов"))" }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let tail = n % 100
        if (11...14).contains(tail) { return many }
        switch n % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}

// Папка — кадр «все заметки» (79:11295): карточки 184×176 по четыре в ряд через 28, «новая папка»,
// ниже «без папки» — заметки этого уровня строками.
struct FolderOverview: View {
    let model: NotesModel
    let folder: NoteLibrary.Folder
    @State private var naming = false
    @State private var newName = ""

    // Сколько папок в ряд — сколько влезает: окно тянется.
    private let columns = [GridItem(.adaptive(minimum: 184, maximum: 184), spacing: 28, alignment: .topLeading)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(folder.url == model.library.root ? "все заметки" : folder.name)
                    .font(Martian.heading.font(26))
                    .kerning(Theme.tracking(-7, size: 26))
                    .foregroundStyle(Theme.ink)
                Text("\(folder.folders.count) \(NoteEditor.plural(folder.folders.count, "папка", "папки", "папок")) | \(folder.noteCount) \(NoteEditor.plural(folder.noteCount, "заметка", "заметки", "заметок"))")
                    .font(Martian.body.font(13))
                    .kerning(Theme.tracking(-7, size: 13))
                    .foregroundStyle(NotesLayout.gray)
                    .padding(.top, 6)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                    ForEach(Array(folder.folders.enumerated()), id: \.element.id) { _, child in
                        Button { model.open(.folder(child.url)); model.expanded.insert(child.url) } label: {
                            FolderCard(name: child.name, count: child.noteCount)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { naming = true } label: { NewFolderCard() }
                        .buttonStyle(.plain)
                }
                .padding(.top, 46)

                if !folder.notes.isEmpty {
                    Text(folder.url == model.library.root ? "без папки" : "заметки")
                        .font(Martian.body.font(15))
                        .kerning(Theme.tracking(-7, size: 15))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 36)
                    VStack(spacing: 6) {
                        ForEach(folder.notes) { note in
                            Button { model.open(.note(note.url)) } label: { NoteRow(note: note) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 56 + 2)
            .padding(.trailing, 56)
            .padding(.top, 36)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.never)
        // Имени папки в макете поля ввода нет — спрашиваем системным окном, как Finder.
        .alert("Новая папка", isPresented: $naming) {
            TextField("Название", text: $newName)
            Button("Создать") { model.newFolder(named: newName); newName = "" }
            Button("Отмена", role: .cancel) { newName = "" }
        }
    }
}

// Карточка папки: форма с выступом слева (контур из макета, скругление 20, чёрный 6 %),
// под ней имя xWd xBd 15 и счётчик.
struct FolderCard: View {
    let name: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Наклейку с названием Макар убрал (26.10.2026): на папке только форма, имя — под ней.
            FolderShape().fill(Theme.fg.opacity(0.06))
                .frame(width: 184, height: 133)
            Text(name)
                .font(Martian.heading.font(15))
                .kerning(Theme.tracking(-7, size: 15))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.top, 6)
            Text("\(count) \(NoteEditor.plural(count, "заметка", "заметки", "заметок"))")
                .font(Martian.body.font(11))
                .kerning(Theme.tracking(-7, size: 11))
                .foregroundStyle(NotesLayout.gray)
                .padding(.top, 6)
        }
        .frame(width: 184, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// Контур папки из макета: выступ 63×31 слева, тело ниже, скругление 20.
struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 184, sy = rect.height / 133
        let tabRight = 62.9 * sx, step = 30.5 * sy, r: CGFloat = 20
        var path = Path()
        path.move(to: CGPoint(x: 0, y: r))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: tabRight, y: 0), radius: r)
        path.addArc(tangent1End: CGPoint(x: tabRight, y: 0), tangent2End: CGPoint(x: tabRight, y: step), radius: r)
        path.addArc(tangent1End: CGPoint(x: tabRight, y: step), tangent2End: CGPoint(x: rect.width, y: step), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.width, y: step), tangent2End: CGPoint(x: rect.width, y: rect.height), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.width, y: rect.height), tangent2End: CGPoint(x: 0, y: rect.height), radius: r)
        path.addArc(tangent1End: CGPoint(x: 0, y: rect.height), tangent2End: CGPoint(x: 0, y: 0), radius: r)
        path.closeSubpath()
        return path
    }
}

private struct NewFolderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                FolderShape().stroke(NotesLayout.line, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                DotIcon(glyph: .plus, size: 24).offset(y: 15)
            }
            .frame(width: 184, height: 133)
            Text("новая папка")
                .font(Martian.heading.font(15))
                .kerning(Theme.tracking(-7, size: 15))
                .foregroundStyle(NotesLayout.gray)
        }
        .contentShape(Rectangle())
    }
}

// Строка заметки «без папки»: иконка файла, название, дата справа, линия снизу.
private struct NoteRow: View {
    let note: NoteLibrary.Note

    var body: some View {
        HStack(spacing: 10) {
            DotIcon(glyph: .file)
            Text(note.title)
                .font(Martian.body.font(13))
                .kerning(Theme.tracking(-7, size: 13))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 10)
            Text(NoteEditor.short(note.modified))
                .font(Martian.body.font(11))
                .kerning(Theme.tracking(-7, size: 11))
                .foregroundStyle(NotesLayout.gray)
        }
        .padding(.horizontal, 4)
        .frame(height: 35)
        .overlay(alignment: .bottom) { Rectangle().fill(NotesLayout.line).frame(height: 1) }
        .contentShape(Rectangle())
    }
}

// Поиск поверх — переделан по просьбе Макара (27.10.2026): карточка шире, запрос крупным шрифтом
// заголовков, пока запрос пустой — недавние заметки, найденное слово в отрывке выделено, выбранная
// строка — мягкая подсветка, как в боковой панели, внизу подсказки клавиш.
struct SearchOverlay: View {
    @Bindable var model: NotesModel
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.black.opacity(0.12)).contentShape(Rectangle())
                .onTapGesture { model.searchShown = false }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    DotIcon(glyph: .search, size: 20)
                    TextField("найти в заметках", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(Martian.heading.font(20))
                        .foregroundStyle(Theme.ink)
                        .focused($focused)
                        .onSubmit { model.openHighlighted() }
                        .onKeyPress(.downArrow) { move(1) }
                        .onKeyPress(.upArrow) { move(-1) }
                        .onKeyPress(.escape) { model.searchShown = false; return .handled }
                    if !model.query.isEmpty {
                        Text("\(model.hits.count)")
                            .font(Martian.body.font(13)).foregroundStyle(NotesLayout.gray)
                    }
                }
                .padding(.horizontal, 22)
                .frame(height: 64)

                Rectangle().fill(NotesLayout.line).frame(height: 1)

                VStack(alignment: .leading, spacing: 2) {
                    if model.query.isEmpty {
                        Caption(text: "недавние")
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, note in
                            Button { model.open(.note(note.url)); model.searchShown = false } label: {
                                ResultRow(title: note.title, path: path(note.url), snippet: nil, word: nil, selected: false)
                            }.buttonStyle(.plain)
                        }
                    } else if model.hits.isEmpty {
                        Text("ничего не нашли — попробуй другие слова")
                            .font(Martian.body.font(13)).foregroundStyle(NotesLayout.gray)
                            .frame(maxWidth: .infinity).frame(height: 70)
                    } else {
                        ForEach(Array(model.hits.enumerated()), id: \.element.id) { index, hit in
                            Button { model.highlighted = index; model.openHighlighted() } label: {
                                ResultRow(title: hit.note.title, path: path(hit.note.url), snippet: hit.snippet,
                                          word: model.query.split(separator: " ").first.map(String.init),
                                          selected: index == model.highlighted)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(10)

                HStack(spacing: 16) {
                    Hint(key: "↑↓", text: "выбрать"); Hint(key: "enter", text: "открыть"); Hint(key: "esc", text: "закрыть")
                    Spacer()
                    Text("по тексту · по смыслу скоро")
                        .font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
                }
                .padding(.horizontal, 22)
                .frame(height: 38)
                .background(Theme.fg.opacity(0.03))
            }
            .frame(width: 720)
            .background(RoundedRectangle(cornerRadius: 28).fill(Theme.bg.opacity(0.78))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28)))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.edge.opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 40, y: 16)
            .padding(.top, 150)
        }
        .onAppear { focused = true }
    }

    private var recent: [NoteLibrary.Note] {
        Array(model.library.allNotes(in: model.tree).sorted { $0.modified > $1.modified }.prefix(5))
    }

    private func path(_ url: URL) -> String {
        let parts = model.library.breadcrumb(for: url).dropLast()
        return parts.isEmpty ? "без папки" : parts.joined(separator: " / ")
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !model.hits.isEmpty else { return .ignored }
        model.highlighted = (model.highlighted + delta + model.hits.count) % model.hits.count
        return .handled
    }
}

private struct Caption: View {
    let text: String
    var body: some View {
        Text(text).font(Martian.body.font(11)).foregroundStyle(Theme.fg.opacity(0.3))
            .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

private struct Hint: View {
    let key: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Keycap(text: key)
            Text(text).font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray)
        }
    }
}

private struct ResultRow: View {
    let title: String
    let path: String
    let snippet: String?
    let word: String?
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DotIcon(glyph: .file).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(Martian.body.font(14)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(path).font(Martian.body.font(11)).foregroundStyle(NotesLayout.gray).lineLimit(1)
                }
                if let snippet {
                    highlighted(snippet).font(Martian.body.font(13)).foregroundStyle(NotesLayout.gray).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.fg.opacity(selected ? 0.06 : 0)))
        .contentShape(Rectangle())
    }

    // Найденное слово в отрывке — тёмным, остальное серым.
    private func highlighted(_ text: String) -> Text {
        guard let word, !word.isEmpty,
              let range = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) else { return Text(text) }
        let head = String(text[..<range.lowerBound]), match = String(text[range]), tail = String(text[range.upperBound...])
        return Text("\(head)\(Text(match).foregroundStyle(Theme.ink))\(tail)")
    }
}
