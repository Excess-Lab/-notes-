//! Имена файлов, которые приходят с мака и могут не открыться на Windows.
//!
//! Мак пишет имена в NFD, Windows — в NFC: «й» и «ё» становятся разными строками. Сравниваем
//! только после нормализации и чужие файлы ради неё не переименовываем.

use unicode_normalization::UnicodeNormalization;

/// Ключ для сравнения путей: NFC и нижний регистр (обе ОС регистр не различают, git — различает).
pub fn compare_key(name: &str) -> String {
    name.nfc().collect::<String>().to_lowercase()
}

/// Почему имя нельзя создать на Windows. `None` — можно.
pub fn windows_problem(name: &str) -> Option<&'static str> {
    if name.is_empty() {
        return Some("empty name");
    }
    if name.chars().any(|c| matches!(c, '<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*') || (c as u32) < 32) {
        return Some("forbidden character");
    }
    if name.ends_with('.') || name.ends_with(' ') {
        return Some("ends with a dot or space");
    }
    let stem = name.split('.').next().unwrap_or("").to_ascii_uppercase();
    const RESERVED: [&str; 22] = [
        "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    ];
    if RESERVED.contains(&stem.as_str()) {
        return Some("reserved name");
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nfd_and_nfc_compare_equal() {
        let nfd = "и\u{0306}"; // «й» как и + кратка — так пишет мак
        assert_ne!(nfd, "й");
        assert_eq!(compare_key(nfd), compare_key("Й"));
    }

    #[test]
    fn windows_names() {
        assert_eq!(windows_problem("план.md"), None);
        assert!(windows_problem("a:b.md").is_some());
        assert!(windows_problem("CON.md").is_some());
        assert!(windows_problem("con").is_some());
        assert!(windows_problem("заметка.").is_some());
        assert_eq!(windows_problem("console.md"), None);
    }
}
