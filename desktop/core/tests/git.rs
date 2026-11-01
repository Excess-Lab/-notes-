// Поведение — по образцу NotesCore/Tests/NotesCoreTests/GitVaultTests.swift.

use notes_core::git::{self, Change, History, Kind};
use std::fs;

#[test]
fn prepare_commits_and_messages() {
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("план.md"), "a\n").unwrap();
    let (h, created) = History::prepare(dir.path()).unwrap();
    assert!(created);
    assert_eq!(h.commit_count(), 1, "initial commit");
    assert!(dir.path().join(".gitignore").exists());
    let repo = git2::Repository::open(dir.path()).unwrap();
    assert_eq!(repo.head().unwrap().shorthand(), Some("main"));
    let config = repo.config().unwrap().snapshot().unwrap();
    assert_eq!(config.get_str("user.name").unwrap(), "notes");
    assert!(!config.get_bool("core.autocrlf").unwrap());

    assert_eq!(h.commit_now().unwrap(), None, "nothing to commit");
    fs::write(dir.path().join("план.md"), "b\n").unwrap();
    fs::write(dir.path().join("идеи.md"), "x\n").unwrap();
    fs::write(dir.path().join("видео.mp4"), "x").unwrap();
    assert_eq!(h.commit_now().unwrap().as_deref(), Some("правки: план.md, +1 новая"), "mp4 ignored");
    fs::remove_file(dir.path().join("идеи.md")).unwrap();
    assert_eq!(h.commit_now().unwrap().as_deref(), Some("удалена: идеи.md"));
    assert_eq!(h.commit_count(), 3);

    let (_, again) = History::prepare(dir.path()).unwrap();
    assert!(!again, "existing repo kept");
}

#[test]
fn existing_repo_keeps_gitignore() {
    let dir = tempfile::tempdir().unwrap();
    git2::Repository::init(dir.path()).unwrap();
    fs::write(dir.path().join(".gitignore"), "мой\n").unwrap();
    History::prepare(dir.path()).unwrap();
    assert_eq!(fs::read_to_string(dir.path().join(".gitignore")).unwrap(), "мой\n");
}

#[test]
fn message_like_mac() {
    let c = |p: &str, k| Change { path: p.into(), kind: k };
    assert_eq!(git::message(&[c("a/план.md", Kind::Modified)]), "правка: план.md");
    let five: Vec<_> = (0..5).map(|i| c(&format!("{i}.md"), Kind::Deleted)).collect();
    assert_eq!(git::message(&five), "удалены: 5 файлов");
    assert_eq!(git::message(&[c("a.md", Kind::Modified), c("b.md", Kind::Deleted), c("c.md", Kind::Deleted)]), "правки: a.md, −2 удалены");
    assert_eq!(git::plural(21, "файл", "файла", "файлов"), "файл");
    assert_eq!(git::plural(12, "файл", "файла", "файлов"), "файлов");
}

/// Два компьютера и сервер (голый репозиторий в папке): правки уходят и приходят, конфликт не теряет текста.
#[test]
fn push_pull_and_conflict_copy() {
    let server = tempfile::tempdir().unwrap();
    git2::Repository::init_bare(server.path()).unwrap();
    let url = server.path().to_str().unwrap().to_string();

    let a = tempfile::tempdir().unwrap();
    fs::write(a.path().join("план.md"), "первая строка\n").unwrap();
    let (ha, _) = History::prepare(a.path()).unwrap();
    ha.set_remote(&url).unwrap();
    assert!(ha.has_unpushed());
    ha.push(None).unwrap();
    assert!(!ha.has_unpushed());

    // Второй компьютер: пустая папка, история приходит с сервера.
    let b = tempfile::tempdir().unwrap();
    let (hb, _) = History::prepare(b.path()).unwrap();
    hb.set_remote(&url).unwrap();
    let first = hb.pull(None, "2026-11-01").unwrap();
    assert!(matches!(first, git::Pull::Merged { .. } | git::Pull::FastForward), "{first:?}");
    assert_eq!(fs::read_to_string(b.path().join("план.md")).unwrap(), "первая строка\n");
    hb.push(None).unwrap();
    assert_eq!(ha.pull(None, "2026-11-01").unwrap(), git::Pull::FastForward);

    // Обе стороны правят одну заметку по-разному.
    fs::write(a.path().join("план.md"), "версия A\n").unwrap();
    ha.commit_now().unwrap();
    ha.push(None).unwrap();
    fs::write(b.path().join("план.md"), "версия B\n").unwrap();
    fs::write(b.path().join("новая.md"), "только на B\n").unwrap();
    let merged = hb.pull(None, "2026-11-02").unwrap();
    assert_eq!(merged, git::Pull::Merged { conflicts: vec!["план.md".into()] });
    assert_eq!(fs::read_to_string(b.path().join("план.md")).unwrap(), "версия B\n", "ours stays in place");
    assert_eq!(fs::read_to_string(b.path().join("план (конфликт 2026-11-02).md")).unwrap(), "версия A\n", "theirs kept next to it");
    assert!(b.path().join("новая.md").exists());
    assert!(hb.changes().unwrap().is_empty(), "working tree matches the merge commit");
}
