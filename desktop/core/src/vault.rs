//! Хранилище — обычная папка с `.md`. Как `NoteLibrary` на маке
//! (`NotesCore/Sources/NotesCore/NoteLibrary.swift`): скрытое (`.git`, служебные папки других программ)
//! не показываем и не трогаем, порядок — по имени без учёта регистра.

use serde::Serialize;
use std::cmp::Ordering;
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};

use crate::names::{compare_key, windows_problem};
use crate::tasks::{tasks_in, Task};

/// Файлы, которые показываем просмотром (как `NoteLibrary.viewable`).
pub const VIEWABLE: &[&str] = &[
    "pdf", "doc", "docx", "rtf", "pages", "key", "numbers", "xls", "xlsx", "ppt", "pptx", "txt", "csv",
    "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "svg", "mp4", "mov", "m4v", "mp3", "m4a", "wav",
    "aiff", "flac",
];

#[derive(Debug)]
pub enum VaultError {
    Io(io::Error),
    /// Путь выходит за пределы хранилища (`..`, абсолютный путь).
    OutsideVault,
    /// Имя не создать на этой ОС — показать человеку, файл не трогать.
    BadName(&'static str),
    NotFound,
}

impl std::fmt::Display for VaultError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            VaultError::Io(e) => write!(f, "{e}"),
            VaultError::OutsideVault => write!(f, "path is outside the vault"),
            VaultError::BadName(why) => write!(f, "bad file name: {why}"),
            VaultError::NotFound => write!(f, "not found"),
        }
    }
}

impl std::error::Error for VaultError {}

impl From<io::Error> for VaultError {
    fn from(e: io::Error) -> Self {
        if e.kind() == io::ErrorKind::NotFound { VaultError::NotFound } else { VaultError::Io(e) }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Note {
    /// Путь от корня хранилища через `/` — одинаковый на обеих ОС.
    pub path: String,
    pub title: String,
    /// Секунды с 1970 года.
    pub modified: u64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Entry {
    pub path: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Folder {
    pub path: String,
    pub name: String,
    pub folders: Vec<Folder>,
    pub notes: Vec<Note>,
    pub files: Vec<Entry>,
    /// Заметок внутри вместе с вложенными папками.
    pub note_count: usize,
    /// Файлы, которые на этой ОС не открыть (имя с мака) — показать человеку списком.
    pub unreadable: Vec<Entry>,
}

#[derive(Debug, Clone)]
pub struct Vault {
    root: PathBuf,
}

impl Vault {
    pub fn open(root: impl Into<PathBuf>) -> Result<Self, VaultError> {
        let root = root.into();
        if !root.is_dir() {
            return Err(VaultError::NotFound);
        }
        Ok(Self { root })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn tree(&self) -> Folder {
        self.folder(&self.root, "")
    }

    fn folder(&self, dir: &Path, rel: &str) -> Folder {
        let mut folders = Vec::new();
        let mut notes = Vec::new();
        let mut files = Vec::new();
        let mut unreadable = Vec::new();
        for item in fs::read_dir(dir).into_iter().flatten().flatten() {
            let name = item.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') {
                continue;
            }
            let path = join(rel, &name);
            if cfg!(windows) {
                if let Some(_why) = windows_problem(&name) {
                    unreadable.push(Entry { path, name });
                    continue;
                }
            }
            let Ok(meta) = item.metadata() else { continue };
            if meta.is_dir() {
                folders.push(self.folder(&item.path(), &path));
                continue;
            }
            let ext = Path::new(&name).extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
            if ext == "md" {
                let modified = meta
                    .modified()
                    .ok()
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map_or(0, |d| d.as_secs());
                let title = name[..name.len() - 3].to_string();
                notes.push(Note { path, title, modified });
            } else if VIEWABLE.contains(&ext.as_str()) {
                files.push(Entry { path, name });
            }
        }
        folders.sort_by(|a, b| by_name(&a.name, &b.name));
        notes.sort_by(|a, b| by_name(&a.title, &b.title));
        files.sort_by(|a, b| by_name(&a.name, &b.name));
        let note_count = notes.len() + folders.iter().map(|f| f.note_count).sum::<usize>();
        let name = if rel.is_empty() {
            self.root.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
        } else {
            rel.rsplit('/').next().unwrap_or(rel).to_string()
        };
        Folder { path: rel.to_string(), name, folders, notes, files, note_count, unreadable }
    }

    /// Абсолютный путь внутри хранилища. `..` и абсолютные пути не пускаем.
    pub fn resolve(&self, rel: &str) -> Result<PathBuf, VaultError> {
        let mut out = self.root.clone();
        for part in Path::new(rel).components() {
            match part {
                Component::Normal(p) => out.push(p),
                Component::CurDir => {}
                _ => return Err(VaultError::OutsideVault),
            }
        }
        Ok(out)
    }

    /// Текст заметки. Концы строк — как в файле.
    pub fn read(&self, rel: &str) -> Result<String, VaultError> {
        Ok(fs::read_to_string(self.resolve(rel)?)?)
    }

    /// Записать заметку, сохранив концы строк файла: пришёл с LF — останется LF, даже если
    /// поле ввода на Windows вернуло CRLF. Пишем через временный файл, чтобы сбой не оставил полфайла.
    pub fn write(&self, rel: &str, text: &str) -> Result<(), VaultError> {
        let path = self.resolve(rel)?;
        if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
            if let Some(why) = windows_problem(name) {
                return Err(VaultError::BadName(why));
            }
        }
        let crlf = match fs::read(&path) {
            Ok(old) => old.windows(2).any(|w| w == b"\r\n"),
            Err(_) => false,
        };
        let lf = text.replace("\r\n", "\n");
        let body = if crlf { lf.replace('\n', "\r\n") } else { lf };
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("md.tmp-notes");
        fs::write(&tmp, body)?;
        fs::rename(&tmp, &path)?;
        Ok(())
    }

    /// Новая заметка в папке: «Новая заметка», «Новая заметка 2»… Возвращает путь.
    pub fn create_note(&self, folder: &str, title: &str) -> Result<String, VaultError> {
        if let Some(why) = windows_problem(title) {
            return Err(VaultError::BadName(why));
        }
        let dir = self.resolve(folder)?;
        let taken: Vec<String> = fs::read_dir(&dir)
            .into_iter()
            .flatten()
            .flatten()
            .map(|e| compare_key(&e.file_name().to_string_lossy()))
            .collect();
        let mut n = 1;
        loop {
            let name = if n == 1 { format!("{title}.md") } else { format!("{title} {n}.md") };
            if !taken.contains(&compare_key(&name)) {
                let rel = join(folder, &name);
                self.write(&rel, "")?;
                return Ok(rel);
            }
            n += 1;
        }
    }

    /// Переименовать заметку заголовком. Имя занято — добавляем номер, как Finder. Возвращает новый путь.
    pub fn rename(&self, rel: &str, title: &str) -> Result<String, VaultError> {
        let title = title.trim();
        if let Some(why) = windows_problem(title) {
            return Err(VaultError::BadName(why));
        }
        let from = self.resolve(rel)?;
        if !from.is_file() {
            return Err(VaultError::NotFound);
        }
        let folder = rel.rsplit_once('/').map_or("", |(f, _)| f);
        let current = rel.rsplit('/').next().unwrap_or(rel);
        let dir = self.resolve(folder)?;
        let taken: Vec<String> = fs::read_dir(&dir)
            .into_iter()
            .flatten()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|n| compare_key(n) != compare_key(current))
            .map(|n| compare_key(&n))
            .collect();
        let mut n = 1;
        let name = loop {
            let name = if n == 1 { format!("{title}.md") } else { format!("{title} {n}.md") };
            if !taken.contains(&compare_key(&name)) {
                break name;
            }
            n += 1;
        };
        if name == current {
            return Ok(rel.to_string());
        }
        let to = dir.join(&name);
        fs::rename(&from, &to)?;
        Ok(join(folder, &name))
    }

    /// Задачи из всех заметок: (путь заметки, задача).
    pub fn tasks(&self) -> Vec<(String, Task)> {
        let mut out = Vec::new();
        self.collect_tasks(&self.tree(), &mut out);
        out
    }

    fn collect_tasks(&self, folder: &Folder, out: &mut Vec<(String, Task)>) {
        for note in &folder.notes {
            if let Ok(text) = self.read(&note.path) {
                out.extend(tasks_in(&text).into_iter().map(|t| (note.path.clone(), t)));
            }
        }
        for child in &folder.folders {
            self.collect_tasks(child, out);
        }
    }
}

fn join(rel: &str, name: &str) -> String {
    if rel.is_empty() { name.to_string() } else { format!("{rel}/{name}") }
}

/// По имени без учёта регистра и формы Юникода, цифры — по значению («2» раньше «10»), как в Finder.
fn by_name(a: &str, b: &str) -> Ordering {
    natural(&compare_key(a), &compare_key(b))
}

fn natural(a: &str, b: &str) -> Ordering {
    let (mut x, mut y) = (a.chars().peekable(), b.chars().peekable());
    loop {
        match (x.peek().copied(), y.peek().copied()) {
            (None, None) => return Ordering::Equal,
            (None, _) => return Ordering::Less,
            (_, None) => return Ordering::Greater,
            (Some(c), Some(d)) if c.is_ascii_digit() && d.is_ascii_digit() => {
                let n: String = std::iter::from_fn(|| x.next_if(|c| c.is_ascii_digit())).collect();
                let m: String = std::iter::from_fn(|| y.next_if(|c| c.is_ascii_digit())).collect();
                let (n, m) = (n.trim_start_matches('0'), m.trim_start_matches('0'));
                match n.len().cmp(&m.len()).then_with(|| n.cmp(m)) {
                    Ordering::Equal => {}
                    o => return o,
                }
            }
            (Some(c), Some(d)) => {
                if c != d {
                    return c.cmp(&d);
                }
                x.next();
                y.next();
            }
        }
    }
}
