// Главный экран — порт `NotesWindow.swift`: шапка из планок, три капсулы, стеклянный лист,
// путь капсулой, дерево слева, раздел справа. Окно 1200×760, сжимается до 820.

import { api, type Api, type Folder, type Note, type TaskRow } from "./api";
import { icon, type Glyph } from "./icons";
import { drawSlats } from "./slats";

type Section = "notes" | "tasks" | "calendar" | "video" | "settings";
type Selection = { kind: "folder"; path: string } | { kind: "note"; path: string };

const SECTIONS: { id: Section; title: string; glyph: Glyph }[] = [
  { id: "notes", title: "заметки", glyph: "notes" },
  { id: "tasks", title: "задачи", glyph: "taskDone" },
  { id: "calendar", title: "календарь", glyph: "calendar" },
  { id: "video", title: "видео", glyph: "video" },
  { id: "settings", title: "настройки", glyph: "settings" },
];

const state = {
  section: "notes" as Section,
  tree: null as Folder | null,
  selection: { kind: "folder", path: "" } as Selection,
  expanded: new Set<string>(),
  text: "",
  saved: Date.now(),
  tasks: [] as TaskRow[],
};

let backend: Api;
const app = document.getElementById("app")!;
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);

// ——— тема: светлая/тёмная по системе, можно принудить ?theme=dark ———
const forced = new URLSearchParams(location.search).get("theme");
if (forced === "dark" || forced === "light") document.documentElement.dataset.theme = forced;
const isDark = () =>
  document.documentElement.dataset.theme === "dark" ||
  (!document.documentElement.dataset.theme && matchMedia("(prefers-color-scheme: dark)").matches);

// ——— каркас окна: рисуется один раз, дальше меняются только части ———
app.innerHTML = `
  <canvas class="slats"></canvas>
  <header class="topbar arrive" style="transition-delay:.05s">
    <div class="group brand">
      <button class="logo" data-go="home">&lt;notes&gt;</button>
      <button class="search">${icon("search")}<span>поиск</span><kbd class="keycap">Ctrl K</kbd></button>
    </div>
    <nav class="group sections"></nav>
    <div class="group sync">${icon("git")}<span>синхронизировано</span></div>
  </header>
  <div class="sheet arrive" style="transition-delay:.15s"></div>
  <button class="crumb arrive" style="transition-delay:.2s"></button>
  <aside class="sidebar arrive" style="transition-delay:.2s"></aside>
  <main class="content arrive" style="transition-delay:.25s">
    <div class="actions"></div>
    <div class="page"></div>
  </main>`;

const $ = <T extends HTMLElement>(s: string) => app.querySelector<T>(s)!;
const slats = $<HTMLCanvasElement>(".slats");
const nav = $(".sections");
const crumb = $(".crumb");
const sidebar = $(".sidebar");
const actions = $(".actions");
let page = $(".page");

function paintSlats() {
  drawSlats(slats, app.clientWidth, 92, isDark());
}
new ResizeObserver(paintSlats).observe(app);
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", paintSlats);

// ——— шапка ———
function renderNav() {
  nav.innerHTML = SECTIONS.map((s) => `
    <button class="section${s.id === state.section ? " active" : ""}" data-section="${s.id}" title="${s.title}">
      ${icon(s.glyph)}<span>${s.title}</span>
    </button>`).join("");
}

// ——— дерево ———
function findFolder(path: string, node = state.tree): Folder | null {
  if (!node) return null;
  if (node.path === path) return node;
  for (const f of node.folders) {
    const hit = findFolder(path, f);
    if (hit) return hit;
  }
  return null;
}

function rows(folder: Folder, depth: number): string {
  const pad = 8 + depth * 18;
  let html = "";
  for (const f of folder.folders) {
    const selected = state.selection.kind === "folder" && state.selection.path === f.path;
    html += `<button class="row${selected ? " selected" : ""}" style="padding-left:${pad}px" data-folder="${esc(f.path)}">
      ${icon("folder")}<span>${esc(f.name)}</span></button>`;
    if (state.expanded.has(f.path)) html += rows(f, depth + 1);
  }
  for (const n of folder.notes) {
    const selected = state.selection.kind === "note" && state.selection.path === n.path;
    html += `<button class="row${selected ? " selected" : ""}" style="padding-left:${pad}px" data-note="${esc(n.path)}">
      ${icon("file")}<span>${esc(n.title)}</span></button>`;
  }
  return html;
}

function renderSidebar() {
  if (state.section === "notes") {
    sidebar.innerHTML = state.tree ? rows(state.tree, 0) : "";
  } else if (state.section === "tasks") {
    const open = state.tasks.filter((t) => !t.done).length;
    sidebar.innerHTML = `
      <button class="row selected" style="padding-left:8px">${icon("taskDone")}<span>все</span><small>${open}</small></button>`;
  } else {
    sidebar.innerHTML = "";
  }
}

// ——— путь ———
function crumbText(): string {
  if (state.section === "notes") {
    const path = state.selection.path.replace(/\.md$/, "");
    return path ? path.split("/").join(" / ") : "все заметки";
  }
  return SECTIONS.find((s) => s.id === state.section)!.title;
}

// ——— раздел ———
const plural = (n: number, one: string, few: string, many: string) => {
  const d = n % 10, h = n % 100;
  return d === 1 && h !== 11 ? one : d >= 2 && d <= 4 && (h < 12 || h > 14) ? few : many;
};

function when(seconds: number): string {
  const date = new Date(seconds * 1000);
  const time = date.toLocaleTimeString("ru", { hour: "2-digit", minute: "2-digit" });
  const today = new Date();
  if (date.toDateString() === today.toDateString()) return `сегодня в ${time}`;
  return `${date.toLocaleDateString("ru", { day: "numeric", month: "short" })} в ${time}`;
}

const folderSvg = `<svg viewBox="0 0 184 133" aria-hidden="true"><path fill="currentColor" d="M0 20 A20 20 0 0 1 20 0 H42.9 A20 20 0 0 1 62.9 20 V10.5 A20 20 0 0 0 82.9 30.5 H164 A20 20 0 0 1 184 50.5 V113 A20 20 0 0 1 164 133 H20 A20 20 0 0 1 0 113 Z"/></svg>`;

function overviewHTML(folder: Folder): string {
  const root = folder.path === "";
  return `<div class="overview">
    <h1>${root ? "все заметки" : esc(folder.name)}</h1>
    <div class="counts">${folder.folders.length} ${plural(folder.folders.length, "папка", "папки", "папок")} | ${folder.note_count} ${plural(folder.note_count, "заметка", "заметки", "заметок")}</div>
    <div class="cards">${folder.folders.map((f) => `
      <button class="card" data-folder="${esc(f.path)}">${folderSvg}<b>${esc(f.name)}</b>
        <small>${f.note_count} ${plural(f.note_count, "заметка", "заметки", "заметок")}</small></button>`).join("")}
    </div>
    ${folder.notes.length ? `<div class="list-title">${root ? "без папки" : "заметки"}</div>
      ${folder.notes.map((n: Note) => `<button class="note-row" data-note="${esc(n.path)}">${icon("file")}
        <span>${esc(n.title)}</span><small>${when(n.modified)}</small></button>`).join("")}` : ""}
  </div>`;
}

function words(text: string) {
  return text.split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w)).length;
}

function noteHTML(path: string): string {
  const title = path.split("/").pop()!.replace(/\.md$/, "");
  const n = words(state.text);
  return `<article class="note">
    <input class="note-title" value="${esc(title)}" placeholder="без названия" spellcheck="false" readonly>
    <div class="note-meta">изменено ${when(state.saved / 1000)} · ${n} ${plural(n, "слово", "слова", "слов")}</div>
    <textarea class="note-text" spellcheck="true">${esc(state.text)}</textarea>
  </article>`;
}

function tasksHTML(): string {
  const list = state.tasks;
  return `<div class="placeholder"><h1>задачи</h1>
    <p>${list.length ? `${list.filter((t) => !t.done).length} открытых — из строк «- [ ] … 📅 дата» в заметках.` : "Задач пока нет: напишите «- [ ] задача 📅 2026-11-03» в любой заметке."}</p>
    <div style="margin-top:28px">${list.map((t) => `
      <div class="task${t.done ? " done" : ""}"><i></i><span>${esc(t.title)}${t.urgent ? ' <b class="urgent">!!</b>' : ""}</span>
      <small>${[t.date, t.time].filter(Boolean).join(" ")}</small></div>`).join("")}</div></div>`;
}

function soonHTML(title: string): string {
  return `<div class="placeholder"><h1>${title}</h1><p>Этот раздел переезжает с мака следующим.</p></div>`;
}

function renderActions() {
  const buttons: [Glyph, string, string][] =
    state.section === "notes" ? [["microphone", "надиктовать", "dictate"], ["newNote", "новая заметка", "new-note"]]
    : state.section === "tasks" ? [["microphone", "надиктовать", "dictate"], ["plus", "новая задача", "new-task"]]
    : state.section === "video" ? [["plus", "добавить видео или аудио", "add-video"]]
    : state.section === "calendar" ? [["microphone", "надиктовать", "dictate"]] : [];
  actions.innerHTML = buttons.map(([g, help, act]) =>
    `<button class="icon-button" title="${help}" data-act="${act}">${icon(g)}</button>`).join("");
}

function contentHTML(): string {
  if (!state.tree) {
    return `<div class="placeholder"><h1>папка с заметками</h1>
      <p>Выберите папку: заметки останутся обычными файлами Markdown, а мак откроет ту же папку.</p>
      <button class="primary" data-act="pick">выбрать папку</button></div>`;
  }
  switch (state.section) {
    case "notes":
      return state.selection.kind === "note" ? noteHTML(state.selection.path)
        : overviewHTML(findFolder(state.selection.path) ?? state.tree);
    case "tasks": return tasksHTML();
    case "calendar": return soonHTML("календарь");
    case "video": return soonHTML("видео");
    case "settings": return soonHTML("настройки");
  }
}

// Смена раздела или заметки: старое уходит в размытие, новое из него проявляется — как на маке.
let lastKey = "";
function renderContent() {
  const key = `${state.section}:${state.selection.kind}:${state.selection.path}:${!!state.tree}`;
  const html = contentHTML();
  if (key === lastKey) { page.innerHTML = html; bindEditor(); return; }
  lastKey = key;
  const old = page;
  const next = document.createElement("div");
  next.className = "page entering";
  next.innerHTML = html;
  old.after(next);
  old.classList.add("leaving");
  requestAnimationFrame(() => requestAnimationFrame(() => next.classList.remove("entering")));
  setTimeout(() => old.remove(), 450);
  page = next;
  bindEditor();
}

function render() {
  renderNav();
  renderSidebar();
  crumb.textContent = crumbText();
  renderActions();
  renderContent();
}

// ——— редактор: автосохранение через полсекунды тишины ———
let saveTimer = 0;
function bindEditor() {
  const area = page.querySelector<HTMLTextAreaElement>(".note-text");
  if (!area || state.selection.kind !== "note") return;
  const path = state.selection.path;
  area.addEventListener("input", () => {
    state.text = area.value;
    clearTimeout(saveTimer);
    saveTimer = window.setTimeout(async () => {
      await backend.write(path, state.text);
      state.saved = Date.now();
      const meta = page.querySelector(".note-meta");
      const n = words(state.text);
      if (meta) meta.textContent = `изменено ${when(state.saved / 1000)} · ${n} ${plural(n, "слово", "слова", "слов")}`;
    }, 500);
  });
}

async function openNote(path: string) {
  state.text = await backend.read(path);
  state.saved = (findNote(path)?.modified ?? Date.now() / 1000) * 1000;
  state.selection = { kind: "note", path };
  state.section = "notes";
  render();
}

function findNote(path: string, node = state.tree): Note | null {
  if (!node) return null;
  return node.notes.find((n) => n.path === path) ?? node.folders.map((f) => findNote(path, f)).find(Boolean) ?? null;
}

// ——— клики ———
app.addEventListener("click", async (e) => {
  const el = (e.target as HTMLElement).closest<HTMLElement>("button");
  if (!el) return;
  if (el.dataset.section) {
    state.section = el.dataset.section as Section;
    if (state.section === "tasks" && state.tree) state.tasks = await backend.tasks();
    render();
  } else if (el.dataset.folder !== undefined) {
    const path = el.dataset.folder;
    if (el.classList.contains("row") && state.expanded.has(path) && state.selection.path === path) state.expanded.delete(path);
    else state.expanded.add(path);
    state.selection = { kind: "folder", path };
    render();
  } else if (el.dataset.note) {
    await openNote(el.dataset.note);
  } else if (el.dataset.go === "home" || el === crumb) {
    state.section = "notes";
    state.selection = { kind: "folder", path: "" };
    render();
  } else if (el.dataset.act === "pick") {
    state.tree = await backend.pickVault();
    render();
  } else if (el.dataset.act === "new-note" && state.tree) {
    const folder = state.selection.kind === "folder" ? state.selection.path : state.selection.path.split("/").slice(0, -1).join("/");
    const path = await backend.create(folder, "Новая заметка");
    state.tree = await backend.tree();
    if (folder) state.expanded.add(folder);
    await openNote(path);
  }
});

// Ctrl+K — поиск (на маке ⌘K), Ctrl+N — новая заметка.
window.addEventListener("keydown", (e) => {
  if (!(e.ctrlKey || e.metaKey)) return;
  if (e.key.toLowerCase() === "n") { e.preventDefault(); actions.querySelector<HTMLButtonElement>('[data-act="new-note"]')?.click(); }
});

// ——— старт ———
(async () => {
  backend = await api;
  const os = await backend.os();
  document.body.classList.add(backend.inTauri ? `tauri-${os}` : "browser");
  state.tree = await backend.lastVault();
  const demo = new URLSearchParams(location.search).get("open");
  render();
  paintSlats();
  requestAnimationFrame(() => app.classList.add("arrived"));
  if (demo) {
    for (const part of demo.split("/").slice(0, -1).reduce<string[]>((acc, p) => [...acc, acc.length ? `${acc.at(-1)}/${p}` : p], [])) state.expanded.add(part);
    await openNote(demo);
  }
})();
