// Сфера надиктовки — окно поверх всех, фокус не берёт, клики пропускает (как NSPanel на маке).
// На маке это шейдер Metal (Orb.metal): стеклянный шар, внутри полосы света по частотам голоса,
// «думает» — свет бежит по полосам, «готово» — зелёная заливка снизу. Здесь — тот же сценарий на
// canvas; точный перенос шейдера на WebGL — отдельной задачей.

import { listen } from "@tauri-apps/api/event";

type State = "listening" | "recognizing" | "copied" | "error" | "idle";
const canvas = document.getElementById("orb") as HTMLCanvasElement;
const ctx = canvas.getContext("2d")!;
let state: State = "idle";
let level = 0, smooth = 0, since = performance.now(), message = "";
const coral = [229, 77, 51];

function resize() {
  const r = devicePixelRatio || 1;
  canvas.width = innerWidth * r;
  canvas.height = innerHeight * r;
  ctx.setTransform(r, 0, 0, r, 0, 0);
}
addEventListener("resize", resize);
resize();

function frame(now: number) {
  const w = innerWidth, h = innerHeight, cx = w / 2, cy = h / 2, R = Math.min(w, h) * 0.32;
  const t = (now - since) / 1000;
  // Голос сглаживается каждый кадр — без рывков, как OrbClock на маке.
  smooth += (level - smooth) * 0.18;
  ctx.clearRect(0, 0, w, h);
  if (state === "idle") { requestAnimationFrame(frame); return; }

  // Ореол.
  const halo = ctx.createRadialGradient(cx, cy, R * 0.6, cx, cy, R * 1.9);
  halo.addColorStop(0, `rgba(${coral},${0.18 + smooth * 0.25})`);
  halo.addColorStop(1, "rgba(229,77,51,0)");
  ctx.fillStyle = halo;
  ctx.beginPath(); ctx.arc(cx, cy, R * 1.9, 0, Math.PI * 2); ctx.fill();

  // Стеклянный шар.
  ctx.save();
  ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.clip();
  const glass = ctx.createRadialGradient(cx - R * 0.3, cy - R * 0.4, R * 0.1, cx, cy, R);
  glass.addColorStop(0, "rgba(255,255,255,0.95)");
  glass.addColorStop(1, "rgba(240,236,234,0.88)");
  ctx.fillStyle = glass;
  ctx.fillRect(cx - R, cy - R, R * 2, R * 2);

  // Четыре полосы света: слушает — от голоса, думает — бегущий свет, готово — зелёная заливка.
  for (let i = 0; i < 4; i++) {
    const y = cy - R * 0.45 + i * R * 0.3;
    const phase = state === "recognizing" ? Math.max(0, Math.sin(t * 6 - i * 0.9)) : 0;
    const amp = state === "listening" ? smooth * (0.6 + 0.4 * Math.sin(t * 3 + i)) : phase;
    const wave = (x: number) => y + Math.sin(x / R * 5 + t * 4 + i) * R * 0.12 * (0.2 + amp);
    ctx.lineWidth = 10 + amp * 12;
    ctx.strokeStyle = `rgba(${coral},${0.08 + amp * 0.35})`;
    ctx.filter = "blur(6px)";
    ctx.beginPath();
    for (let x = cx - R; x <= cx + R; x += 4) x === cx - R ? ctx.moveTo(x, wave(x)) : ctx.lineTo(x, wave(x));
    ctx.stroke();
    ctx.filter = "none";
    ctx.lineWidth = 1.5;
    ctx.strokeStyle = `rgba(${coral},${0.35 + amp * 0.6})`;
    ctx.stroke();
  }
  if (state === "copied") {
    const fill = Math.min(1, t / 0.6);
    ctx.fillStyle = "rgba(52,199,89,0.85)";
    ctx.fillRect(cx - R, cy + R - fill * R * 2, R * 2, fill * R * 2);
  }
  ctx.restore();

  // Кромка стекла и блик.
  ctx.lineWidth = 1;
  ctx.strokeStyle = "rgba(255,255,255,0.9)";
  ctx.beginPath(); ctx.arc(cx, cy, R - 0.5, 0, Math.PI * 2); ctx.stroke();
  const glint = ctx.createLinearGradient(cx, cy - R, cx, cy);
  glint.addColorStop(0, "rgba(255,255,255,0.7)"); glint.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = glint;
  ctx.beginPath(); ctx.ellipse(cx, cy - R * 0.55, R * 0.55, R * 0.28, 0, 0, Math.PI * 2); ctx.fill();

  if (state === "error" && message) {
    ctx.font = "12px system-ui"; ctx.textAlign = "center"; ctx.fillStyle = "rgba(0,0,0,0.75)";
    ctx.fillText(message, cx, cy + R + 22);
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

void listen<{ state: State; level?: number; message?: string }>("dictation", (e) => {
  const p = e.payload;
  if (p.state === "level" as State) { level = p.level ?? 0; return; }
  if (p.state !== state) since = performance.now();
  state = p.state;
  message = p.message ?? "";
});
