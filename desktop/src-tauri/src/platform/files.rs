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
