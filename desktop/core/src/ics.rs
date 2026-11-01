//! Задачи с датой — в формате iCalendar (`.ics`) для Календаря Windows, Outlook и любого другого
//! календаря. Только чтение: правятся задачи в заметках, файл собирается заново.
//! Время — «плавающее» (без часового пояса): 15:00 в заметке — 15:00 в календаре, где бы ни открыли.

use crate::tasks::Task;

fn escape(text: &str) -> String {
    text.replace('\\', r"\\").replace(';', r"\;").replace(',', r"\,").replace('\n', r"\n")
}

/// Стабильный UID: заметка + текст, как ключ связи с календарём на маке. FNV-1a, без зависимостей.
fn uid(note: &str, title: &str) -> String {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in note.bytes().chain([0]).chain(title.bytes()) {
        h ^= u64::from(b);
        h = h.wrapping_mul(0x100000001b3);
    }
    format!("{h:016x}@notes")
}

fn compact(date: &str) -> String {
    date.replace('-', "")
}

fn plus_day(date: &str) -> String {
    // Конец события «весь день» — следующий день. Считаем по-простому: календарь григорианский.
    let (y, m, d): (i32, u32, u32) = (date[0..4].parse().unwrap_or(1970), date[5..7].parse().unwrap_or(1), date[8..10].parse().unwrap_or(1));
    let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    let days = [31, if leap { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][(m as usize).saturating_sub(1).min(11)];
    let (y, m, d) = if d < days { (y, m, d + 1) } else if m < 12 { (y, m + 1, 1) } else { (y + 1, 1, 1) };
    format!("{y:04}{m:02}{d:02}")
}

/// `stamp` — момент сборки в UTC, `20261101T120000Z`: его требует формат (DTSTAMP).
pub fn calendar(tasks: &[(String, Task)], stamp: &str) -> String {
    let mut out = String::from("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//notes//tasks//RU\r\nCALSCALE:GREGORIAN\r\nX-WR-CALNAME:<notes>\r\n");
    for (note, t) in tasks {
        let Some(date) = &t.date else { continue };
        out.push_str("BEGIN:VEVENT\r\n");
        out.push_str(&format!("UID:{}\r\nDTSTAMP:{stamp}\r\n", uid(note, &t.title)));
        match &t.time {
            Some(time) => {
                let start: u32 = time[0..2].parse::<u32>().unwrap_or(0) * 60 + time[3..5].parse::<u32>().unwrap_or(0);
                let end = (start + t.minutes.unwrap_or(60)).min(23 * 60 + 59);
                out.push_str(&format!("DTSTART:{}T{:02}{:02}00\r\n", compact(date), start / 60, start % 60));
                out.push_str(&format!("DTEND:{}T{:02}{:02}00\r\n", compact(date), end / 60, end % 60));
            }
            None => {
                out.push_str(&format!("DTSTART;VALUE=DATE:{}\r\nDTEND;VALUE=DATE:{}\r\n", compact(date), plus_day(date)));
            }
        }
        let title = if t.done { format!("✓ {}", t.title) } else { t.title.clone() };
        out.push_str(&format!("SUMMARY:{}\r\nDESCRIPTION:{}\r\n", escape(&title), escape(note)));
        if t.urgent {
            out.push_str("PRIORITY:1\r\n");
        }
        out.push_str("END:VEVENT\r\n");
    }
    out.push_str("END:VCALENDAR\r\n");
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tasks::parse_task;

    #[test]
    fn events() {
        let rows = vec![
            ("Входящие.md".to_string(), parse_task("- [ ] звонок, важный !! 📅 2026-11-01 15:00–16:30", 0).unwrap()),
            ("Входящие.md".to_string(), parse_task("- [x] хлеб 📅 2026-12-31", 1).unwrap()),
            ("Входящие.md".to_string(), parse_task("- [ ] без даты", 2).unwrap()),
        ];
        let ics = calendar(&rows, "20261101T120000Z");
        assert_eq!(ics.matches("BEGIN:VEVENT").count(), 2);
        assert!(ics.contains("DTSTART:20261101T150000\r\nDTEND:20261101T163000"));
        assert!(ics.contains("SUMMARY:звонок\\, важный\r\n"));
        assert!(ics.contains("PRIORITY:1"));
        assert!(ics.contains("DTSTART;VALUE=DATE:20261231\r\nDTEND;VALUE=DATE:20270101"));
        assert!(ics.contains("SUMMARY:✓ хлеб"));
        assert_eq!(uid("a", "b"), uid("a", "b"));
        assert_ne!(uid("a", "b"), uid("a", "c"));
    }
}
