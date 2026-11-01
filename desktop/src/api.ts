// Связь с Rust-ядром. В окне Tauri — команды из `src-tauri/src/lib.rs`; в обычном браузере
// (`npm run dev`, проверка вида и видео) — демо-хранилище в памяти, чтобы интерфейс жил без Rust.

export interface Note { path: string; title: string; modified: number }
export interface Entry { path: string; name: string }
export interface Folder {
  path: string; name: string;
  folders: Folder[]; notes: Note[]; files: Entry[];
  note_count: number; unreadable: Entry[];
}
export interface TaskRow {
  note: string; line: number; title: string; done: boolean;
  date: string | null; time: string | null; minutes: number | null; urgent: boolean;
}

export interface Hit { note: Note; snippet: string; score: number }

export interface Api {
  inTauri: boolean;
  lastVault(): Promise<Folder | null>;
  pickVault(): Promise<Folder | null>;
  tree(): Promise<Folder>;
  read(path: string): Promise<string>;
  write(path: string, text: string): Promise<void>;
  create(folder: string, title: string): Promise<string>;
  rename(path: string, title: string): Promise<string>;
  search(query: string): Promise<Hit[]>;
  tasks(): Promise<TaskRow[]>;
  os(): Promise<string>;
}

const inTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

async function tauriApi(): Promise<Api> {
  const { invoke } = await import("@tauri-apps/api/core");
  const { open } = await import("@tauri-apps/plugin-dialog");
  return {
    inTauri: true,
    lastVault: () => invoke<Folder | null>("last_vault"),
    async pickVault() {
      const path = await open({ directory: true, multiple: false, title: "Папка с заметками" });
      return typeof path === "string" ? invoke<Folder>("open_vault", { path }) : null;
    },
    tree: () => invoke<Folder>("tree"),
    read: (path) => invoke<string>("read_note", { path }),
    write: (path, text) => invoke<void>("write_note", { path, text }),
    create: (folder, title) => invoke<string>("create_note", { folder, title }),
    rename: (path, title) => invoke<string>("rename_note", { path, title }),
    search: (query) => invoke<Hit[]>("search", { query }),
    tasks: () => invoke<TaskRow[]>("tasks"),
    os: () => invoke<string>("os"),
  };
}

// ——— демо-хранилище ———

const demo: Record<string, string> = {
  "Входящие.md": "- [ ] купить хлеб 📅 2026-11-02\n- [ ] позвонить Ане !! 📅 2026-11-03 15:00\n",
  "проекты/план приложения.md":
    "# Что делаем\n\nЗаметки — обычные файлы Markdown в папке. История — в git, на GitHub по желанию.\n\n## Windows\n\n- [x] ядро на Rust\n- [ ] стекло как на маке 📅 2026-11-05\n- [ ] надиктовка по хоткею\n\nСинхронизация идёт сама: раз в час коммит, раз в день — на GitHub.\n",
  "проекты/лендинг.md": "# Лендинг\n\nОдин экран, кнопка «скачать», три фишки.\n",
  "проекты/дизайн/шапка.md": "# Шапка\n\nКапсулы 48, скругление 18, стекло 20 %.\n",
  "дневник/2026-11-01.md": "# 1 ноября\n\nВыпустили 1.0.0.\n",
  "идеи.md": "- рисунки внутри заметки\n- поиск по смыслу точнее\n",
};
const demoTime = Math.floor(Date.now() / 1000) - 600;

function demoTree(): Folder {
  const root: Folder = { path: "", name: "заметки", folders: [], notes: [], files: [], note_count: 0, unreadable: [] };
  const ensure = (path: string): Folder => {
    if (!path) return root;
    const parts = path.split("/");
    let node = root;
    parts.forEach((part, i) => {
      const p = parts.slice(0, i + 1).join("/");
      let child = node.folders.find((f) => f.path === p);
      if (!child) {
        child = { path: p, name: part, folders: [], notes: [], files: [], note_count: 0, unreadable: [] };
        node.folders.push(child);
      }
      node = child;
    });
    return node;
  };
  for (const path of Object.keys(demo)) {
    const slash = path.lastIndexOf("/");
    const folder = ensure(slash < 0 ? "" : path.slice(0, slash));
    folder.notes.push({ path, title: path.slice(slash + 1, -3), modified: demoTime });
  }
  const sort = (f: Folder): number => {
    const cmp = (a: string, b: string) => a.localeCompare(b, "ru", { numeric: true, sensitivity: "base" });
    f.folders.sort((a, b) => cmp(a.name, b.name));
    f.notes.sort((a, b) => cmp(a.title, b.title));
    f.note_count = f.notes.length + f.folders.reduce((n, c) => n + sort(c), 0);
    return f.note_count;
  };
  sort(root);
  return root;
}

const demoApi: Api = {
  inTauri: false,
  lastVault: async () => demoTree(),
  pickVault: async () => demoTree(),
  tree: async () => demoTree(),
  read: async (path) => demo[path] ?? "",
  write: async (path, text) => { demo[path] = text; },
  async create(folder, title) {
    let n = 1;
    const name = () => `${folder ? folder + "/" : ""}${title}${n === 1 ? "" : " " + n}.md`;
    while (name() in demo) n++;
    demo[name()] = "";
    return name();
  },
  async rename(path, title) {
    const folder = path.includes("/") ? path.slice(0, path.lastIndexOf("/") + 1) : "";
    const to = `${folder}${title.trim()}.md`;
    if (to === path || !title.trim()) return path;
    if (to in demo) throw new Error("name taken");
    demo[to] = demo[path]; delete demo[path];
    return to;
  },
  // Как `core/src/search.rs`: все слова, ё = е, название весит больше.
  async search(query) {
    const norm = (s: string) => s.toLowerCase().replaceAll("ё", "е");
    const words = norm(query).split(/\s+/).filter(Boolean);
    if (!words.length) return [];
    const hits: Hit[] = [];
    for (const [path, text] of Object.entries(demo)) {
      const title = path.slice(path.lastIndexOf("/") + 1, -3);
      const t = norm(title), b = norm(text);
      if (!words.every((w) => t.includes(w) || b.includes(w))) continue;
      const lines = text.split("\n").map((l) => l.trim());
      const line = lines.find((l) => norm(l).includes(words[0]) && !l.startsWith("#")) ?? lines.find(Boolean) ?? "";
      const snippet = line.replace(/^[#\s\-—*]+/, "").replace(/^\[[ xX]\] /, "").split("📅")[0].trim();
      const score = words.filter((w) => t.includes(w)).length * 3 + Math.min(10, words.reduce((n, w) => n + b.split(w).length - 1, 0));
      hits.push({ note: { path, title, modified: demoTime }, snippet, score });
    }
    return hits.sort((a, b) => b.score - a.score).slice(0, 20);
  },
  // Упрощённый разбор, только для демо; настоящий — `core/src/tasks.rs`.
  tasks: async () =>
    Object.entries(demo).flatMap(([note, text]) =>
      text.split("\n").flatMap((line, i) => {
        const m = /^\s*[-*] \[([ xX])\] (.+?)(?: 📅 (\d{4}-\d{2}-\d{2})(?: (\d{2}:\d{2}))?.*)?$/u.exec(line);
        if (!m) return [];
        const urgent = m[2].includes("!!");
        return [{ note, line: i, title: m[2].replace("!!", "").trim(), done: m[1] !== " ",
          date: m[3] ?? null, time: m[4] ?? null, minutes: null, urgent }];
      })),
  os: async () => "browser",
};

export const api: Promise<Api> = inTauri ? tauriApi() : Promise.resolve(demoApi);
