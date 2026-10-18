import Foundation
import Testing
@testable import NotesCore

private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("git в папке хранилища")
struct GitVaultTests {
    @Test("новая папка: репозиторий на ветке main, .gitignore и первый коммит")
    func createsRepository() throws {
        let folder = try tempFolder()
        try "привет".write(to: folder.appendingPathComponent("заметка.md"), atomically: true, encoding: .utf8)

        let (vault, created) = try GitVault.prepare(at: folder)

        #expect(created)
        // libgit2 по умолчанию создаёт master — проверяем, что ветка именно main.
        #expect(vault.headReference == "refs/heads/main")
        #expect(vault.commitCount == 1)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".gitignore").path))
    }

    @Test("папка уже репозиторий: заново не создаём и историю не трогаем")
    func keepsExistingRepository() throws {
        let folder = try tempFolder()
        let first = try GitVault.prepare(at: folder).vault
        try "текст".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try first.commitAll(message: "правка")

        let (again, created) = try GitVault.prepare(at: folder)

        #expect(!created)
        #expect(again.commitCount == 2)
    }

    @Test("свой .gitignore пользователя не перезаписываем")
    func keepsUserGitignore() throws {
        let folder = try tempFolder()
        let ignore = folder.appendingPathComponent(".gitignore")
        try "мой список\n".write(to: ignore, atomically: true, encoding: .utf8)

        _ = try GitVault.prepare(at: folder)

        #expect(try String(contentsOf: ignore, encoding: .utf8) == "мой список\n")
    }

    @Test("без изменений коммит не создаётся")
    func skipsEmptyCommit() throws {
        let (vault, _) = try GitVault.prepare(at: try tempFolder())

        #expect(try vault.commitAll(message: "пусто") == false)
        #expect(vault.commitCount == 1)
    }

    @Test("новый, изменённый и удалённый файл попадают в коммит")
    func commitsAllChangeKinds() throws {
        let folder = try tempFolder()
        let note = folder.appendingPathComponent("a.md")
        try "1".write(to: note, atomically: true, encoding: .utf8)
        let (vault, _) = try GitVault.prepare(at: folder)

        try "2".write(to: note, atomically: true, encoding: .utf8)
        #expect(try vault.commitAll(message: "изменили"))

        // Удаление заметки — тоже правка: без неё в истории осталась бы заметка, которой уже нет.
        try FileManager.default.removeItem(at: note)
        #expect(try vault.commitAll(message: "удалили"))
        #expect(try vault.commitAll(message: "повтор") == false)
        #expect(vault.commitCount == 3)
    }

    @Test("видео и служебные файлы не попадают в историю")
    func ignoresMediaAndJunk() throws {
        let folder = try tempFolder()
        let (vault, _) = try GitVault.prepare(at: folder)

        try Data([0, 1, 2]).write(to: folder.appendingPathComponent("созвон.mp4"))
        try Data().write(to: folder.appendingPathComponent(".DS_Store"))

        #expect(try vault.commitAll(message: "медиа") == false)
    }

    @Test("push отправляет текущую ветку в удалённый репозиторий")
    func pushesToRemote() throws {
        let folder = try tempFolder()
        try "заметка".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        let (vault, _) = try GitVault.prepare(at: folder)

        // Вместо GitHub — пустой bare-репозиторий на диске: протокол тот же, авторизация не нужна.
        let remote = try tempFolder()
        _ = try GitVault.prepareBare(at: remote)
        try vault.setRemote(remote.path)
        try vault.push(token: nil)

        let pushed = remote.appendingPathComponent("refs/heads/main")
        #expect(FileManager.default.fileExists(atPath: pushed.path))
    }

    @Test("remote origin можно поменять, не создавая второй")
    func replacesRemote() throws {
        let (vault, _) = try GitVault.prepare(at: try tempFolder())

        try vault.setRemote("https://github.com/a/notes.git")
        try vault.setRemote("https://github.com/b/notes.git")

        #expect(vault.remoteURL() == "https://github.com/b/notes.git")
    }
}
