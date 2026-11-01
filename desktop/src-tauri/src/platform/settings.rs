//! Настройки приложения — вне хранилища: `%APPDATA%\ai.edinstvo.notes\` на Windows,
//! `~/Library/Application Support/ai.edinstvo.notes/` на маке. В хранилище своих файлов не кладём.

use std::fs;
use tauri::{AppHandle, Manager};

fn file(app: &AppHandle, name: &str) -> Option<std::path::PathBuf> {
    Some(app.path().app_config_dir().ok()?.join(name))
}

fn save(app: &AppHandle, name: &str, text: &str) {
    if let Some(file) = file(app, name) {
        if let Some(dir) = file.parent() {
            let _ = fs::create_dir_all(dir);
        }
        let _ = fs::write(file, text);
    }
}

fn load(app: &AppHandle, name: &str) -> Option<String> {
    fs::read_to_string(file(app, name)?).ok()
}

pub fn save_vault_path(app: &AppHandle, path: &str) {
    save(app, "vault-path", path);
}

pub fn load_vault_path(app: &AppHandle) -> Option<String> {
    let path = load(app, "vault-path")?.trim().to_string();
    (!path.is_empty()).then_some(path)
}

/// Закреплённые заметки — пути от корня хранилища, по строке. Настройка приложения, как
/// `pinnedNotes` в UserDefaults на маке: в хранилище не пишем.
pub fn pins(app: &AppHandle) -> Vec<String> {
    load(app, "pins").map(|t| t.lines().filter(|l| !l.is_empty()).map(str::to_string).collect()).unwrap_or_default()
}

pub fn save_pins(app: &AppHandle, pins: &[String]) {
    save(app, "pins", &pins.join("\n"));
}

/// Настройки интерфейса (тема, размер текста, заметка дня…) — JSON целиком; разбирает интерфейс.
pub fn prefs(app: &AppHandle) -> String {
    load(app, "prefs.json").unwrap_or_else(|| "{}".to_string())
}

pub fn save_prefs(app: &AppHandle, json: &str) {
    save(app, "prefs.json", json);
}
