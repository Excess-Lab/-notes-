// Меню правого клика — стеклянная капсула в стиле листа, а не системное меню Windows:
// на маке это системное меню, здесь вид держим общим для обеих ОС. Пункты — как `NoteMenu` на маке.

export type MenuItem = { label: string; run: () => void; danger?: boolean } | "divider";

let open: HTMLElement | null = null;

export function closeMenu() {
  if (!open) return;
  const gone = open;
  open = null;
  gone.classList.remove("shown");
  setTimeout(() => gone.remove(), 150);
}

export function showMenu(x: number, y: number, items: MenuItem[]) {
  closeMenu();
  const menu = document.createElement("div");
  menu.className = "menu";
  menu.setAttribute("role", "menu");
  items.forEach((item) => {
    if (item === "divider") {
      menu.append(Object.assign(document.createElement("hr"), {}));
      return;
    }
    const button = document.createElement("button");
    button.className = item.danger ? "danger" : "";
    button.textContent = item.label;
    button.setAttribute("role", "menuitem");
    button.addEventListener("click", () => { closeMenu(); item.run(); });
    menu.append(button);
  });
  document.body.append(menu);
  // Не вылезать за окно: у правого и нижнего края меню открывается влево и вверх.
  const { width, height } = menu.getBoundingClientRect();
  menu.style.left = `${Math.min(x, innerWidth - width - 8)}px`;
  menu.style.top = `${Math.min(y, innerHeight - height - 8)}px`;
  open = menu;
  requestAnimationFrame(() => menu.classList.add("shown"));
}

addEventListener("mousedown", (e) => { if (open && !open.contains(e.target as Node)) closeMenu(); }, true);
addEventListener("keydown", (e) => { if (e.key === "Escape") closeMenu(); });
addEventListener("blur", closeMenu);
