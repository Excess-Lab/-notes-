//! Стекло под окном.
//!
//! Windows 11: Mica из `tauri.conf.json` (`windowEffects`), окно прозрачное, интерфейс кладёт свои
//! стеклянные слои поверх. macOS: системный Liquid Glass — `tauri-plugin-liquid-glass`
//! (приватный NSGlassEffectView) подключается здесь при переезде мака, под `cfg(target_os = "macos")`.

pub fn apply_glass(_window: &tauri::WebviewWindow) {}
