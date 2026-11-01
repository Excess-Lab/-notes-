// Самопроверка в настоящем окне Tauri (`NOTES_SELFTEST=1`), как `-notesSelfTest` на маке: сценарий идёт
// через настоящее Rust-ядро на настоящей папке — то, что Playwright на демо-хранилище не проверит.
// Хранилище — тестовое, не настоящее.

import { invoke } from "@tauri-apps/api/core";
import type { Api } from "./api";

export async function runSelftest(backend: Api, ui: { openNote(path: string): Promise<void>; app: HTMLElement }) {
  const log = (line: string, done = false) => invoke("selftest_log", { line, done });
  const results: string[] = [];
  const check = async (name: string, ok: boolean) => {
    results.push(`${ok ? "ok  " : "FAIL"} ${name}`);
    await log(`${ok ? "ok  " : "FAIL"} ${name}`);
    await pause(step);
  };
  const pause = (ms: number) => new Promise((r) => setTimeout(r, ms));
  // Для записи видео шаги видны глазом: NOTES_SELFTEST_SLOW=1 — пауза между проверками.
  const step = (await invoke<boolean>("selftest_slow")) ? 900 : 0;
  try {
    const tree = await backend.tree();
    await check("vault tree from Rust", tree.folders.some((f) => f.name === "проекты"));
    await ui.openNote("проекты/план.md");
    await pause(800);
    await check("note opened in editor", (ui.app.querySelector(".note-text")?.textContent ?? "").includes("проверить на Windows"));
    const note = await backend.create("проекты", "Новая заметка");
    await backend.write(note, "# Из самопроверки\n\nстрока\n");
    await check("write and read back", (await backend.read(note)).startsWith("# Из самопроверки"));
    const renamed = await backend.rename(note, "итоги");
    await check("rename", renamed === "проекты/итоги.md");
    const hits = await backend.search("самопроверки");
    await check("search finds it", hits.some((h) => h.note.path === renamed));
    await ui.openNote(renamed);
    const tasks = await backend.tasks();
    const t = tasks.find((x) => x.title === "купить хлеб");
    await check("tasks parsed", !!t && tasks.length >= 2);
    if (t) await backend.setDue(t, "2026-11-05", "10:00", 30);
    await check("set due writes the line", (await backend.read("Входящие.md")).includes("купить хлеб 📅 2026-11-05 10:00–10:30"));
    await backend.gitEnable();
    let s = await backend.gitStatus();
    await check("git enabled with first commit", s.repo && s.commits === 1);
    await backend.write(renamed, "# Из самопроверки\n\nправка\n");
    const message = await backend.gitCommit();
    s = await backend.gitStatus();
    await check(`commit «${message}»`, s.commits === 2 && message === "правка: итоги.md");
    const dup = await backend.duplicate(renamed);
    const moved = await backend.moveInto(dup, "");
    await check("duplicate and move", moved === "итоги копия.md");
    await backend.trash(moved!);
    await check("trash", !(await backend.tree()).notes.some((n) => n.path === moved));
    const daily = await backend.daily("2026-11-01", "09:00");
    await check("daily note", daily === "дневник/2026-11-01.md");
    await ui.openNote("Входящие.md");
    await pause(300);
  } catch (e) {
    await check(`exception: ${e}`, false);
  }
  const failed = results.filter((r) => r.startsWith("FAIL")).length;
  await log(`${results.length - failed}/${results.length}`, true);
}
