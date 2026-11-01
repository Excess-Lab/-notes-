//! Оболочка Tauri: команды для интерфейса поверх `notes-core`. Здесь нет логики заметок —
//! она в ядре, — и нет кода под ОС: он в `platform`.

mod platform;

use notes_core::{Folder, Vault};
use serde::Serialize;
use std::sync::Mutex;
use tauri::{Manager, State};

/// Открытое хранилище. Путь к нему — в настройках приложения (вне хранилища).
#[derive(Default)]
struct AppState {
    vault: Mutex<Option<Vault>>,
}

#[derive(Serialize)]
struct TaskRow {
    note: String,
    #[serde(flatten)]
    task: notes_core::Task,
}

fn with_vault<T>(state: &State<AppState>, f: impl FnOnce(&Vault) -> Result<T, String>) -> Result<T, String> {
    let guard = state.vault.lock().map_err(|e| e.to_string())?;
    let vault = guard.as_ref().ok_or("no vault open")?;
    f(vault)
}

#[tauri::command]
fn open_vault(path: String, state: State<AppState>, app: tauri::AppHandle) -> Result<Folder, String> {
    let vault = Vault::open(&path).map_err(|e| e.to_string())?;
    let tree = vault.tree();
    *state.vault.lock().map_err(|e| e.to_string())? = Some(vault);
    platform::settings::save_vault_path(&app, &path);
    Ok(tree)
}

/// Хранилище с прошлого запуска, если папка ещё на месте.
#[tauri::command]
fn last_vault(state: State<AppState>, app: tauri::AppHandle) -> Option<Folder> {
    let path = platform::settings::load_vault_path(&app)?;
    let vault = Vault::open(path).ok()?;
    let tree = vault.tree();
    *state.vault.lock().ok()? = Some(vault);
    Some(tree)
}

#[tauri::command]
fn tree(state: State<AppState>) -> Result<Folder, String> {
    with_vault(&state, |v| Ok(v.tree()))
}

#[tauri::command]
fn read_note(path: String, state: State<AppState>) -> Result<String, String> {
    with_vault(&state, |v| v.read(&path).map_err(|e| e.to_string()))
}

#[tauri::command]
fn write_note(path: String, text: String, state: State<AppState>) -> Result<(), String> {
    with_vault(&state, |v| v.write(&path, &text).map_err(|e| e.to_string()))
}

#[tauri::command]
fn create_note(folder: String, title: String, state: State<AppState>) -> Result<String, String> {
    with_vault(&state, |v| v.create_note(&folder, &title).map_err(|e| e.to_string()))
}

#[tauri::command]
fn rename_note(path: String, title: String, state: State<AppState>) -> Result<String, String> {
    with_vault(&state, |v| v.rename(&path, &title).map_err(|e| e.to_string()))
}

#[tauri::command]
fn search(query: String, state: State<AppState>) -> Result<Vec<notes_core::Hit>, String> {
    with_vault(&state, |v| Ok(v.search(&query, 20)))
}

#[tauri::command]
fn tasks(state: State<AppState>) -> Result<Vec<TaskRow>, String> {
    with_vault(&state, |v| Ok(v.tasks().into_iter().map(|(note, task)| TaskRow { note, task }).collect()))
}

#[tauri::command]
fn create_folder(parent: String, name: String, state: State<AppState>) -> Result<String, String> {
    with_vault(&state, |v| v.create_folder(&parent, &name).map_err(|e| e.to_string()))
}

#[tauri::command]
fn duplicate(path: String, state: State<AppState>) -> Result<String, String> {
    with_vault(&state, |v| v.duplicate(&path).map_err(|e| e.to_string()))
}

#[tauri::command]
fn move_into(path: String, folder: String, state: State<AppState>) -> Result<Option<String>, String> {
    with_vault(&state, |v| v.move_into(&path, &folder).map_err(|e| e.to_string()))
}

#[tauri::command]
fn copy_in(outside: String, folder: String, state: State<AppState>) -> Result<String, String> {
    with_vault(&state, |v| v.copy_in(std::path::Path::new(&outside), &folder).map_err(|e| e.to_string()))
}

#[tauri::command]
fn trash(path: String, state: State<AppState>) -> Result<(), String> {
    with_vault(&state, |v| platform::files::trash(&v.resolve(&path).map_err(|e| e.to_string())?))
}

#[tauri::command]
fn reveal(path: String, state: State<AppState>) -> Result<(), String> {
    with_vault(&state, |v| platform::files::reveal(&v.resolve(&path).map_err(|e| e.to_string())?).map_err(|e| e.to_string()))
}

#[tauri::command]
fn pins(app: tauri::AppHandle) -> Vec<String> {
    platform::settings::pins(&app)
}

#[tauri::command]
fn set_pins(pins: Vec<String>, app: tauri::AppHandle) {
    platform::settings::save_pins(&app, &pins);
}

#[tauri::command]
fn templates(state: State<AppState>) -> Result<Vec<String>, String> {
    with_vault(&state, |v| Ok(v.templates()))
}

#[tauri::command]
fn create_from_template(template: String, folder: String, date: String, time: String, state: State<AppState>) -> Result<String, String> {
    with_vault(&state, |v| v.create_from_template(&template, &folder, &date, &time).map_err(|e| e.to_string()))
}

#[tauri::command]
fn daily(date: String, time: String, state: State<AppState>) -> Result<String, String> {
    with_vault(&state, |v| v.daily(&date, &time).map_err(|e| e.to_string()))
}

/// Какая ОС — интерфейс выбирает стекло окна (Mica на Windows, Liquid Glass на маке).
#[tauri::command]
fn os() -> &'static str {
    std::env::consts::OS
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState::default())
        .setup(|app| {
            if let Some(window) = app.get_webview_window("main") {
                platform::window::apply_glass(&window);
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            open_vault, last_vault, tree, read_note, write_note, create_note, rename_note, search, tasks, os,
            create_folder, duplicate, move_into, copy_in, trash, reveal, pins, set_pins,
            templates, create_from_template, daily
        ])
        .run(tauri::generate_context!())
        .expect("error while running <notes>");
}
