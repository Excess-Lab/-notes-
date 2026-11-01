//! Настройки приложения — вне хранилища: `%APPDATA%\ai.edinstvo.notes\` на Windows,
//! `~/Library/Application Support/ai.edinstvo.notes/` на маке. В хранилище своих файлов не кладём.

use std::fs;
use tauri::{AppHandle, Manager};

fn file(app: &AppHandle) -> Option<std::path::PathBuf> {
    Some(app.path().app_config_dir().ok()?.join("vault-path"))
}

pub fn save_vault_path(app: &AppHandle, path: &str) {
    if let Some(file) = file(app) {
        if let Some(dir) = file.parent() {
            let _ = fs::create_dir_all(dir);
        }
        let _ = fs::write(file, path);
    }
}

pub fn load_vault_path(app: &AppHandle) -> Option<String> {
    let text = fs::read_to_string(file(app)?).ok()?;
    let path = text.trim().to_string();
    (!path.is_empty()).then_some(path)
}
