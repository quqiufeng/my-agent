// Tmall Genie X1 — 等距图 + 运动（按 anatomy motion.md：缓动/弹簧(过冲) + burst 一次事件 + 拆解）
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as k from "../../kit/iso-kit.mjs";
import { smooth, burst } from "../../kit/gl.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const theme = process.argv.includes("--light") ? "light" : "dark";
const WIDTH = 560, HEIGHT = 660, FIGH = 560;

const R = 42, RB = 46, Z0 = 0, BODY_TOP = 118, TOP_Z = BODY_TOP + 6;
// —— 运动时间线（motion.md）——
const FR = process.env.ISO_FRAME !== undefined ? Number(process.env.ISO_FRAME) : 0;
const FN = Number(process.env.ISO_N || 1);
const t = FN > 1 ? FR / FN : 0;
const easeOutBack = (c) => { const s = 1.70158, c3 = c - 1; return 1 + (s + 1) * c3 * c3 * c3 + s * c3 * c3; };  // 有过冲(像弹簧)
let lift; // 顶部组件抬升（0=合，1=拆开到顶）
if (t < 0.42) lift = 0;
else if (t < 0.60) lift = easeOutBack((t - 0.42) / 0.18);
else if (t < 0.86) lift = 1;
else lift = 1 - easeOutBack((t - 0.86) / 0.14);
const LY = 44 * lift;                       // 抬升量（世界单位）
const wakeAge = t - 0.42;
const flash = (wakeAge > 0 && t < 0.62) ? burst(wakeAge, 0.08, 0.22) : 0;   // "唤醒" 一次事件：attack 80ms + decay

const P = k.fitProjection(
  [...k.boxCorners({ x: -RB, y: -RB, w: RB * 2, d: RB * 2, r: 0 }, -12, TOP_Z + LY + 6)],
  WIDTH, FIGH, { pad: 36, azimuth: 45 },
);
const S = (p, s) => k.solidSvg(p, s);
const L = (d, s) => k.lineSvg(d, s);
const D = (pts, s) => k.dotsSvg(pts, s);
const at = (p) => k.iso(p, P);
const z = (v) => v + LY;                     // 顶部件的 z（随 lift 抬升）

function micRing() {
  const pts = [];
  for (let i = 0; i < 6; i++) { const a = (Math.PI * 2 * i) / 6; pts.push(at([24 * Math.cos(a), 24 * Math.sin(a), z(TOP_Z)])); }
  return D(pts, { size: 1.1, tone: "mid" });
}

const body = [
  `<path class="iso-halo" d="${k.haloOf({ x: -RB, y: -RB, w: RB * 2, d: RB * 2, r: RB }, -12, 10, P)}"/>`,
  S(k.cylinder(0, 0, RB, -10, 6, P, 56), { tone: "lo" }),           // 脚
  S(k.cylinder(0, 0, RB - 3, -4, 6, P, 56), { tone: "mid" }),
  S(k.cylinder(0, 0, R, Z0, BODY_TOP, P, 64, 1.0), { tone: "hi" }), // 机身
  L(k.knurl(0, 0, R, 14, 76, 140, P, 0.25), { tone: "lo" }),        // 出音缝
  L(k.sideArc(0, 0, R, 14, P, 48), { tone: "lo" }),
  L(k.sideArc(0, 0, R, 76, P, 48), { tone: "lo" }),
  L(k.sideArc(0, 0, R, 92, P, 48), { tone: "faint" }),
  // —— 顶部组件（随 lift 抬升）——
  S(k.cylinder(0, 0, R, z(BODY_TOP), 6, P, 64, 0.6), { tone: "mid" }),        // 顶盖
  L(k.ring(0, 0, R - 4, z(TOP_Z), P, 64), { tone: "lo" }),                     // 内圈
  L(k.ring(0, 0, 26, z(TOP_Z), P, 64), { tone: flash > 0.3 ? "lit" : "hi" }),  // LED 环（唤醒时变亮）
  L(k.ring(0, 0, 14 + 26 * Math.max(0, (t * 2) % 1), z(TOP_Z), P, 64), { tone: "faint" }), // 唤醒波
  micRing(),
  S(k.cylinder(0, 0, 7, z(TOP_Z), 2.4, P, 32), { tone: "lo" }),                // 中央按键
  // —— 底部中文说明（仓耳今楷）——
  `<text x="${WIDTH / 2}" y="${HEIGHT - 72}" text-anchor="middle" font-family="TsangerJinKai02, 仓耳今楷02" font-size="27" fill="var(--anatomy-text)">天猫精灵 X1 智能音箱</text>`,
];

const svg = k.figureSvg({
  width: WIDTH, height: HEIGHT,
  label: "A Tmall Genie X1 smart speaker, isometric: a tall cylinder on a round foot with speaker slots round its lower half; on a wake word its top face (a ring of six microphones, a lit light ring and a centre button) lifts off with a spring.",
  body: [body.join("")],
});
writeFileSync(join(HERE, theme === "light" ? "genie-light.html" : "genie.html"),
  k.pageHtml({ title: "Tmall Genie X1", theme, width: WIDTH, body: `<div class="iso-stage">${svg}</div>` }));
if (process.env.ISO_SVG) writeFileSync(process.env.ISO_SVG, svg);
console.log("ok");
