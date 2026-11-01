//! Шаблоны — обычные `.md` в папке «шаблоны» хранилища, как `Templates.swift` на маке.
//! Подстановки: `{{дата}}` — 2026-10-31, `{{время}}` — 15:30, `{{название}}` — имя новой заметки.
//! Заметка дня — в папке «дневник», имя — дата, текст — из шаблона «день», если он есть.
//!
//! Дату и время передаёт интерфейс: он знает часовой пояс человека, ядру часы ОС не нужны.

use std::fs;

use crate::vault::{Vault, VaultError};

pub const FOLDER: &str = "шаблоны";
pub const DAILY_FOLDER: &str = "дневник";
pub const DAILY_TEMPLATE: &str = "день";

pub fn apply(text: &str, title: &str, date: &str, time: &str) -> String {
    text.replace("{{дата}}", date).replace("{{время}}", time).replace("{{название}}", title)
}

impl Vault {
    /// Названия шаблонов без `.md`, по имени.
    pub fn templates(&self) -> Vec<String> {
        let Ok(dir) = self.resolve(FOLDER) else { return Vec::new() };
        let mut names: Vec<String> = fs::read_dir(dir)
            .into_iter()
            .flatten()
            .flatten()
            .filter_map(|e| e.file_name().to_str()?.strip_suffix(".md").map(str::to_string))
            .collect();
        names.sort();
        names
    }

    /// Новая заметка из шаблона: имя — имя шаблона (занято — с номером), подстановки заполнены.
    pub fn create_from_template(&self, template: &str, folder: &str, date: &str, time: &str) -> Result<String, VaultError> {
        let text = self.read(&format!("{FOLDER}/{template}.md"))?;
        let path = self.create_note(folder, template)?;
        let title = path.rsplit('/').next().unwrap_or(&path).trim_end_matches(".md").to_string();
        self.write(&path, &apply(&text, &title, date, time))?;
        Ok(path)
    }

    /// Заметка дня: есть — возвращаем как есть, нет — создаём. Чужой файл с таким именем не трогаем.
    pub fn daily(&self, date: &str, time: &str) -> Result<String, VaultError> {
        let path = format!("{DAILY_FOLDER}/{date}.md");
        if self.resolve(&path)?.exists() {
            return Ok(path);
        }
        let text = self.read(&format!("{FOLDER}/{DAILY_TEMPLATE}.md")).unwrap_or_else(|_| "# {{дата}}\n\n".to_string());
        self.write(&path, &apply(&text, date, date, time))?;
        Ok(path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn placeholders() {
        assert_eq!(apply("# {{название}}\n{{дата}} {{время}}", "план", "2026-11-01", "15:30"), "# план\n2026-11-01 15:30");
    }
}
