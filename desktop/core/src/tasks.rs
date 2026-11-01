//! Задачи — строки Markdown в заметках, как на маке (`NotesCore/Sources/NotesCore/NoteTasks.swift`):
//!
//! ```text
//! - [ ] Созвониться с командой 📅 2026-10-16 15:00
//! - [ ] Позвонить !! 📅 2026-10-31 15:00–16:30
//! - [x] Выбрать модель
//! ```

use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Task {
    /// Номер строки в файле, с нуля.
    pub line: usize,
    pub title: String,
    pub done: bool,
    /// `yyyy-MM-dd`, если есть дата.
    pub date: Option<String>,
    /// `HH:mm`, если есть время.
    pub time: Option<String>,
    /// Длительность в минутах — конец после тире.
    pub minutes: Option<u32>,
    /// «!!» в строке.
    pub urgent: bool,
}

const MARKER: &str = "📅";

pub fn parse_task(line: &str, index: usize) -> Option<Task> {
    let trimmed = line.trim_start_matches([' ', '\t']);
    let rest = trimmed.strip_prefix("- [").or_else(|| trimmed.strip_prefix("* ["))?;
    let mut chars = rest.chars();
    let mark = chars.next()?;
    if !matches!(mark, ' ' | 'x' | 'X') || chars.next()? != ']' {
        return None;
    }
    let mut text = chars.as_str().trim().to_string();

    let (mut date, mut time, mut minutes) = (None, None, None);
    if let Some(pos) = text.find(MARKER) {
        let mut tail = text[pos + MARKER.len()..].trim().to_string();
        if let Some(dash) = tail.find('–') {
            let end = hm(&tail[dash + '–'.len_utf8()..]);
            tail = tail[..dash].trim().to_string();
            let start = tail.split(' ').last().and_then(hm);
            if let (Some(s), Some(e)) = (start, end) {
                if e > s {
                    minutes = Some(e - s);
                }
            }
        }
        let mut parts = tail.split_whitespace();
        date = parts.next().filter(|d| is_date(d)).map(str::to_string);
        time = parts.next().filter(|t| hm(t).is_some()).map(str::to_string);
        text = text[..pos].trim().to_string();
    }

    let mut urgent = false;
    if text.ends_with("!!") || text.contains(" !! ") {
        urgent = true;
        text = text.replace(" !! ", " ").replace("!!", "").trim().to_string();
    }
    if text.is_empty() {
        return None;
    }
    Some(Task { line: index, title: text, done: mark != ' ', date, time, minutes, urgent })
}

/// Все задачи заметки.
pub fn tasks_in(text: &str) -> Vec<Task> {
    text.lines().enumerate().filter_map(|(i, l)| parse_task(l, i)).collect()
}

fn hm(s: &str) -> Option<u32> {
    let (h, m) = s.trim().split_once(':')?;
    let (h, m): (u32, u32) = (h.parse().ok()?, m.parse().ok()?);
    (h < 24 && m < 60).then_some(h * 60 + m)
}

fn is_date(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() == 10
        && b[4] == b'-'
        && b[7] == b'-'
        && b.iter().enumerate().all(|(i, c)| i == 4 || i == 7 || c.is_ascii_digit())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_and_done() {
        let t = parse_task("- [ ] Выбрать модель", 3).unwrap();
        assert_eq!((t.title.as_str(), t.done, t.line), ("Выбрать модель", false, 3));
        assert!(parse_task("  * [x] готово", 0).unwrap().done);
    }

    #[test]
    fn date_time_duration_urgent() {
        let t = parse_task("- [ ] Позвонить !! 📅 2026-10-31 15:00–16:30", 0).unwrap();
        assert_eq!(t.title, "Позвонить");
        assert!(t.urgent);
        assert_eq!(t.date.as_deref(), Some("2026-10-31"));
        assert_eq!(t.time.as_deref(), Some("15:00"));
        assert_eq!(t.minutes, Some(90));
    }

    #[test]
    fn not_tasks() {
        assert_eq!(parse_task("- просто строка", 0), None);
        assert_eq!(parse_task("- [?] нет", 0), None);
        assert_eq!(parse_task("- [ ] 📅 2026-10-31", 0), None);
    }

    #[test]
    fn many() {
        let text = "# План\n- [ ] раз\nтекст\n- [x] два 📅 2026-11-01\n";
        let all = tasks_in(text);
        assert_eq!(all.len(), 2);
        assert_eq!(all[1].line, 3);
        assert_eq!(all[1].time, None);
    }
}
