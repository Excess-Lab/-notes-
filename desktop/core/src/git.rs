//! История хранилища в git — как `GitVault.swift` на маке: репозиторий в папке заметок, ветка `main`,
//! автор `notes <notes@local>` в конфиге самого репозитория (глобальный конфиг git не трогаем),
//! `core.autocrlf=false`, чтобы Windows не превращал LF в CRLF и мак не видел «правки» во всех файлах.
//! Коммит — всё изменённое, новое и удалённое; пустых коммитов не делаем.

use std::path::Path;

use git2::{IndexAddOption, Repository, RepositoryInitOptions, Signature, Status, StatusOptions};
use serde::Serialize;

pub const BRANCH: &str = "main";
pub const AUTHOR: &str = "notes";
pub const EMAIL: &str = "notes@local";
pub const INITIAL: &str = "начало истории";

/// Что не попадает в историю: служебное ОС, корзина, тяжёлые медиа. Мак пишет то же, плюс мусор Windows.
pub const GITIGNORE: &str = "# создано <notes>\n.DS_Store\nThumbs.db\ndesktop.ini\n.trash/\n*.mp4\n*.mov\n*.m4a\n*.mp3\n*.wav\n";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Added,
    Modified,
    Deleted,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Change {
    pub path: String,
    pub kind: Kind,
}

pub struct History {
    repo: Repository,
}

pub fn is_repository(folder: &Path) -> bool {
    folder.join(".git").exists()
}

impl History {
    /// Открыть репозиторий в папке или создать новый с первым коммитом. `true` — создан сейчас.
    /// Папка уже была репозиторием — его историю и `.gitignore` не трогаем, только `autocrlf`.
    pub fn prepare(folder: &Path) -> Result<(Self, bool), git2::Error> {
        if is_repository(folder) {
            let repo = Repository::open(folder)?;
            repo.config()?.set_bool("core.autocrlf", false)?;
            return Ok((Self { repo }, false));
        }
        let mut options = RepositoryInitOptions::new();
        options.initial_head(BRANCH).mkpath(true);
        let repo = Repository::init_opts(folder, &options)?;
        {
            let mut config = repo.config()?;
            config.set_str("user.name", AUTHOR)?;
            config.set_str("user.email", EMAIL)?;
            config.set_bool("core.autocrlf", false)?;
        }
        let ignore = folder.join(".gitignore");
        if !ignore.exists() {
            std::fs::write(&ignore, GITIGNORE).map_err(|e| git2::Error::from_str(&e.to_string()))?;
        }
        let history = Self { repo };
        history.commit_all(INITIAL)?;
        Ok((history, true))
    }

    pub fn open(folder: &Path) -> Result<Self, git2::Error> {
        Ok(Self { repo: Repository::open(folder)? })
    }

    /// Новые, изменённые и удалённые файлы — без игнорируемых. Для подписи коммита.
    pub fn changes(&self) -> Result<Vec<Change>, git2::Error> {
        let mut options = StatusOptions::new();
        options.include_untracked(true).recurse_untracked_dirs(true).include_ignored(false);
        let mut out: Vec<Change> = self
            .repo
            .statuses(Some(&mut options))?
            .iter()
            .filter_map(|e| {
                let s = e.status();
                let kind = if s.intersects(Status::WT_NEW | Status::INDEX_NEW) {
                    Kind::Added
                } else if s.intersects(Status::WT_DELETED | Status::INDEX_DELETED) {
                    Kind::Deleted
                } else if s.intersects(Status::WT_MODIFIED | Status::INDEX_MODIFIED | Status::WT_RENAMED | Status::INDEX_RENAMED | Status::WT_TYPECHANGE) {
                    Kind::Modified
                } else {
                    return None;
                };
                Some(Change { path: e.path()?.to_string(), kind })
            })
            .collect();
        out.sort_by(|a, b| a.path.cmp(&b.path));
        Ok(out)
    }

    /// Как `git add -A && git commit`. `false` — менять было нечего.
    pub fn commit_all(&self, message: &str) -> Result<bool, git2::Error> {
        let mut index = self.repo.index()?;
        index.add_all(["*"], IndexAddOption::DEFAULT, None)?;
        index.update_all(["*"], None)?;
        index.write()?;
        let tree_id = index.write_tree()?;
        let parent = self.repo.head().ok().and_then(|h| h.peel_to_commit().ok());
        if parent.as_ref().is_some_and(|p| p.tree_id() == tree_id) {
            return Ok(false);
        }
        let tree = self.repo.find_tree(tree_id)?;
        let me = Signature::now(AUTHOR, EMAIL)?;
        let parents: Vec<&git2::Commit> = parent.iter().collect();
        self.repo.commit(Some("HEAD"), &me, &me, message, &tree, &parents)?;
        Ok(true)
    }

    /// Закоммитить, если есть что, с подписью по изменениям. Возвращает подпись коммита.
    pub fn commit_now(&self) -> Result<Option<String>, git2::Error> {
        let changes = self.changes()?;
        if changes.is_empty() {
            return Ok(None);
        }
        let message = message(&changes);
        Ok(self.commit_all(&message)?.then_some(message))
    }

    /// Время последнего коммита, секунды с 1970.
    pub fn last_commit(&self) -> Option<i64> {
        Some(self.repo.head().ok()?.peel_to_commit().ok()?.time().seconds())
    }

    pub fn commit_count(&self) -> usize {
        let Ok(mut walk) = self.repo.revwalk() else { return 0 };
        if walk.push_head().is_err() {
            return 0;
        }
        walk.count()
    }
}

/// Подпись автокоммита, как `CommitMessage` на маке: «новая: идеи.md», «правки: план.md, идеи.md»,
/// «удалены: 5 файлов», «правки: план.md, +1 новая, −2 удалены».
pub fn message(changes: &[Change]) -> String {
    let names = |k: Kind| -> Vec<&str> {
        changes.iter().filter(|c| c.kind == k).map(|c| c.path.rsplit('/').next().unwrap_or(&c.path)).collect()
    };
    let (added, modified, deleted) = (names(Kind::Added), names(Kind::Modified), names(Kind::Deleted));
    for (list, one, many) in [(&modified, "правка", "правки"), (&added, "новая", "новые"), (&deleted, "удалена", "удалены")] {
        if !list.is_empty() && list.len() == changes.len() {
            let prefix = if list.len() == 1 { one } else { many };
            return if list.len() <= 3 {
                format!("{prefix}: {}", list.join(", "))
            } else {
                format!("{prefix}: {} {}", list.len(), plural(list.len(), "файл", "файла", "файлов"))
            };
        }
    }
    if changes.is_empty() {
        return "правка".into();
    }
    let mut parts = Vec::new();
    if !modified.is_empty() {
        parts.push(if modified.len() <= 2 { modified.join(", ") } else { format!("{} {}", modified.len(), plural(modified.len(), "файл", "файла", "файлов")) });
    }
    if !added.is_empty() {
        parts.push(format!("+{} {}", added.len(), plural(added.len(), "новая", "новые", "новых")));
    }
    if !deleted.is_empty() {
        parts.push(format!("−{} {}", deleted.len(), plural(deleted.len(), "удалена", "удалены", "удалено")));
    }
    format!("правки: {}", parts.join(", "))
}

pub fn plural(n: usize, one: &'static str, few: &'static str, many: &'static str) -> &'static str {
    if (11..=14).contains(&(n % 100)) {
        return many;
    }
    match n % 10 {
        1 => one,
        2..=4 => few,
        _ => many,
    }
}
