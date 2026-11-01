// Поведение — по образцу NotesCore/Tests/NotesCoreTests/NoteLibraryTests.swift.

use notes_core::{Vault, VaultError};
use std::fs;

fn vault() -> (tempfile::TempDir, Vault) {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    fs::create_dir_all(root.join("проекты/вложенная")).unwrap();
    fs::create_dir_all(root.join(".git")).unwrap();
    fs::write(root.join(".git/config"), "x").unwrap();
    fs::write(root.join("Входящие.md"), "- [ ] купить хлеб 📅 2026-11-02\n").unwrap();
    fs::write(root.join("проекты/план 10.md"), "# План\n").unwrap();
    fs::write(root.join("проекты/план 2.md"), "- [x] сделано\n").unwrap();
    fs::write(root.join("проекты/вложенная/идея.md"), "").unwrap();
    fs::write(root.join("проекты/фото.png"), [0u8]).unwrap();
    fs::write(root.join("проекты/скрипт.sh"), "").unwrap();
    let vault = Vault::open(root).unwrap();
    (dir, vault)
}

#[test]
fn tree_skips_hidden_and_counts_notes() {
    let (_d, v) = vault();
    let tree = v.tree();
    assert_eq!(tree.folders.len(), 1, ".git hidden");
    assert_eq!(tree.note_count, 4);
    let projects = &tree.folders[0];
    assert_eq!(projects.path, "проекты");
    let titles: Vec<_> = projects.notes.iter().map(|n| n.title.as_str()).collect();
    assert_eq!(titles, ["план 2", "план 10"], "natural order like Finder");
    assert_eq!(projects.files.len(), 1, "png shown, sh skipped");
    assert_eq!(projects.folders[0].notes[0].path, "проекты/вложенная/идея.md");
}

#[test]
fn write_keeps_line_endings() {
    let (d, v) = vault();
    fs::write(d.path().join("crlf.md"), "a\r\nb\r\n").unwrap();
    v.write("crlf.md", "a\nb\nc\n").unwrap();
    assert_eq!(fs::read(d.path().join("crlf.md")).unwrap(), b"a\r\nb\r\nc\r\n");

    v.write("Входящие.md", "x\r\ny\r\n").unwrap();
    assert_eq!(fs::read_to_string(d.path().join("Входящие.md")).unwrap(), "x\ny\n", "LF stays LF");
}

#[test]
fn no_escape_from_vault() {
    let (_d, v) = vault();
    assert!(matches!(v.read("../secret.md"), Err(VaultError::OutsideVault)));
    assert!(matches!(v.write("../x.md", ""), Err(VaultError::OutsideVault)));
    assert!(matches!(v.read("нет.md"), Err(VaultError::NotFound)));
}

#[test]
fn create_note_picks_free_name() {
    let (_d, v) = vault();
    assert_eq!(v.create_note("проекты", "план 2").unwrap(), "проекты/план 2 2.md");
    assert_eq!(v.create_note("", "Новая заметка").unwrap(), "Новая заметка.md");
    assert_eq!(v.create_note("", "Новая заметка").unwrap(), "Новая заметка 2.md");
    assert!(matches!(v.create_note("", "a:b"), Err(VaultError::BadName(_))));
}

#[test]
fn tasks_from_all_notes() {
    let (_d, v) = vault();
    let tasks = v.tasks();
    assert_eq!(tasks.len(), 2);
    let bread = tasks.iter().find(|(p, _)| p == "Входящие.md").unwrap();
    assert_eq!(bread.1.date.as_deref(), Some("2026-11-02"));
    assert!(tasks.iter().any(|(p, t)| p == "проекты/план 2.md" && t.done));
}

#[test]
fn rename_keeps_folder_and_avoids_clash() {
    let (d, v) = vault();
    assert_eq!(v.rename("проекты/план 10.md", "план 2").unwrap(), "проекты/план 2 2.md");
    assert!(d.path().join("проекты/план 2 2.md").exists());
    assert_eq!(v.rename("проекты/план 2 2.md", "  итог ").unwrap(), "проекты/итог.md");
    assert_eq!(v.rename("проекты/итог.md", "итог").unwrap(), "проекты/итог.md", "same name is a no-op");
    assert!(matches!(v.rename("проекты/итог.md", "a/b"), Err(VaultError::BadName(_))));
}

#[test]
fn search_all_words_title_first() {
    let (d, v) = vault();
    fs::write(d.path().join("хлеб.md"), "просто так").unwrap();
    let hits = v.search("ХЛЕБ", 10);
    assert_eq!(hits.len(), 2);
    assert_eq!(hits[0].note.title, "хлеб", "title match ranks higher");
    assert_eq!(hits[1].snippet, "купить хлеб");
    assert!(v.search("хлеб сделано", 10).is_empty(), "all words must match");
    assert!(v.search("  ", 10).is_empty());
}
