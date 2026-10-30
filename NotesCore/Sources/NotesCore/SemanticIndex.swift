import Foundation
import NaturalLanguage

// Вектор текста: что-то, что превращает кусок текста в числа так, что близкие по смыслу куски
// дают близкие векторы. В приложении — встроенная модель Apple, в тестах — заглушка.
public protocol Embedder: Sendable {
    func vector(for text: String) throws -> [Float]
}

// Встроенная в macOS модель (NLContextualEmbedding): в сборку ничего не кладём, ресурсы система
// докачивает сама один раз. Вектор куска — среднее векторов его слов.
public final class AppleEmbedder: Embedder, @unchecked Sendable {
    private let model: NLContextualEmbedding
    private let lock = NSLock()

    public init?() {
        guard let model = NLContextualEmbedding(language: .russian) else { return nil }
        self.model = model
    }

    public var ready: Bool { model.hasAvailableAssets }

    private var loaded = false

    // Модель грузим один раз: повторный load() на каждое обновление индекса не нужен.
    public func prepare() async throws {
        if lock.withLock({ loaded }) { return }
        if !model.hasAvailableAssets {
            _ = try await model.requestAssets()
        }
        try lock.withLock {
            guard !loaded else { return }
            try model.load()
            loaded = true
        }
    }

    public func vector(for text: String) throws -> [Float] {
        try lock.withLock {
            let result = try model.embeddingResult(for: text, language: .russian)
            var sum = [Float](repeating: 0, count: model.dimension)
            var count = 0
            result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
                for i in 0..<min(vector.count, sum.count) { sum[i] += Float(vector[i]) }
                count += 1
                return true
            }
            return count == 0 ? sum : sum.map { $0 / Float(count) }
        }
    }
}

// Индекс по смыслу: заметки режутся на куски (абзацы до ~600 знаков), у каждого куска — вектор.
// Это кэш (CLAUDE.md): лежит вне хранилища, пересобирается из файлов, пересчитываются только
// изменившиеся заметки (по дате изменения).
public final class SemanticIndex: @unchecked Sendable {
    public struct Chunk: Codable, Sendable {
        public let text: String
        public let vector: [Float]
    }

    struct Entry: Codable {
        let modified: Date
        let chunks: [Chunk]
    }

    public struct Hit: Sendable {
        public let note: URL
        public let snippet: String
        public let score: Double
    }

    private var entries: [String: Entry] = [:]   // ключ — путь заметки
    private let lock = NSLock()
    private let store: URL?

    public init(store: URL? = nil) {
        self.store = store
        if let store, let data = try? Data(contentsOf: store) {
            entries = (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
        }
    }

    public var chunkCount: Int { lock.withLock { entries.values.reduce(0) { $0 + $1.chunks.count } } }

    // Абзацы; длинные — по предложениям до ~600 знаков. Заголовки и разметку задач не теряем — это тоже смысл.
    public static func chunks(of text: String) -> [String] {
        var result: [String] = []
        for paragraph in text.components(separatedBy: "\n\n") {
            let clean = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.count > 2 else { continue }
            if clean.count <= 600 { result.append(clean); continue }
            var current = ""
            for sentence in clean.split(separator: ".", omittingEmptySubsequences: true) {
                if current.count + sentence.count > 600, !current.isEmpty { result.append(current); current = "" }
                current += sentence + "."
            }
            if !current.isEmpty { result.append(current) }
        }
        return result
    }

    // Обновить индекс: удалить пропавшие заметки, посчитать новые и изменённые.
    @discardableResult
    public func update(library: NoteLibrary, embedder: Embedder) -> Int {
        let notes = library.allNotes(in: library.tree())
        let alive = Set(notes.map(\.url.path))
        var changed = 0
        lock.withLock { entries = entries.filter { alive.contains($0.key) } }
        for note in notes {
            if lock.withLock({ entries[note.url.path]?.modified == note.modified }) { continue }
            guard let text = library.text(of: note) else { continue }
            let pieces = Self.chunks(of: note.title + "\n\n" + text)
            let chunks = pieces.compactMap { piece in (try? embedder.vector(for: piece)).map { Chunk(text: piece, vector: $0) } }
            lock.withLock { entries[note.url.path] = Entry(modified: note.modified, chunks: chunks) }
            changed += 1
        }
        if changed > 0, let store {
            try? FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? lock.withLock { try JSONEncoder().encode(entries) }.write(to: store)
        }
        return changed
    }

    // Ближайшие по смыслу заметки: у заметки берём лучший кусок, он же — отрывок.
    public func search(_ query: String, embedder: Embedder, limit: Int = 8) -> [Hit] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty, let q = try? embedder.vector(for: query) else { return [] }
        let snapshot = lock.withLock { entries }
        var best: [Hit] = []
        for (path, entry) in snapshot {
            guard let top = entry.chunks.map({ ($0, Self.cosine(q, $0.vector)) }).max(by: { $0.1 < $1.1 }) else { continue }
            best.append(Hit(note: URL(fileURLWithPath: path), snippet: String(top.0.text.prefix(140)), score: top.1))
        }
        return Array(best.sorted { $0.score > $1.score }.prefix(limit))
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return na == 0 || nb == 0 ? 0 : Double(dot / (na.squareRoot() * nb.squareRoot()))
    }
}
