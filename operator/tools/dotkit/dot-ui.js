/*
 * dot-ui.js - dependency-free canvas renderers for the dot-matrix dashboard style.
 * Geometry and colour rules mirror the WPF controls in ../wpf/Controls one to one.
 *
 * Markup usage (call DotUI.mount() once, then DotUI.render(el, {...}) to update):
 *   <canvas data-dot="text" data-text="1300"></canvas>
 *   <canvas data-dot="bar" data-value="72" data-max="90" data-warn="70" data-crit="80"></canvas>
 *   <canvas data-dot="ring" data-value="64" data-max="100" data-warn="80" data-crit="90"></canvas>
 *   <canvas data-dot="columns" data-values="12,40,88" data-max="100"></canvas>
 *   <canvas data-dot="sparkline" data-values="10,20,15" data-min="0" data-max="100"></canvas>
 *   <div class="dot-slider"><input type="range" min="0" max="100" value="56"></div>
 */
(function (global) {
  "use strict";

  const palette = {
    ink: "#EDEAE4",
    unlit: "#373431",
    faint: "#2A2725",
    accent: "#FF5A36",
    warning: "#FFB547",
    critical: "#FF3B3B",
  };

  // 5x7 glyphs, same table as DotMatrixText.cs. "1" = lit dot.
  const glyphs = {
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    A: ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    B: ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    C: ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    D: ["11100", "10010", "10001", "10001", "10001", "10010", "11100"],
    E: ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    F: ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    G: ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    H: ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    I: ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    J: ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    K: ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    L: ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    M: ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    N: ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
    O: ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    P: ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    Q: ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    R: ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    S: ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    T: ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    U: ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    V: ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    W: ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    X: ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    Y: ["10001", "10001", "10001", "01010", "00100", "00100", "00100"],
    Z: ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "%": ["11000", "11001", "00010", "00100", "01000", "10011", "00011"],
    "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
    "/": ["00000", "00001", "00010", "00100", "01000", "10000", "00000"],
    _: ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
    "-": ["000", "000", "000", "111", "000", "000", "000"],
    "°": ["010", "101", "010", "000", "000", "000", "000"],
    ".": ["0", "0", "0", "0", "0", "0", "1"],
    ":": ["0", "1", "0", "0", "0", "1", "0"],
    " ": ["000", "000", "000", "000", "000", "000", "000"],
  };

  const isNum = (v) => typeof v === "number" && !Number.isNaN(v);

  // DotPalette.Fraction
  function fraction(value, min, max) {
    const span = max - min;
    if (!(span > 0) || !isNum(value)) return 0;
    return Math.min(1, Math.max(0, (value - min) / span));
  }

  // DotPalette.ForValue
  function colorFor(value, warn, crit, normal) {
    if (isNum(crit) && value >= crit) return palette.critical;
    if (isNum(warn) && value >= warn) return palette.warning;
    return normal;
  }

  /** Text colour level for a reading: "critical" | "warning" | "normal". Same rule as Gauge.LevelOf. */
  function level(value, o = {}) {
    if (!isNum(value)) return "normal";
    if ((isNum(o.crit) && value >= o.crit) || (isNum(o.floor) && value <= o.floor)) return "critical";
    if (isNum(o.warn) && value >= o.warn) return "warning";
    return "normal";
  }

  function resolveColor(c) {
    return palette[c] || c || palette.ink;
  }

  /** Sizes the canvas backing store for devicePixelRatio and returns a context in CSS pixels. */
  function prepare(canvas, cssWidth, cssHeight) {
    const dpr = global.devicePixelRatio || 1;
    const w = cssWidth ?? canvas.clientWidth;
    const h = cssHeight ?? canvas.clientHeight;
    if (cssWidth != null) canvas.style.width = cssWidth + "px";
    if (cssHeight != null) canvas.style.height = cssHeight + "px";
    canvas.width = Math.max(1, Math.round(w * dpr));
    canvas.height = Math.max(1, Math.round(h * dpr));
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    return { ctx, w, h };
  }

  function dot(ctx, x, y, r, color) {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }

  function roundRect(ctx, x, y, w, h, r, color) {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.roundRect ? ctx.roundRect(x, y, w, h, r) : ctx.rect(x, y, w, h);
    ctx.fill();
  }

  // DotMatrixText.cs - canvas is sized to the text.
  function text(canvas, str, o = {}) {
    const size = o.dot ?? 3;
    const gap = o.gap ?? 1.2;
    const pitch = size + gap;
    const list = String(str ?? "").toUpperCase().split("").map((ch) => glyphs[ch] || glyphs[" "]);
    const columns = list.length ? list.reduce((sum, g) => sum + g[0].length + 1, 0) - 1 : 0;
    const width = columns ? columns * pitch - gap : 0;
    const height = 7 * pitch - gap;
    const { ctx } = prepare(canvas, Math.ceil(width), Math.ceil(height));
    const color = resolveColor(o.color);
    const r = size / 2;
    let x = 0;
    for (const g of list) {
      for (let row = 0; row < 7; row++) {
        for (let col = 0; col < g[row].length; col++) {
          if (g[row][col] === "1") dot(ctx, x + col * pitch + r, row * pitch + r, r, color);
        }
      }
      x += (g[0].length + 1) * pitch;
    }
  }

  // DotBar.cs - CSS width from layout, height defaults to dot*2+10.
  function bar(canvas, o = {}) {
    const size = o.dot ?? 3.4;
    if (!canvas.style.height) canvas.style.height = size * 2 + 10 + "px";
    const { ctx, w, h } = prepare(canvas);
    if (w <= size) return;
    const min = o.min ?? 0;
    const max = o.max ?? 100;
    const value = o.value ?? min;
    const pitch = Math.max(size + 1, o.pitch ?? 7);
    const count = Math.max(2, Math.floor((w - size) / pitch) + 1);
    let lit = Math.round(fraction(value, min, max) * count);
    if (lit === 0 && value > min) lit = 1;
    const r = size / 2;
    const cy = h / 2;
    const normal = resolveColor(o.color);
    for (let i = 0; i < count; i++) {
      const x = r + i * pitch;
      if (i < lit) {
        const dotValue = min + ((i + 1) / count) * (max - min);
        dot(ctx, x, cy, r, colorFor(dotValue, o.warn, o.crit, normal));
      } else {
        dot(ctx, x, cy, r * 0.62, palette.unlit);
      }
    }
    const track = (count - 1) * pitch;
    const marker = (v, color) => {
      if (!isNum(v) || v < min || v > max) return;
      const x = r + fraction(v, min, max) * track;
      roundRect(ctx, x - 0.9, cy - r - 5, 1.8, 3.2, 0.9, color);
      roundRect(ctx, x - 0.9, cy + r + 1.8, 1.8, 3.2, 0.9, color);
    };
    marker(o.floor, palette.critical);
    marker(o.warn, palette.warning);
    marker(o.crit, palette.critical);
  }

  // DotRing.cs - 300 degree sweep starting at 120 degrees (y axis points down).
  function ring(canvas, o = {}) {
    const { ctx, w, h } = prepare(canvas);
    const size = Math.min(w, h);
    if (size <= 0) return;
    const cx = w / 2;
    const cy = h / 2;
    const outer = size / 2 - 3;
    const radius = outer - 10;
    const at = (rad, deg) => {
      const a = (deg * Math.PI) / 180;
      return [cx + rad * Math.cos(a), cy + rad * Math.sin(a)];
    };
    for (let i = 0; i < 90; i++) {
      const [x, y] = at(outer, i * 4);
      dot(ctx, x, y, 0.9, palette.faint);
    }
    const min = o.min ?? 0;
    const max = o.max ?? 100;
    const value = o.value ?? min;
    const count = Math.max(8, o.count ?? 56);
    let lit = Math.round(fraction(value, min, max) * count);
    if (lit === 0 && value > min) lit = 1;
    const r = (o.dot ?? 4.4) / 2;
    const normal = resolveColor(o.color);
    for (let i = 0; i < count; i++) {
      const [x, y] = at(radius, 120 + (300 * i) / (count - 1));
      if (i < lit) {
        const dotValue = min + ((i + 1) / count) * (max - min);
        dot(ctx, x, y, r, colorFor(dotValue, o.warn, o.crit, normal));
      } else {
        dot(ctx, x, y, r * 0.55, palette.unlit);
      }
    }
    const marker = (v, color) => {
      if (!isNum(v) || v < min || v > max) return;
      const [x, y] = at(outer, 120 + 300 * fraction(v, min, max));
      dot(ctx, x, y, 2.4, color);
    };
    marker(o.warn, palette.warning);
    marker(o.crit, palette.critical);
  }

  // DotColumns.cs - one column of dots per value, bottom-up.
  function columns(canvas, o = {}) {
    const { ctx, w, h } = prepare(canvas);
    const values = o.values || [];
    if (!values.length || w <= 0 || h <= 0) return;
    const rows = Math.max(2, o.rows ?? 8);
    const max = o.max ?? 100;
    const highlightAt = o.highlightAt ?? 0.8;
    const pitchX = Math.min(12, w / values.length);
    const pitchY = h / rows;
    const r = Math.min(3.8, Math.max(1.4, Math.min(pitchX, pitchY) * 0.55)) / 2;
    const thresholdMode = isNum(o.warn) || isNum(o.crit);
    const normal = resolveColor(o.color);
    values.forEach((value, c) => {
      const f = fraction(value, 0, max);
      let lit = Math.ceil(f * rows - 1e-9);
      if (lit === 0 && value > 0) lit = 1;
      const color = thresholdMode
        ? colorFor(value, o.warn, o.crit, normal)
        : isNum(highlightAt) && f >= highlightAt ? palette.accent : normal;
      const x = pitchX * c + pitchX / 2;
      for (let row = 0; row < rows; row++) {
        const y = h - pitchY * row - pitchY / 2;
        if (row < lit) dot(ctx, x, y, r, color);
        else dot(ctx, x, y, r * 0.55, palette.unlit);
      }
    });
  }

  // DotSparkline.cs - dotted polyline with an accent head.
  function sparkline(canvas, o = {}) {
    const { ctx, w, h } = prepare(canvas);
    if (w <= 16 || h <= 12) return;
    for (let x = 2; x < w - 2; x += 6) dot(ctx, x, h - 1.5, 0.9, palette.faint);
    const values = o.values || [];
    if (!values.length) return;
    const min = isNum(o.min) ? o.min : Math.min(...values);
    let max = isNum(o.max) ? o.max : Math.max(...values);
    if (max - min < 1e-6) max = min + 1;
    const top = 8;
    const bottom = h - 6;
    const left = 3;
    const right = w - 10;
    const pts = values.map((v, i) => [
      values.length === 1 ? right : left + ((right - left) * i) / (values.length - 1),
      bottom - fraction(v, min, max) * (bottom - top),
    ]);
    const color = resolveColor(o.color);
    const step = 4.5;
    let carry = 0;
    for (let i = 1; i < pts.length; i++) {
      const [x0, y0] = pts[i - 1];
      const [x1, y1] = pts[i];
      const length = Math.hypot(x1 - x0, y1 - y0);
      let pos = carry;
      while (pos <= length) {
        const t = length === 0 ? 0 : pos / length;
        dot(ctx, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, 1.15, color);
        pos += step;
      }
      carry = pos - length;
    }
    const [lx, ly] = pts[pts.length - 1];
    ctx.strokeStyle = palette.accent;
    ctx.lineWidth = 1.2;
    ctx.beginPath();
    ctx.arc(lx, ly, 6, 0, Math.PI * 2);
    ctx.stroke();
    dot(ctx, lx, ly, 2.8, palette.accent);
  }

  const renderers = { text, bar, ring, columns, sparkline };

  function draw(el) {
    const o = el._dot;
    if (!o) return;
    if (o.type === "text") text(el, o.text, o);
    else renderers[o.type]?.(el, o);
  }

  /** Merge options into a mounted canvas and redraw. Example: DotUI.render(el, { value: 72 }). */
  function render(el, options) {
    el._dot = Object.assign(el._dot || { type: el.dataset.dot }, options);
    draw(el);
  }

  const num = (s) => (s === undefined || s === "" ? undefined : Number(s));
  const list = (s) => (s ? s.split(",").map(Number) : []);

  function optionsFromData(el) {
    const d = el.dataset;
    return {
      type: d.dot,
      text: d.text,
      value: num(d.value),
      values: list(d.values),
      min: num(d.min),
      max: num(d.max),
      warn: num(d.warn),
      crit: num(d.crit),
      floor: num(d.floor),
      dot: num(d.size),
      gap: num(d.gap),
      pitch: num(d.pitch),
      rows: num(d.rows),
      count: num(d.count),
      color: d.color,
    };
  }

  const strip = (o) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined));

  let observer = null;
  function observe(el) {
    if (!global.ResizeObserver) return;
    observer = observer || new ResizeObserver((entries) => entries.forEach((e) => draw(e.target)));
    observer.observe(el);
  }

  // DotSlider style: dot bar track under a transparent range input.
  function mountSlider(wrapper) {
    const input = wrapper.querySelector("input[type=range]");
    let canvas = wrapper.querySelector("canvas");
    if (!canvas) {
      canvas = document.createElement("canvas");
      wrapper.prepend(canvas);
    }
    const floor = num(wrapper.dataset.floor);
    const sync = () =>
      render(canvas, {
        type: "bar",
        value: Number(input.value),
        min: Number(input.min || 0),
        max: Number(input.max || 100),
        floor,
        pitch: 6.5,
        dot: 3.2,
        color: "accent",
      });
    input.addEventListener("input", sync);
    canvas._dotSync = sync;
    sync();
    observe(canvas);
  }

  /** Draws every [data-dot] canvas and .dot-slider under root, and redraws them on resize. */
  function mount(root = document) {
    root.querySelectorAll("canvas[data-dot]").forEach((el) => {
      if (el._dot) return;
      el._dot = strip(optionsFromData(el));
      draw(el);
      if (el._dot.type !== "text") observe(el);
    });
    root.querySelectorAll(".dot-slider").forEach((w) => {
      if (!w._mounted) {
        w._mounted = true;
        mountSlider(w);
      }
    });
  }

  global.DotUI = { palette, glyphs, fraction, level, text, bar, ring, columns, sparkline, render, mount };
})(window);
