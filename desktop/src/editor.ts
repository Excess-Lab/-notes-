// Редактор Markdown — как `MarkdownEditor.swift`: текст обычный, заголовки `#`, `##`, `###` крупнее
// и полужирные (знаки `#` бледные), задачи видны отметкой. Файл остаётся чистым Markdown: стиль —
// только на экране. Строка — отдельный блок, при наборе перекрашиваем лишь классы строк;
// DOM пересобираем, только если браузер сам поменял его устройство (вставка, Enter).

const lineClass = (line: string) => {
  const h = /^(#{1,3}) /.exec(line);
  if (h) return `l h${h[1].length}`;
  if (/^\s*[-*] \[[xX]\] /.test(line)) return "l todo done";
  if (/^\s*[-*] \[ \] /.test(line)) return "l todo";
  return "l";
};

const escape = (s: string) => s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]!);

function lineHTML(line: string): string {
  const h = /^(#{1,3} )(.*)$/.exec(line);
  const body = h ? `<span class="mark">${h[1]}</span>${escape(h[2])}` : escape(line);
  return `<div class="${lineClass(line)}">${body || "<br>"}</div>`;
}

export function editorHTML(text: string): string {
  return `<div class="note-text" contenteditable="plaintext-only" spellcheck="true">${text.split("\n").map(lineHTML).join("")}</div>`;
}

function textOf(root: HTMLElement): string {
  // Блок на строку: так и читаем, чтобы пустые строки не терялись и не множились.
  const lines: string[] = [];
  root.childNodes.forEach((node) => {
    const t = node.nodeName === "BR" ? "" : (node.textContent ?? "");
    lines.push(...t.split("\n"));
  });
  return lines.join("\n");
}

function caret(root: HTMLElement): { line: number; column: number } | null {
  const sel = getSelection();
  if (!sel || !sel.rangeCount || !root.contains(sel.anchorNode)) return null;
  const range = sel.getRangeAt(0);
  const pre = document.createRange();
  pre.selectNodeContents(root);
  pre.setEnd(range.startContainer, range.startOffset);
  const before = textOf(fragmentRoot(pre));
  const lines = before.split("\n");
  return { line: lines.length - 1, column: lines.at(-1)!.length };
}

function fragmentRoot(range: Range): HTMLElement {
  const div = document.createElement("div");
  div.appendChild(range.cloneContents());
  return div;
}

function place(root: HTMLElement, at: { line: number; column: number }) {
  const line = root.children[Math.min(at.line, root.children.length - 1)];
  if (!line) return;
  const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
  let left = at.column;
  let node: Node | null;
  const range = document.createRange();
  while ((node = walker.nextNode())) {
    const len = node.textContent!.length;
    if (left <= len) { range.setStart(node, left); break; }
    left -= len;
  }
  if (!node) range.setStart(line, 0);
  range.collapse(true);
  const sel = getSelection()!;
  sel.removeAllRanges();
  sel.addRange(range);
}

/** Подписывает редактор: отдаёт текст на каждую правку. */
export function bindMarkdown(root: HTMLElement, onText: (text: string) => void) {
  root.addEventListener("input", () => {
    const text = textOf(root);
    const lines = text.split("\n");
    const tidy = root.childNodes.length === lines.length &&
      [...root.childNodes].every((n) => n.nodeName === "DIV" && !(n as HTMLElement).querySelector("div"));
    if (tidy) {
      // Классы — по тексту строки; знаки «#» перекрашиваем пересборкой только этой строки.
      [...root.children].forEach((el, i) => {
        const want = lineClass(lines[i]);
        const marked = el.firstElementChild?.classList.contains("mark") ?? false;
        const heading = want.includes(" h");
        if (el.className !== want || marked !== heading) {
          const at = caret(root);
          el.outerHTML = lineHTML(lines[i]);
          if (at) place(root, at);
        }
      });
    } else {
      const at = caret(root);
      root.innerHTML = lines.map(lineHTML).join("");
      if (at) place(root, at);
    }
    onText(text);
  });
  // Tab — отступ в тексте, а не уход фокуса.
  root.addEventListener("keydown", (e) => {
    if (e.key === "Tab") { e.preventDefault(); document.execCommand("insertText", false, "\t"); }
  });
}
