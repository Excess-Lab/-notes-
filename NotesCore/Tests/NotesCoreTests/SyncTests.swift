import Foundation
import Testing
@testable import NotesCore

private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-sync-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, _ name: String, in folder: URL) throws {
    let url = folder.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

private func m(_ path: String) -> FileChange { FileChange(path: path, kind: .modified) }
private func n(_ path: String) -> FileChange { FileChange(path: path, kind: .added) }
private func d(_ path: String) -> FileChange { FileChange(path: path, kind: .deleted) }

@Suite("подпись автокоммита")
struct CommitMessageTests {
    @Test("одна изменённая заметка — её имя, без папок")
    func singleModified() {
        #expect(CommitMessage.make(for: [m("проекты/план приложения.md")]) == "правка: план приложения.md")
    }

    @Test("новая и удалённая заметка подписаны по-разному, а не обе «правка»")
    func addedAndDeleted() {
        #expect(CommitMessage.make(for: [n("идеи.md")]) == "новая: идеи.md")
        #expect(CommitMessage.make(for: [d("старое.md")]) == "удалена: старое.md")
        #expect(CommitMessage.make(for: [d("a.md"), d("b.md")]) == "удалены: a.md, b.md")
    }

    @Test("много одного вида — число с правильным окончанием")
    func manyOfOneKind() {
        #expect(CommitMessage.make(for: (1...5).map { m("\($0).md") }) == "правки: 5 файлов")
        #expect(CommitMessage.make(for: (1...4).map { n("\($0).md") }) == "новые: 4 файла")
    }

    @Test("вперемешку — изменённые по именам, новые и удалённые числом")
    func mixed() {
        #expect(CommitMessage.make(for: [m("план.md"), n("идеи.md"), d("a.md"), d("b.md")])
                == "правки: план.md, +1 новая, −2 удалены")
        #expect(CommitMessage.make(for: [n("a.md"), n("b.md"), n("c.md"), n("e.md"), n("f.md"), d("x.md")])
                == "правки: +5 новых, −1 удалена")
    }

    @Test("склонение: 1, 2, 5, 11, 21")
    func plurals() {
        #expect(CommitMessage.files(1) == "файл")
        #expect(CommitMessage.files(2) == "файла")
        #expect(CommitMessage.files(5) == "файлов")
        // 11–14 — исключение: «11 файлов», а не «11 файл».
        #expect(CommitMessage.files(11) == "файлов")
        #expect(CommitMessage.files(21) == "файл")
    }
}

@Suite("когда отправлять на github")
struct PushScheduleTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("ещё ни разу не отправляли — пора")
    func neverPushed() { #expect(PushSchedule.isDue(lastPush: nil, now: now)) }

    @Test("прошло меньше суток — ждём")
    func lessThanDay() { #expect(!PushSchedule.isDue(lastPush: now.addingTimeInterval(-23 * 3600), now: now)) }

    @Test("прошли сутки — пора")
    func dayPassed() { #expect(PushSchedule.isDue(lastPush: now.addingTimeInterval(-24 * 3600), now: now)) }

    @Test("свой интервал из настроек: раз в час")
    func customInterval() {
        #expect(PushSchedule.isDue(lastPush: now.addingTimeInterval(-3600), now: now, every: 3600))
        #expect(!PushSchedule.isDue(lastPush: now.addingTimeInterval(-3000), now: now, every: 3600))
    }
}

@Suite("синхронизация хранилища")
struct SyncEngineTests {
    @Test("изменённые файлы: новые, правленые и удалённые, без игнорируемых")
    func detectsChangeKinds() throws {
        let folder = try tempFolder()
        try write("1", "old.md", in: folder)
        try write("1", "edit.md", in: folder)
        let (vault, _) = try GitVault.prepare(at: folder)

        try write("2", "edit.md", in: folder)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("old.md"))
        try write("new", "папка/new.md", in: folder)
        try Data([1]).write(to: folder.appendingPathComponent("созвон.mp4"))

        #expect(try vault.changes() == [FileChange(path: "edit.md", kind: .modified),
                                        FileChange(path: "old.md", kind: .deleted),
                                        FileChange(path: "папка/new.md", kind: .added)])
    }

    @Test("подпись коммита — по изменённой заметке")
    func commitMessage() async throws {
        let folder = try tempFolder()
        _ = try GitVault.prepare(at: folder)
        try write("текст", "план.md", in: folder)

        #expect(try await SyncEngine(folder: folder).commitNow() == "новая: план.md")
        #expect(try await SyncEngine(folder: folder).commitNow() == nil)
    }

    @Test("отправка: только когда пора и есть что отправлять")
    func pushesWhenDue() async throws {
        let folder = try tempFolder()
        try write("1", "a.md", in: folder)
        let (vault, _) = try GitVault.prepare(at: folder)
        let remote = try tempFolder()
        _ = try GitVault.prepareBare(at: remote)
        try vault.setRemote(remote.path)
        let engine = SyncEngine(folder: folder)
        let now = Date()

        // Отправляли час назад — рано, даже если есть новые коммиты.
        #expect(try await engine.pushIfDue(token: nil, lastPush: now.addingTimeInterval(-3600), now: now) == false)
        #expect(try await engine.pushIfDue(token: nil, lastPush: nil, now: now))
        #expect(FileManager.default.fileExists(atPath: remote.appendingPathComponent("refs/heads/main").path))
        // Всё уже на сервере — второй раз не отправляем, даже если «пора».
        #expect(try await engine.pushIfDue(token: nil, lastPush: nil, now: now) == false)
    }

    @Test("без remote не отправляем и не падаем")
    func noRemote() async throws {
        let folder = try tempFolder()
        _ = try GitVault.prepare(at: folder)

        #expect(try await SyncEngine(folder: folder).pushIfDue(token: nil, lastPush: nil) == false)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

@Suite("слежка за папкой")
struct FolderWatcherTests {
    @Test("правка заметки будит синхронизацию")
    func seesNoteChange() async throws {
        let folder = try tempFolder()
        let counter = Counter()
        let watcher = FolderWatcher(folder: folder) { counter.increment() }

        try await Task.sleep(for: .milliseconds(300))
        try write("текст", "заметка.md", in: folder)
        try await Task.sleep(for: .seconds(2))

        #expect(counter.count > 0)
        _ = watcher
    }

    @Test("собственные коммиты в .git не будят синхронизацию — иначе коммит будил бы сам себя")
    func ignoresGitFolder() {
        #expect(FolderWatcher.isInternal("/vault/.git/index"))
        #expect(FolderWatcher.isInternal("/vault/.git"))
        #expect(!FolderWatcher.isInternal("/vault/заметки/.gitkeep.md"))
    }
}
