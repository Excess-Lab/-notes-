//! Файлы глазами ОС: показать в Проводнике или Finder, удалить в Корзину (вернуть можно).

use std::path::Path;
use std::process::Command;

/// Показать файл выделенным в файловом менеджере.
pub fn reveal(path: &Path) -> std::io::Result<()> {
    #[cfg(target_os = "windows")]
    {
        // `/select,` и путь — одним аргументом, иначе Проводник открывает «Документы».
        Command::new("explorer").arg(format!("/select,{}", path.display())).spawn()?;
    }
    #[cfg(target_os = "macos")]
    {
        Command::new("open").arg("-R").arg(path).spawn()?;
    }
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        Command::new("xdg-open").arg(path.parent().unwrap_or(path)).spawn()?;
    }
    Ok(())
}

/// В Корзину Windows или macOS, а не насовсем: как на маке, удалённое можно вернуть.
pub fn trash(path: &Path) -> Result<(), String> {
    trash::delete(path).map_err(|e| e.to_string())
}

/// Открыть страницу в браузере по умолчанию. Только https://github.com/ — больше приложению некуда.
pub fn open_github(url: &str) -> Result<(), String> {
    if !url.starts_with("https://github.com/") {
        return Err("only github.com".into());
    }
    #[cfg(target_os = "windows")]
    let status = Command::new("rundll32").args(["url.dll,FileProtocolHandler", url]).spawn();
    #[cfg(target_os = "macos")]
    let status = Command::new("open").arg(url).spawn();
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    let status = Command::new("xdg-open").arg(url).spawn();
    status.map(|_| ()).map_err(|e| e.to_string())
}
