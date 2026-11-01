//! Поиск по тексту — как `NoteLibrary.search` на маке: все слова запроса должны встретиться в заметке
//! (без учёта регистра и ё/е), совпадение в названии весит больше, отрывок — строка с первым словом.

use serde::Serialize;

use crate::vault::{Folder, Note, Vault};

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Hit {
    pub note: Note,
    pub snippet: String,
    pub score: f64,
}

pub fn normalize(text: &str) -> String {
    text.to_lowercase().replace('ё', "е")
}

pub fn all_notes(folder: &Folder) -> Vec<Note> {
    let mut out = folder.notes.clone();
    for child in &folder.folders {
        out.extend(all_notes(child));
    }
    out
}

impl Vault {
    pub fn search(&self, query: &str, limit: usize) -> Vec<Hit> {
        let query = normalize(query);
        let words: Vec<&str> = query.split_whitespace().collect();
        if words.is_empty() {
            return Vec::new();
        }
        let mut hits = Vec::new();
        for note in all_notes(&self.tree()) {
            let Ok(text) = self.read(&note.path) else { continue };
            let title = normalize(&note.title);
            let body = normalize(&text);
            if !words.iter().all(|w| title.contains(w) || body.contains(w)) {
                continue;
            }
            let in_title = words.iter().filter(|w| title.contains(*w)).count() as f64;
            let in_body: f64 = words.iter().map(|w| body.matches(w).count() as f64).sum();
            let snippet = snippet(&text, words[0]);
            hits.push(Hit { note, snippet, score: in_title * 3.0 + in_body.min(10.0) });
        }
        hits.sort_by(|a, b| {
            b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal).then(b.note.modified.cmp(&a.note.modified))
        });
        hits.truncate(limit);
        hits
    }
}

/// Строка, где нашлось слово, без разметки списка, задачи и даты.
pub fn snippet(text: &str, word: &str) -> String {
    let lines: Vec<&str> = text.lines().map(str::trim).collect();
    let line = lines
        .iter()
        .find(|l| normalize(l).contains(word) && !l.starts_with('#'))
        .or_else(|| lines.iter().find(|l| !l.is_empty()))
        .copied()
        .unwrap_or("");
    let mut clean = line.trim_start_matches(['#', ' ', '-', '—', '*']);
    for mark in ["[ ] ", "[x] ", "[X] "] {
        if let Some(rest) = clean.strip_prefix(mark) {
            clean = rest;
        }
    }
    let clean = clean.split("📅").next().unwrap_or("").trim();
    clean.chars().take(140).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snippet_strips_markup() {
        assert_eq!(snippet("# План\n- [ ] купить хлеб 📅 2026-11-02", "хлеб"), "купить хлеб");
        assert_eq!(snippet("# Заголовок\nтекст", "нет"), "Заголовок");
    }

    #[test]
    fn yo_and_case() {
        assert_eq!(normalize("Ёлка"), "елка");
    }
}
