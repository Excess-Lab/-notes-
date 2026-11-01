// Настройки — порт `SettingsScreen.swift`: страницы в боковой панели, заголовок и серая подпись,
// стеклянные строки 640 с кнопкой справа. Здесь — то, что уже работает на Windows; остальное
// (git и GitHub, надиктовка, пинкод) — отдельной строкой «переезжает с мака», без выдуманного вида.

import type { Api, Prefs } from "./api";
import { icon, type Glyph } from "./icons";

type Page = "general" | "sync" | "templates" | "calendar" | "dictation" | "lock";
const PAGES: [Page, string, string, Glyph][] = [
  ["general", "общие", "вид, запуск и текст заметок", "settings"],
  ["sync", "синхронизация", "где лежат заметки и куда уходят", "git"],
  ["templates", "шаблоны", "шаблоны заметок и автоматизация", "file"],
  ["calendar", "календарь", "задачи со сроком в календаре", "calendar"],
  ["dictation", "надиктовка", "текст сразу в буфере", "microphone"],
  ["lock", "вход", "пинкод и windows hello", "task"],
];

export interface SettingsHost {
  backend: Api;
  onCrumb(text: string): void;
  /** Применить тему и размер текста сразу. */
  apply(prefs: Prefs): void;
  pickVault(): Promise<void>;
  /** Создать папку в корне, только если её ещё нет (иначе вышла бы «шаблоны 2»). */
  ensureFolder(name: string): Promise<void>;
}

let page: Page = "general";
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);

const row = (title: string, subtitle: string, trailing: string) => `
  <div class="setting"><div><b>${title}</b><small>${subtitle}</small></div>${trailing}</div>`;
const pill = (act: string, text: string) => `<button class="pill" data-set="${act}">${text}</button>`;
const toggle = (key: string, on: boolean) => `<button class="switch${on ? " on" : ""}" data-toggle="${key}" role="switch" aria-checked="${on}"><i></i></button>`;
const choice = (key: string, value: string | number, options: [string | number, string][]) =>
  `<div class="segmented">${options.map(([v, t]) => `<button class="${v === value ? "on" : ""}" data-choice="${key}" data-value="${v}">${t}</button>`).join("")}</div>`;
const granted = (text: string) => `<span class="granted">${icon("taskDone")}${text}</span>`;
const later = (text = "переезжает с мака") => `<span class="later">${text}</span>`;
const note = (text: string) => `<p class="setting-note">${text}</p>`;

export async function mountSettings(root: HTMLElement, sidebar: HTMLElement, host: SettingsHost) {
  let prefs = await host.backend.prefs();
  const vault = await host.backend.vaultPath();
  const isMac = document.body.classList.contains("tauri-macos");

  function body(): string {
    switch (page) {
      case "general":
        return row("тема", "как в системе, светлая или тёмная", choice("theme", prefs.theme ?? "system", [["system", "система"], ["light", "светлая"], ["dark", "тёмная"]]))
          + row("размер текста заметок", `${prefs.textSize ?? 15} — заголовки растут вместе с текстом`, choice("textSize", prefs.textSize ?? 15, [13, 15, 17, 19].map((n) => [n, String(n)])))
          + row("проверка орфографии", "подчёркивать слова с ошибкой", toggle("spellcheck", prefs.spellcheck ?? true))
          + row("открывать при входе в " + (isMac ? "mac" : "windows"), "сразу после включения компьютера", later());
      case "sync":
        return row("папка хранилища", esc(vault ?? "не выбрана"), pill("vault", "изменить"))
          + row("история в git", "версии сохраняются по расписанию", later())
          + row("github", "приватный репозиторий notes, вход по коду", later())
          + note("папка та же, что на маке: заметки — обычные файлы .md, окончания строк не меняются");
      case "templates":
        return row("папка шаблонов", "обычные .md в папке «шаблоны»: {{дата}}, {{время}}, {{название}}", pill("templates", "открыть"))
          + row("заметка на каждый день", "в папке «дневник» по шаблону «день», открывается при запуске", toggle("daily", prefs.daily ?? false));
      case "calendar":
        return row("календарь в приложении", "задачи с 📅 из заметок: день, неделя, месяц", granted("включено"))
          + row(isMac ? "календарь apple" : "календарь windows и outlook", isMac ? "переезжает с мака" : "файл .ics со всеми задачами со сроком", isMac ? later() : pill("ics", "сохранить .ics"))
          + note(isMac ? "" : "системный календарь windows закрыт для приложений не из store — поэтому .ics");
      case "dictation":
        return row("горячая клавиша", "зажать, сказать, отпустить — текст в буфере", later())
          + row("модели распознавания", "gigaam (русский) и whisper (99 языков), качаются по требованию", later());
      case "lock":
        return row("пинкод", "при запуске и после сна", later())
          + row(isMac ? "touch id" : "windows hello", isMac ? "палец вместо пинкода" : "лицо или палец вместо пинкода", later());
    }
  }

  function render() {
    const [, title, subtitle] = PAGES.find(([p]) => p === page)!;
    root.innerHTML = `<div class="settings"><h1>${title}</h1><p class="settings-sub">${subtitle}</p><div class="settings-rows">${body()}</div></div>`;
    sidebar.innerHTML = PAGES.map(([p, t, , g]) =>
      `<button class="row${p === page ? " selected" : ""}" style="padding-left:8px" data-page="${p}">${icon(g)}<span>${t}</span></button>`).join("");
    host.onCrumb(`настройки / ${title}`);
  }

  async function save(next: Prefs) {
    prefs = next;
    await host.backend.setPrefs(prefs);
    host.apply(prefs);
    render();
  }

  root.addEventListener("click", async (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>("button");
    if (!b) return;
    if (b.dataset.toggle) {
      const key = b.dataset.toggle as "spellcheck" | "daily";
      const current = prefs[key] ?? (key === "spellcheck");
      await save({ ...prefs, [key]: !current });
    } else if (b.dataset.choice) {
      const key = b.dataset.choice as "theme" | "textSize";
      await save({ ...prefs, [key]: key === "textSize" ? Number(b.dataset.value) : b.dataset.value });
    } else if (b.dataset.set === "vault") {
      await host.pickVault();
    } else if (b.dataset.set === "templates") {
      await host.ensureFolder("шаблоны");
      if (host.backend.inTauri) await host.backend.reveal("шаблоны");
    } else if (b.dataset.set === "ics") {
      if (await host.backend.exportIcs()) { b.textContent = "сохранено"; setTimeout(() => (b.textContent = "сохранить .ics"), 1600); }
    }
  });
  sidebar.addEventListener("click", (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>("[data-page]");
    if (!b || !root.isConnected) return;
    page = b.dataset.page as Page;
    render();
  });
  render();
}
