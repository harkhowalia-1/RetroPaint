// A small pixel-exact paint program, mirroring RetroPaint's engine.
(() => {
  'use strict';

  const PALETTE = [
    '#000000', '#808080', '#800000', '#808000', '#008000', '#008080', '#000080',
    '#800080', '#808040', '#004040', '#0080ff', '#004080', '#8000ff', '#804000',
    '#ffffff', '#c0c0c0', '#ff0000', '#ffff00', '#00ff00', '#00ffff', '#0000ff',
    '#ff00ff', '#ffff80', '#00ff80', '#80ffff', '#8080ff', '#ff0080', '#ff8040',
  ];

  const TOOLS = [
    ['free-select', 'Free-Form Select', 'Selects a free-form part of the picture.', false],
    ['select', 'Select', 'Selects a rectangular part of the picture.', false],
    ['eraser', 'Eraser/Color Eraser', 'Erases a portion of the picture, using the selected eraser shape.', true],
    ['fill', 'Fill With Color', 'Fills an area with the current drawing color.', true],
    ['picker', 'Pick Color', 'Picks up a color from the picture for drawing.', true],
    ['magnifier', 'Magnifier', 'Changes the magnification.', false],
    ['pencil', 'Pencil', 'Draws a free-form line one pixel wide.', true],
    ['brush', 'Brush', 'Draws using a brush with the selected shape and size.', true],
    ['airbrush', 'Airbrush', 'Draws using an airbrush of the selected size.', true],
    ['text', 'Text', 'Inserts text into the picture.', false],
    ['line', 'Line', 'Draws a straight line with the selected line width.', true],
    ['curve', 'Curve', 'Draws a curved line with the selected line width.', false],
    ['rectangle', 'Rectangle', 'Draws a rectangle with the selected fill style.', true],
    ['polygon', 'Polygon', 'Draws a polygon with the selected fill style.', false],
    ['ellipse', 'Ellipse', 'Draws an ellipse with the selected fill style.', true],
    ['rounded-rectangle', 'Rounded Rectangle', 'Draws a rounded rectangle with the selected fill style.', true],
  ].map(([id, name, help, enabled]) => ({ id, name, help, enabled }));

  const canvas = document.getElementById('canvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  let W = canvas.width, H = canvas.height;
  let image, px;

  const state = {
    tool: 'pencil', previous: 'pencil',
    fg: '#000000', bg: '#ffffff',
    lineWidth: 1, eraser: 8, airbrush: 9, brush: 1, fillStyle: 0,
  };
  const undo = [];

  // ---------- Pixels ----------
  function toPixel(hex) {
    const n = parseInt(hex.slice(1), 16);
    return (0xff000000 | ((n & 0xff) << 16) | (n & 0xff00) | ((n >> 16) & 0xff)) >>> 0;
  }
  function toHex(p) {
    const r = p & 0xff, g = (p >> 8) & 0xff, b = (p >> 16) & 0xff;
    return '#' + [r, g, b].map(v => v.toString(16).padStart(2, '0')).join('');
  }
  function grab() {
    image = ctx.getImageData(0, 0, W, H);
    px = new Uint32Array(image.data.buffer);
  }
  function flush() { ctx.putImageData(image, 0, 0); }
  function set(x, y, c) { if (x >= 0 && y >= 0 && x < W && y < H) px[y * W + x] = c; }
  function pushUndo() { undo.push(px.slice()); if (undo.length > 40) undo.shift(); }

  function penOffsets(w) {
    if (w <= 1) return [[0, 0]];
    const c = (w - 1) / 2, r2 = w * w / 4, out = [];
    for (let dy = 0; dy < w; dy++) for (let dx = 0; dx < w; dx++) {
      const fx = dx - c, fy = dy - c;
      if (fx * fx + fy * fy <= r2) out.push([dx - Math.floor((w - 1) / 2), dy - Math.floor((w - 1) / 2)]);
    }
    return out;
  }
  function squareOffsets(n) {
    const out = [];
    for (let dy = 0; dy < n; dy++) for (let dx = 0; dx < n; dx++) out.push([dx - (n >> 1), dy - (n >> 1)]);
    return out;
  }
  function diagonal(n, forward) {
    const out = [];
    for (let i = 0; i < n; i++) out.push([i - (n >> 1), (forward ? n - 1 - i : i) - (n >> 1)]);
    return out;
  }
  const BRUSHES = [
    penOffsets(7), penOffsets(4), [[0, 0]],
    squareOffsets(8), squareOffsets(5), squareOffsets(2),
    diagonal(8, true), diagonal(5, true), diagonal(2, true),
    diagonal(8, false), diagonal(5, false), diagonal(2, false),
  ];

  function line(x0, y0, x1, y1, pen, c) {
    const dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0);
    const sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    for (;;) {
      for (const [ox, oy] of pen) set(x0 + ox, y0 + oy, c);
      if (x0 === x1 && y0 === y1) break;
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x0 += sx; }
      if (e2 <= dx) { err += dx; y0 += sy; }
    }
  }

  function inside(kind, rx, ry, rw, rh, inset, x, y) {
    const w = rw - 2 * inset, h = rh - 2 * inset;
    if (w <= 0 || h <= 0) return false;
    const pxx = x - rx - inset + 0.5, pyy = y - ry - inset + 0.5;
    if (pxx < 0 || pyy < 0 || pxx > w || pyy > h) return false;
    if (kind === 'rectangle') return true;
    if (kind === 'ellipse') {
      const dx = (pxx - w / 2) / (w / 2), dy = (pyy - h / 2) / (h / 2);
      return dx * dx + dy * dy <= 1.0001;
    }
    const rad = Math.max(0, Math.min(8 - inset, w / 2, h / 2));
    const cx = Math.min(Math.max(pxx, rad), w - rad), cy = Math.min(Math.max(pyy, rad), h - rad);
    return (pxx - cx) ** 2 + (pyy - cy) ** 2 <= rad * rad + 0.0001;
  }
  function shape(kind, a, b, lw, stroke, fill) {
    const rx = Math.min(a.x, b.x), ry = Math.min(a.y, b.y);
    const rw = Math.abs(a.x - b.x) + 1, rh = Math.abs(a.y - b.y) + 1;
    for (let y = Math.max(0, ry); y < Math.min(H, ry + rh); y++) {
      for (let x = Math.max(0, rx); x < Math.min(W, rx + rw); x++) {
        if (!inside(kind, rx, ry, rw, rh, 0, x, y)) continue;
        if (stroke != null && !inside(kind, rx, ry, rw, rh, lw, x, y)) px[y * W + x] = stroke;
        else if (fill != null) px[y * W + x] = fill;
      }
    }
  }

  function flood(x, y, c) {
    if (x < 0 || y < 0 || x >= W || y >= H) return;
    const target = px[y * W + x];
    if (target === c) return;
    const stack = [[x, y]];
    while (stack.length) {
      const [sx, sy] = stack.pop();
      const row = sy * W;
      if (px[row + sx] !== target) continue;
      let l = sx, r = sx;
      while (l > 0 && px[row + l - 1] === target) l--;
      while (r < W - 1 && px[row + r + 1] === target) r++;
      for (let i = l; i <= r; i++) px[row + i] = c;
      for (const ny of [sy - 1, sy + 1]) {
        if (ny < 0 || ny >= H) continue;
        const nrow = ny * W;
        for (let i = l; i <= r; i++) {
          if (px[nrow + i] === target) {
            stack.push([i, ny]);
            while (i <= r && px[nrow + i] === target) i++;
          }
        }
      }
    }
  }

  // ---------- Tools UI ----------
  const toolsEl = document.getElementById('tools');
  const optionsEl = document.getElementById('options');
  const help = document.getElementById('status-help');
  const posEl = document.getElementById('status-pos');
  const sizeEl = document.getElementById('status-size');

  TOOLS.forEach(t => {
    const b = document.createElement('button');
    b.className = 'tool' + (t.enabled ? '' : ' disabled');
    b.title = t.enabled ? t.name : `${t.name} — in the full app`;
    b.setAttribute('aria-label', b.title);
    b.setAttribute('aria-pressed', String(t.id === state.tool));
    b.innerHTML = `<img src="assets/tools/${t.id}.png" alt="" class="pixelated">`;
    b.addEventListener('click', () => {
      if (!t.enabled) { help.textContent = `${t.name}: available in the full RetroPaint app for Mac, iPad and iPhone.`; return; }
      selectTool(t.id);
    });
    b.addEventListener('mouseenter', () => { help.textContent = t.help; });
    b.dataset.tool = t.id;
    toolsEl.appendChild(b);
  });

  function selectTool(id) {
    if (state.tool !== 'picker') state.previous = state.tool;
    state.tool = id;
    toolsEl.querySelectorAll('.tool').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.tool === id)));
    help.textContent = TOOLS.find(t => t.id === id).help;
    renderOptions();
  }

  function glyph(w, h, draw) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    c.style.width = w + 'px'; c.style.height = h + 'px';
    draw(c.getContext('2d'));
    return c;
  }
  function option(on, onClick, makeGlyph) {
    const b = document.createElement('button');
    b.className = 'opt' + (on ? ' on' : '');
    b.appendChild(makeGlyph(on ? '#fff' : '#000'));
    b.addEventListener('click', () => { onClick(); renderOptions(); });
    return b;
  }
  function renderOptions() {
    optionsEl.innerHTML = '';
    optionsEl.classList.toggle('grid', state.tool === 'brush');
    const t = state.tool;
    if (t === 'eraser') {
      [4, 6, 8, 10].forEach(s => optionsEl.appendChild(option(state.eraser === s, () => state.eraser = s,
        col => glyph(10, 10, g => { g.fillStyle = col; g.fillRect((10 - s) / 2, (10 - s) / 2, s, s); }))));
    } else if (t === 'brush') {
      BRUSHES.forEach((pen, i) => optionsEl.appendChild(option(state.brush === i, () => state.brush = i,
        col => glyph(11, 11, g => { g.fillStyle = col; pen.forEach(([x, y]) => g.fillRect(5 + x, 5 + y, 1, 1)); }))));
    } else if (t === 'airbrush') {
      [9, 16, 24].forEach(s => optionsEl.appendChild(option(state.airbrush === s, () => state.airbrush = s,
        col => glyph(s + 2, s + 2, g => {
          g.fillStyle = col;
          let seed = s * 7919;
          for (let i = 0; i < s * 2; i++) {
            seed = (seed * 16807) % 2147483647; const a = (seed / 2147483647) * Math.PI * 2;
            seed = (seed * 16807) % 2147483647; const d = (seed / 2147483647) * s / 2;
            g.fillRect(Math.round(s / 2 + 1 + Math.cos(a) * d), Math.round(s / 2 + 1 + Math.sin(a) * d), 1, 1);
          }
        }))));
    } else if (t === 'line') {
      [1, 2, 3, 4, 5].forEach(w => optionsEl.appendChild(option(state.lineWidth === w, () => state.lineWidth = w,
        col => glyph(30, 7, g => { g.fillStyle = col; g.fillRect(1, (7 - w) >> 1, 28, w); }))));
    } else if (['rectangle', 'ellipse', 'rounded-rectangle'].includes(t)) {
      [0, 1, 2].forEach(f => optionsEl.appendChild(option(state.fillStyle === f, () => state.fillStyle = f,
        col => glyph(28, 14, g => {
          if (f > 0) { g.fillStyle = '#716f64'; g.fillRect(1, 1, 26, 12); }
          if (f < 2) { g.strokeStyle = col; g.lineWidth = 1; g.strokeRect(1.5, 1.5, 25, 11); }
        }))));
    }
  }

  // ---------- Colors ----------
  const paletteEl = document.getElementById('palette');
  const fgEl = document.getElementById('fg-swatch'), bgEl = document.getElementById('bg-swatch');
  function showColors() { fgEl.style.background = state.fg; bgEl.style.background = state.bg; }
  PALETTE.forEach(hex => {
    const b = document.createElement('button');
    b.className = 'swatch';
    b.style.background = hex;
    b.setAttribute('aria-label', `Color ${hex}`);
    b.addEventListener('click', () => { state.fg = hex; showColors(); });
    b.addEventListener('contextmenu', e => { e.preventDefault(); state.bg = hex; showColors(); });
    paletteEl.appendChild(b);
  });

  // ---------- Drawing ----------
  let drag = null, sprayTimer = null;

  function point(e) {
    const r = canvas.getBoundingClientRect();
    return { x: Math.floor((e.clientX - r.left) * W / r.width), y: Math.floor((e.clientY - r.top) * H / r.height) };
  }
  function constrain(a, b, square) {
    const dx = b.x - a.x, dy = b.y - a.y, m = Math.max(Math.abs(dx), Math.abs(dy));
    if (!square) {
      if (Math.abs(dx) > Math.abs(dy) * 2) return { x: b.x, y: a.y };
      if (Math.abs(dy) > Math.abs(dx) * 2) return { x: a.x, y: b.y };
    }
    return { x: a.x + Math.sign(dx || 1) * m, y: a.y + Math.sign(dy || 1) * m };
  }
  function spray() {
    if (!drag) return;
    const r = state.airbrush / 2;
    for (let i = 0; i < (state.airbrush >> 1) + 2; i++) {
      const a = Math.random() * Math.PI * 2, d = Math.random() * r;
      set(drag.last.x + Math.round(Math.cos(a) * d), drag.last.y + Math.round(Math.sin(a) * d), drag.fg);
    }
    flush();
  }

  canvas.addEventListener('contextmenu', e => e.preventDefault());
  canvas.addEventListener('pointerdown', e => {
    if (e.button > 2) return;
    canvas.setPointerCapture(e.pointerId);
    const p = point(e);
    const secondary = e.button === 2;
    const fg = toPixel(secondary ? state.bg : state.fg), bg = toPixel(secondary ? state.fg : state.bg);
    drag = { start: p, last: p, fg, bg, secondary, base: null };
    const t = state.tool;
    if (t === 'picker') { pick(p, secondary); return; }
    pushUndo();
    if (t === 'pencil') { set(p.x, p.y, fg); }
    else if (t === 'brush') { line(p.x, p.y, p.x, p.y, BRUSHES[state.brush], fg); }
    else if (t === 'eraser') { erase(p, p); }
    else if (t === 'fill') { flood(p.x, p.y, fg); drag = null; }
    else if (t === 'airbrush') { spray(); sprayTimer = setInterval(spray, 30); }
    else { drag.base = px.slice(); moveTo(p, e.shiftKey); }
    flush();
  });
  canvas.addEventListener('pointermove', e => {
    const p = point(e);
    posEl.textContent = p.x >= 0 && p.y >= 0 && p.x < W && p.y < H ? `${p.x},${p.y}` : '';
    if (!drag) return;
    if (state.tool === 'picker') { pick(p, drag.secondary); return; }
    const evts = e.getCoalescedEvents ? e.getCoalescedEvents() : [e];
    for (const ev of evts) moveTo(point(ev), e.shiftKey);
    flush();
  });
  const end = () => {
    if (sprayTimer) { clearInterval(sprayTimer); sprayTimer = null; }
    if (drag && state.tool === 'picker') selectTool(state.previous);
    drag = null;
    sizeEl.textContent = '';
  };
  canvas.addEventListener('pointerup', end);
  canvas.addEventListener('pointercancel', end);
  canvas.addEventListener('pointerleave', () => { if (!drag) posEl.textContent = ''; });

  function erase(a, b) {
    if (drag.secondary) colorErase(a, b);
    else line(a.x, a.y, b.x, b.y, squareOffsets(state.eraser), toPixel(state.bg));
  }
  // Color eraser: replace only the foreground colour along the stroke.
  function colorErase(a, b) {
    const pen = squareOffsets(state.eraser), target = toPixel(state.fg), repl = toPixel(state.bg);
    let x0 = a.x, y0 = a.y;
    const dx = Math.abs(b.x - x0), dy = -Math.abs(b.y - y0), sx = x0 < b.x ? 1 : -1, sy = y0 < b.y ? 1 : -1;
    let err = dx + dy;
    for (;;) {
      for (const [ox, oy] of pen) {
        const x = x0 + ox, y = y0 + oy;
        if (x >= 0 && y >= 0 && x < W && y < H && px[y * W + x] === target) px[y * W + x] = repl;
      }
      if (x0 === b.x && y0 === b.y) break;
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x0 += sx; }
      if (e2 <= dx) { err += dx; y0 += sy; }
    }
  }

  function moveTo(p, shift) {
    const t = state.tool, d = drag;
    if (t === 'pencil') line(d.last.x, d.last.y, p.x, p.y, [[0, 0]], d.fg);
    else if (t === 'brush') line(d.last.x, d.last.y, p.x, p.y, BRUSHES[state.brush], d.fg);
    else if (t === 'eraser') erase(d.last, p);
    else if (t === 'airbrush') { /* sprayed by the timer at d.last */ }
    else if (d.base) {
      px.set(d.base);
      const end = shift ? constrain(d.start, p, t !== 'line') : p;
      if (t === 'line') line(d.start.x, d.start.y, end.x, end.y, penOffsets(state.lineWidth), d.fg);
      else {
        const kind = t === 'rounded-rectangle' ? 'rounded' : t;
        const stroke = state.fillStyle === 2 ? null : d.fg;
        const fill = state.fillStyle === 0 ? null : state.fillStyle === 1 ? d.bg : d.fg;
        shape(kind, d.start, end, state.lineWidth, stroke, fill);
      }
      sizeEl.textContent = `${Math.abs(end.x - d.start.x) + 1}x${Math.abs(end.y - d.start.y) + 1}`;
    }
    d.last = p;
  }

  function pick(p, secondary) {
    if (p.x < 0 || p.y < 0 || p.x >= W || p.y >= H) return;
    const hex = toHex(px[p.y * W + p.x]);
    if (secondary) state.bg = hex; else state.fg = hex;
    showColors();
  }

  // ---------- Commands ----------
  function loadImage(src, fit) {
    const img = new Image();
    img.onload = () => {
      W = canvas.width = fit ? Math.min(img.naturalWidth, 1024) : img.naturalWidth;
      H = canvas.height = fit ? Math.round(img.naturalHeight * W / img.naturalWidth) : img.naturalHeight;
      ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, H);
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(img, 0, 0, W, H);
      grab();
      undo.length = 0;
    };
    img.src = src;
  }

  const commands = {
    new() { pushUndo(); px.fill(toPixel('#ffffff')); flush(); },
    open() { document.getElementById('file-input').click(); },
    save() {
      canvas.toBlob(blob => {
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob); a.download = 'untitled.png'; a.click();
        setTimeout(() => URL.revokeObjectURL(a.href), 1000);
      });
    },
    demo() { pushUndo(); loadImage('assets/demo.png', false); },
    undo() { const prev = undo.pop(); if (prev && prev.length === px.length) { px.set(prev); flush(); } },
    flipH() { pushUndo(); for (let y = 0; y < H; y++) px.subarray(y * W, y * W + W).reverse(); flush(); },
    flipV() {
      pushUndo();
      const copy = px.slice();
      for (let y = 0; y < H; y++) px.set(copy.subarray((H - 1 - y) * W, (H - y) * W), y * W);
      flush();
    },
    invert() { pushUndo(); for (let i = 0; i < px.length; i++) px[i] ^= 0x00ffffff; flush(); },
    clear() { pushUndo(); px.fill(toPixel(state.bg)); flush(); },
  };
  document.getElementById('file-input').addEventListener('change', e => {
    const f = e.target.files[0];
    if (f) loadImage(URL.createObjectURL(f), true);
    e.target.value = '';
  });
  window.RetroPaint = { run: name => commands[name] && commands[name]() };

  document.addEventListener('keydown', e => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z' && !/INPUT|TEXTAREA/.test(document.activeElement.tagName)) {
      e.preventDefault(); commands.undo();
    }
  });

  // ---------- Start ----------
  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, H);
  grab();
  renderOptions();
  showColors();
  loadImage('assets/demo.png', false);
})();
