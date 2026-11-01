//! Секреты — только в хранилище паролей ОС: Диспетчер учётных данных Windows, Связка ключей macOS.
//! Ни в файлах, ни в реестре, ни в хранилище заметок (CLAUDE.md, «Нельзя никогда»).

const SERVICE: &str = "ai.edinstvo.notes";
const GITHUB: &str = "github-token";

fn entry() -> Result<keyring::Entry, String> {
    keyring::Entry::new(SERVICE, GITHUB).map_err(|e| e.to_string())
}

pub fn save_token(token: &str) -> Result<(), String> {
    entry()?.set_password(token).map_err(|e| e.to_string())
}

pub fn token() -> Option<String> {
    entry().ok()?.get_password().ok()
}

pub fn forget_token() {
    if let Ok(e) = entry() {
        let _ = e.delete_credential();
    }
}

const PIN: &str = "pin";

/// Пинкод — его PBKDF2-хеш одной строкой (`notes_core::lock::PinHash::encoded`), сам пинкод нигде не лежит.
pub fn save_pin(encoded: &str) -> Result<(), String> {
    keyring::Entry::new(SERVICE, PIN).and_then(|e| e.set_password(encoded)).map_err(|e| e.to_string())
}

pub fn pin() -> Option<String> {
    keyring::Entry::new(SERVICE, PIN).ok()?.get_password().ok()
}

pub fn forget_pin() {
    if let Ok(e) = keyring::Entry::new(SERVICE, PIN) {
        let _ = e.delete_credential();
    }
}
