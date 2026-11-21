// Moteur d'image du vidéoprojecteur : tout est dessiné en millimètres de cible (centre (0, 0), y vers le haut)
// sur un canevas de 1280 x 800 mm. projector.html le pose sur l'image du projecteur avec la calibration.
// Les effets viennent de la simulation (projecteur/simulation-ombres.html).
(function () {
  const MMW = 1280, MMH = 800, K = 1.25;
  const LCW = MMW * K, LCH = MMH * K, CX = LCW / 2, CY = LCH / 2;
  const ORDER = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];
  const RB = { bull: 6.35, obull: 15.9, tIn: 99, tOut: 107, dIn: 162, dOut: 170, board: 225.5, sur: 380, ring: 410 };
  const C = { fluo: '#FFE14D', sunset: '#FF7A2F', crep: '#FF4D8D', ciel: '#4FA3FF' };
  const HAPPY = ['p01', 'p04', 'p05', 'p08', 'p11'];
  // Zones libres autour de la cible (projecteur sur la baie, à gauche) : score, têtes, tags.
  // Tout reste sur le surround (anneau gris entre le bord de la cible et son bord extérieur) : rien sur le mur.
  const LAY = { score: { x: -255, y: 150, w: 110, h: 100 }, left: { x: -255, y: -150, w: 110, h: 110 }, tag: { x: 300, y: 0, w: 120, h: 110 } };
  const TAU = Math.PI * 2;
  const rnd = (a, b) => a + Math.random() * (b - a);
  const ease = t => 1 - Math.pow(1 - t, 3);
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const pick = a => a[Math.floor(Math.random() * a.length)];
  const P2 = (x, y) => [CX + x * K, CY - y * K];

  let g2 = null, effects = [], parts = [], shake = 0, boardLight = 1, playing = false, fxDim = 1;
  // Position du projecteur par rapport au centre de la cible (mm, z = distance au mur) : sert à placer
  // l'ombre de l'arceau et des caméras, qu'on laisse noires pour ne pas éclairer les objectifs.
  let PROJ = { x: -700, y: -530, z: 1550 };
  const heads = {};

  function init(canvas, headUrl) {
    canvas.width = LCW; canvas.height = LCH; g2 = canvas.getContext('2d');
    for (let i = 1; i <= 12; i++) { const n = 'p' + String(i).padStart(2, '0'); const im = new Image(); im.src = headUrl + n + '.png'; heads[n] = im; }
  }
  const ready = im => im && im.complete && im.naturalWidth > 0;

  /* ---------- formes ---------- */
  function segPath(i, r0, r1) {
    const a = (i * 18 - 9 - 90) * Math.PI / 180, b = (i * 18 + 9 - 90) * Math.PI / 180;
    g2.beginPath(); g2.arc(CX, CY, r1 * K, a, b); g2.arc(CX, CY, r0 * K, b, a, true); g2.closePath();
  }
  function ringPath(r0, r1) { g2.beginPath(); g2.arc(CX, CY, r1 * K, 0, TAU); g2.arc(CX, CY, r0 * K, TAU, 0, true); g2.closePath(); }
  function cellPath(h) {
    if (h.n === 25) { g2.beginPath(); g2.arc(CX, CY, (h.m === 2 ? RB.bull : RB.obull) * K, 0, TAU); return; }
    const i = ORDER.indexOf(h.n), r = Math.hypot(h.x, h.y);
    if (h.m === 3) segPath(i, RB.tIn, RB.tOut);
    else if (h.m === 2) segPath(i, RB.dIn, RB.dOut);
    else if (r < RB.tIn) segPath(i, RB.obull, RB.tIn);
    else segPath(i, RB.tOut, RB.dIn);
  }

  /* ---------- ombre de l'arceau et des caméras (vue du projecteur) ---------- */
  function onWall(qx, qy, qz) { const t = PROJ.z / (PROJ.z - qz); return [PROJ.x + t * (qx - PROJ.x), PROJ.y + t * (qy - PROJ.y)]; }
  function drawMask() {
    g2.save(); g2.fillStyle = '#000'; g2.strokeStyle = '#000';
    // arceau : tore de 410 mm, à 70 mm du mur, épaisseur 18 mm (+ marge)
    g2.lineWidth = 34 * K; g2.beginPath();
    for (let a = 0; a <= 360; a += 4) { const t = a * Math.PI / 180, [x, y] = onWall(Math.sin(t) * RB.ring, Math.cos(t) * RB.ring, 70), [X, Y] = P2(x, y); a ? g2.lineTo(X, Y) : g2.moveTo(X, Y); }
    g2.stroke();
    // caméras : 6 h, 10 h, 2 h, boîtier d'environ 60 mm qui dépasse de 110 mm
    for (const deg of [180, 300, 60]) {
      const t = deg * Math.PI / 180, cx = Math.sin(t) * RB.ring, cy = Math.cos(t) * RB.ring;
      for (const z of [40, 110]) { const [x, y] = onWall(cx, cy, z), [X, Y] = P2(x, y); g2.beginPath(); g2.arc(X, Y, 48 * K, 0, TAU); g2.fill(); }
    }
    g2.restore();
  }

  /* ---------- effets ---------- */
  function fx(dur, draw, delay = 0) { effects.push({ t: -delay, dur, draw }); }
  function blackout(dur, delay = 0, fade = .15) { effects.push({ t: -delay, dur, base: true, draw: (k, t) => { const a = Math.min(1, t / fade, (dur - t) / fade); boardLight = Math.min(boardLight, 1 - a); } }); }
  function fire(x, y, n, power) {
    for (let i = 0; i < n; i++) { const a = rnd(0, TAU), s = rnd(40, 220) * power;
      parts.push({ x, y, vx: Math.cos(a) * s * .6, vy: Math.sin(a) * s * .5 + rnd(80, 260) * power, life: 0, max: rnd(.5, 1.2), size: rnd(8, 22) * power, kind: 'fire' }); }
  }
  function embers(x, y, n) { for (let i = 0; i < n; i++) parts.push({ x: x + rnd(-15, 15), y: y + rnd(-15, 15), vx: rnd(-40, 40), vy: rnd(60, 220), life: -rnd(0, .3), max: rnd(.8, 1.4), size: rnd(2, 4), kind: 'ember' }); }
  function confetti(n) { const cols = [C.sunset, C.crep, C.fluo, C.ciel, '#ffffff'];
    for (let i = 0; i < n; i++) parts.push({ x: rnd(-560, 560), y: rnd(360, 520), vx: rnd(-60, 60), vy: rnd(-40, -160), life: -rnd(0, 1.5), max: rnd(2.5, 4), size: rnd(6, 12), rot: rnd(0, 6), vr: rnd(-8, 8), col: cols[i % 5], kind: 'confetti' }); }
  function rain(n, dur) { for (let i = 0; i < n; i++) parts.push({ x: rnd(-560, 600), y: rnd(350, 700), vx: -40, vy: -rnd(700, 900), life: -rnd(0, dur), max: 1.2, size: 1, kind: 'rain' }); }
  function fireworks(x, y, col) { for (let i = 0; i < 70; i++) { const a = i / 70 * TAU, s = rnd(180, 320);
    parts.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0, max: rnd(.9, 1.4), size: rnd(3, 5), col, kind: 'spark' }); } }
  function crack(x, y, branches, len) {
    const lines = [];
    for (let b = 0; b < branches; b++) { let a = rnd(0, TAU), px = x, py = y; const pts = [[px, py]];
      for (let s = 0; s < 12; s++) { a += rnd(-.5, .5); const st = len / 12 * rnd(.6, 1.4); px += Math.cos(a) * st; py += Math.sin(a) * st; pts.push([px, py]); }
      lines.push(pts); }
    fx(1.4, (k) => {
      const grow = Math.min(1, k * 3), alpha = k < .6 ? 1 : (1 - k) / .4;
      g2.globalCompositeOperation = 'lighter'; g2.lineCap = 'round';
      lines.forEach(pts => { const n = Math.max(2, Math.floor(pts.length * grow));
        [[9, 'rgba(255,77,141,' + .35 * alpha + ')'], [4, 'rgba(255,122,47,' + .8 * alpha + ')'], [1.6, 'rgba(255,240,180,' + alpha + ')']].forEach(([w, c]) => {
          g2.strokeStyle = c; g2.lineWidth = w; g2.beginPath();
          pts.slice(0, n).forEach(([px, py], i) => { const [X, Y] = P2(px, py); i ? g2.lineTo(X, Y) : g2.moveTo(X, Y); }); g2.stroke(); }); });
    });
  }
  function shock(x, y, maxR, col = '255,225,77', dur = .7) {
    fx(dur, (k) => { const [X, Y] = P2(x, y), e = ease(k);
      g2.globalCompositeOperation = 'lighter';
      g2.strokeStyle = `rgba(${col},${1 - k})`; g2.lineWidth = (14 * (1 - k) + 2); g2.beginPath(); g2.arc(X, Y, (10 + maxR * e) * K, 0, TAU); g2.stroke();
      g2.strokeStyle = `rgba(255,255,255,${.7 * (1 - k)})`; g2.lineWidth = 2; g2.beginPath(); g2.arc(X, Y, (6 + maxR * .7 * e) * K, 0, TAU); g2.stroke(); });
  }
  function flash(x, y, r) { fx(.28, (k) => { const [X, Y] = P2(x, y); const gr = g2.createRadialGradient(X, Y, 0, X, Y, r * K);
    gr.addColorStop(0, `rgba(255,255,255,${1 - k})`); gr.addColorStop(1, 'rgba(255,255,255,0)');
    g2.globalCompositeOperation = 'lighter'; g2.fillStyle = gr; g2.beginPath(); g2.arc(X, Y, r * K, 0, TAU); g2.fill(); }); }
  function lava(hit, dur = 1.4) {
    fx(dur, (k) => {
      cellPath(hit); g2.save(); g2.clip();
      const [X, Y] = P2(hit.x, hit.y), r = (20 + 260 * ease(Math.min(1, k * 1.6))) * K, al = k < .7 ? 1 : (1 - k) / .3;
      const gr = g2.createRadialGradient(X, Y, 0, X, Y, r);
      gr.addColorStop(0, `rgba(255,250,200,${al})`); gr.addColorStop(.35, `rgba(255,180,60,${al})`);
      gr.addColorStop(.7, `rgba(255,90,40,${al * .9})`); gr.addColorStop(1, `rgba(255,77,141,${al * .3})`);
      g2.fillStyle = gr; g2.fillRect(0, 0, LCW, LCH); g2.restore();
      cellPath(hit); g2.globalCompositeOperation = 'lighter'; g2.strokeStyle = `rgba(255,240,180,${al})`; g2.lineWidth = 3; g2.stroke();
    });
  }
  function neonWires(dur, col = '79,163,255') {
    fx(dur, (k) => {
      g2.globalCompositeOperation = 'lighter'; g2.lineWidth = 2.4;
      for (let i = 0; i < 20; i++) { const a = clamp(1 - Math.abs(k * 2 - i / 20 - .3) * 3, 0, 1); if (a <= 0) continue;
        const ang = (i * 18 - 9) * Math.PI / 180; g2.strokeStyle = `rgba(${col},${a})`; g2.beginPath();
        const [x0, y0] = P2(Math.sin(ang) * RB.obull, Math.cos(ang) * RB.obull), [x1, y1] = P2(Math.sin(ang) * RB.dOut, Math.cos(ang) * RB.dOut); g2.moveTo(x0, y0); g2.lineTo(x1, y1); g2.stroke(); }
      [RB.obull, RB.tIn, RB.tOut, RB.dIn, RB.dOut].forEach((r, j) => { const a = clamp(1 - Math.abs(k * 2 - j / 5 - .2) * 3, 0, 1); if (a <= 0) return; g2.strokeStyle = `rgba(${col},${a})`; g2.beginPath(); g2.arc(CX, CY, r * K, 0, TAU); g2.stroke(); });
    });
  }
  function lightningRing(r0, r1, dur = .9) {
    fx(dur, (k) => {
      g2.globalCompositeOperation = 'lighter';
      const head = k * Math.PI * 2.4, tail = Math.max(0, head - 2.2);
      for (let pass = 0; pass < 2; pass++) {
        g2.strokeStyle = pass ? 'rgba(255,255,255,.95)' : 'rgba(255,122,47,.7)'; g2.lineWidth = pass ? 2 : 8; g2.beginPath();
        let first = true;
        for (let a = tail; a <= head; a += 0.03) { const r = (r0 + r1) / 2 + rnd(-1, 1) * (r1 - r0) * .8; const X = CX + Math.sin(a) * r * K, Y = CY - Math.cos(a) * r * K; first ? g2.moveTo(X, Y) : g2.lineTo(X, Y); first = false; }
        g2.stroke();
      }
      ringPath(r0, r1); g2.fillStyle = `rgba(255,122,47,${.5 * (1 - k)})`; g2.fill();
    });
  }
  function godRays(x, y, dur = 1.2) {
    fx(dur, (k) => { const [X, Y] = P2(x, y), al = k < .2 ? k / .2 : (1 - k) / .8;
      g2.globalCompositeOperation = 'lighter';
      const gr = g2.createRadialGradient(X, Y, 0, X, Y, 900 * K); gr.addColorStop(0, `rgba(255,200,90,${.55 * al})`); gr.addColorStop(1, 'rgba(255,77,141,0)');
      g2.fillStyle = gr;
      for (let i = 0; i < 18; i++) { const a = i / 18 * TAU + k * 0.8, w = 0.07; g2.beginPath(); g2.moveTo(X, Y); g2.arc(X, Y, 900 * K, a - w, a + w); g2.closePath(); g2.fill(); }
    });
  }
  function vortex(dur = 1.3) {
    fx(dur, (k) => {
      g2.globalCompositeOperation = 'lighter';
      const bands = [[RB.dIn, RB.dOut], [RB.tOut, RB.dIn], [RB.tIn, RB.tOut], [RB.obull, RB.tIn]];
      bands.forEach((b, j) => { for (let i = 0; i < 20; i++) { const ph = ((k * 3 - j * .25 - i / 20) % 1 + 1) % 1; if (ph > .35) continue;
        segPath(i, b[0], b[1]); g2.fillStyle = `rgba(${j % 2 ? '255,77,141' : '255,122,47'},${(1 - ph / .35) * .9 * (1 - k * .5)})`; g2.fill(); } });
    });
  }
  function sprayTag(text, x, y, size, opts = {}) {
    const dur = opts.dur || 2, rot = opts.rot ?? -0.08, lines = text.split('\n');
    let fit = null;
    fx(dur, (k, t) => {
      if (!fit) {
        g2.font = Math.round(size * K) + 'px "Permanent Marker","Space Grotesk",sans-serif';
        const wmm = Math.max(...lines.map(l => g2.measureText(l).width)) / K + 24, hmm = size * 1.05 * lines.length + 20;
        if (x === 'R') { const Z = LAY.tag, sc = Math.min(1, Z.w / wmm, Z.h / hmm); fit = { x: Z.x, y: Z.y, size: size * sc }; } else fit = { x, y, size };
      }
      const sz = fit.size, reveal = Math.min(1, t / 0.4), alpha = k > .82 ? (1 - k) / .18 : 1, [X, Y] = P2(fit.x, fit.y);
      g2.translate(X, Y); g2.rotate(rot);
      g2.font = Math.round(sz * K) + 'px "Permanent Marker","Space Grotesk",sans-serif'; g2.textAlign = 'center'; g2.textBaseline = 'middle';
      const w = Math.max(...lines.map(l => g2.measureText(l).width)), lh = sz * K * 1.05, h = lh * lines.length;
      g2.beginPath(); g2.rect(-w / 2 - 30, -h / 2 - 40, (w + 60) * reveal, h + 80 + sz * K * .5); g2.clip();
      g2.globalAlpha = alpha;
      const gr = g2.createLinearGradient(-w / 2, 0, w / 2, 0); gr.addColorStop(0, opts.c1 || C.sunset); gr.addColorStop(1, opts.c2 || C.crep);
      lines.forEach((l, i) => { const ly = -h / 2 + lh * (i + .5);
        g2.lineWidth = Math.max(3, sz * K * .12); g2.strokeStyle = opts.stroke || C.fluo; g2.lineJoin = 'round'; g2.strokeText(l, 0, ly);
        g2.fillStyle = gr; g2.fillText(l, 0, ly); });
    });
  }
  // Texte écrit en courbe sur le surround, répété n fois, qui tourne autour de la cible.
  // Lettres debout vers l'extérieur, lecture dans le sens des aiguilles d'une montre.
  function ringTag(text, opts = {}) {
    const dur = opts.dur || 2.2, speed = opts.speed ?? .7, start = rnd(0, TAU);
    let layout = null;
    fx(dur, (k, t) => {
      const r0 = RB.board + 6, r1 = RB.sur - 6, rm = (r0 + r1) / 2, size = (r1 - r0) * (opts.scale || .62);
      g2.font = Math.round(size * K) + 'px "Permanent Marker","Space Grotesk",sans-serif';
      if (!layout) {
        const sp = size * K * .08, widths = [...text].map(ch => g2.measureText(ch).width + sp);
        const arc = widths.reduce((a, b) => a + b, 0) / (rm * K);
        const headArc = opts.head ? (r1 - r0) * 1.05 / rm : 0;
        const n = Math.max(1, Math.min(opts.n || 3, Math.floor(TAU / (arc * 1.2 + headArc))));
        layout = { widths, arc, n };
      }
      const { widths, arc, n } = layout;
      const appear = ease(Math.min(1, t / .35)), alpha = k > .8 ? (1 - k) / .2 : 1;
      // Départ rapide qui ralentit, puis rotation régulière.
      const turn = start + speed * t + (1 - appear) * -1.2;
      g2.textAlign = 'center'; g2.textBaseline = 'middle'; g2.lineJoin = 'round';
      g2.lineWidth = Math.max(3, size * K * .12); g2.globalAlpha = alpha;
      for (let c = 0; c < n; c++) {
        // Dans la moitié basse, lettres tête vers le centre et lecture inversée : toujours lisible du pas de tir.
        const mid = turn + c * TAU / n, low = Math.sin(mid) > 0, dir = low ? -1 : 1;
        let a = mid - dir * arc / 2;
        [...text].forEach((ch, i) => {
          const da = dir * widths[i] / (rm * K), am = a + da / 2;
          const R = rm * K * (.85 + .15 * appear);
          g2.save(); g2.translate(CX + Math.cos(am) * R, CY + Math.sin(am) * R); g2.rotate(am + (low ? -Math.PI / 2 : Math.PI / 2));
          g2.scale(appear, appear);
          g2.strokeStyle = opts.stroke || C.fluo; g2.strokeText(ch, 0, 0);
          g2.fillStyle = (i + c) % 2 ? (opts.c2 || C.crep) : (opts.c1 || C.sunset); g2.fillText(ch, 0, 0);
          g2.restore();
          a += da;
        });
        // Tête de Thibaut entre deux inscriptions, qui tourne avec elles.
        const im = opts.head && heads[opts.head];
        if (ready(im)) {
          const ah = mid + Math.PI / n, R = rm * K * (.85 + .15 * appear), hs = (r1 - r0) * .9 * K * appear;
          const ar = im.naturalHeight / im.naturalWidth, w = hs / Math.max(1, ar), h = w * ar;
          g2.save(); g2.translate(CX + Math.cos(ah) * R, CY + Math.sin(ah) * R); g2.rotate(Math.sin(t * 5 + c) * .15);
          if (opts.grey) g2.filter = 'grayscale(1) brightness(.85)';
          g2.drawImage(im, -w / 2, -h / 2, w, h); g2.restore();
        }
      }
    });
  }
  function headAt(name, Z, dur, mode, opts = {}) {
    fx(dur, (k, t) => {
      const im = heads[name]; if (!ready(im)) return;
      const ar = im.naturalHeight / im.naturalWidth; let wmm = Z.w * .95, hmm = wmm * ar; if (hmm > Z.h * .95) { hmm = Z.h * .95; wmm = hmm / ar; }
      let s = 1, rot = 0, dy = 0; const al = k > .85 ? (1 - k) / .15 : 1;
      if (mode === 'pop') { s = ease(Math.min(1, t / .3)); rot = Math.sin(t * 5) * .08; }
      if (mode === 'spin') { const e = Math.min(1, t / .5); s = ease(e); rot = (1 - ease(e)) * Math.PI * 4; }
      if (mode === 'shake') { s = Math.min(1, t / .2); rot = Math.sin(t * 28) * .22 * Math.max(0, 1 - t / 1.2); }
      if (mode === 'sink') { s = 1 - ease(k) * .35; dy = -ease(k) * hmm * .18; }
      if (mode === 'zoom') { const e = Math.min(1, t / .25); s = k < .6 ? (.2 + ease(e) * .8) : 1 - (k - .6) / .4 * .9; rot = t * 2; }
      const [X, Y] = P2(Z.x, Z.y + dy), W2 = wmm * K * s, H2 = hmm * K * s;
      g2.globalAlpha = al; if (opts.grey) g2.filter = 'grayscale(1) brightness(.85)';
      g2.translate(X, Y); g2.rotate(rot); g2.drawImage(im, -W2 / 2, -H2 / 2, W2, H2);
    });
  }
  function headCarousel(names, dur) {
    const r = 285, size = 100;
    fx(dur, (k, t) => {
      const n = names.length;
      names.forEach((name, i) => { const im = heads[name]; if (!ready(im)) return;
        const appear = clamp((t - i * .08) / .35, 0, 1); if (appear <= 0) return;
        const a = i / n * TAU + t * .9, bob = Math.sin(t * 6 + i) * 6, x = Math.cos(a) * (r + bob), y = Math.sin(a) * (r + bob);
        const sc = ease(appear) * (k > .88 ? (1 - k) / .12 : 1), ar = im.naturalHeight / im.naturalWidth;
        const w = size * K * sc / Math.max(1, ar), h = w * ar, [X, Y] = P2(x, y);
        g2.save(); g2.translate(X, Y); g2.rotate(Math.sin(t * 4 + i) * .15); g2.drawImage(im, -w / 2, -h / 2, w, h); g2.restore(); });
    });
  }
  function shatter(dur = 2.4) {
    const shards = [];
    for (let i = 0; i < 20; i++) for (let b = 0; b < 2; b++) {
      const r0 = b ? RB.tOut : RB.obull, r1 = b ? RB.dOut : RB.tOut, a = i * 18 * Math.PI / 180, rm = (r0 + r1) / 2;
      shards.push({ i, r0, r1, ox: Math.sin(a) * rm, oy: Math.cos(a) * rm, vx: Math.sin(a) * rnd(250, 520), vy: Math.cos(a) * rnd(250, 520) + rnd(0, 200), vr: rnd(-6, 6), col: i % 2 ? (b ? '#1d8a4a' : '#eadfc6') : (b ? '#c8242f' : '#3a3a3a') });
    }
    fx(dur, (k, t) => {
      const al = k > .75 ? (1 - k) / .25 : 1;
      shards.forEach(s => { const x = s.ox + s.vx * t, y = s.oy + s.vy * t - 320 * t * t, [X, Y] = P2(x, y);
        g2.save(); g2.translate(X, Y); g2.rotate(s.vr * t); g2.translate(-CX - s.ox * K, -CY + s.oy * K);
        segPath(s.i, s.r0, s.r1); g2.globalAlpha = al; g2.fillStyle = s.col; g2.fill(); g2.strokeStyle = 'rgba(255,225,77,.9)'; g2.lineWidth = 2; g2.stroke(); g2.restore(); });
    });
  }
  function sunsetSpiral(dur) { fx(dur, (k, t) => { g2.globalCompositeOperation = 'lighter';
    for (let i = 0; i < 20; i++) { const on = ((i + Math.floor(t * 14)) % 4) < 2; if (!on) continue; segPath(i, RB.obull, RB.dOut); g2.fillStyle = i % 2 ? 'rgba(255,77,141,.55)' : 'rgba(255,122,47,.6)'; g2.fill(); } }); }
  function redPulse(dur) { fx(dur, (k, t) => { const a = Math.max(0, Math.sin(t * 14)) * (1 - k);
    g2.fillStyle = `rgba(255,30,60,${.65 * a})`; g2.beginPath(); g2.arc(CX, CY, RB.sur * K, 0, TAU); g2.fill(); }); }
  function tint(dur, col, amount) { fx(dur, (k) => { const a = amount * (k < .1 ? k / .1 : k > .85 ? (1 - k) / .15 : 1);
    g2.fillStyle = `rgba(${col},${a})`; g2.fillRect(-50, -50, LCW + 100, LCH + 100); }); }

  /* ---------- une fléchette (x, y en mm, y vers le haut) ---------- */
  function dart(h) {
    if (!h.m) {
      tint(1.8, '40,70,120', .45); rain(200, 1.2); 
      ringTag('MISS', { n: 4, c1: '#9aa0a6', c2: '#4FA3FF', stroke: '#dfe6ee', speed: -.5, head: 'p09', grey: true });
    } else if (h.n === 25) {
      flash(0, 0, 120); vortex(1.3); fire(0, 0, 70, 1.1); shock(0, 0, 520, '255,122,47', 1.1); embers(0, 0, 40); neonWires(1.3, '255,225,77');
      if (h.m === 2) { godRays(0, 0, 1.4); headAt('p12', { x: 0, y: 0, w: 300, h: 300 }, 1.5, 'zoom'); }
      ringTag(h.m === 2 ? 'BULL' : '25', { n: 4, speed: 1.1, head: pick(HAPPY) });
    } else if (h.m === 3) {
      flash(h.x, h.y, 90); lava(h, 1.5); fire(h.x, h.y, 100, 1.2); shock(h.x, h.y, 360); embers(h.x, h.y, 40); godRays(h.x, h.y, 1.2); crack(h.x, h.y, 5, 140);
      ringTag('TRIPLE ' + h.n, { n: 3, speed: .9, head: 'p03' });
    } else if (h.m === 2) {
      flash(h.x, h.y, 80); lava(h, 1.4); lightningRing(RB.dIn, RB.dOut, 1.0); fire(h.x, h.y, 60, 1); shock(h.x, h.y, 280, '255,77,141'); neonWires(1.1);
      ringTag('DOUBLE ' + h.n, { n: 3, speed: .8, c1: C.crep, c2: C.ciel, head: pick(HAPPY) });
    } else {
      flash(h.x, h.y, 60); lava(h, 1); fire(h.x, h.y, 30, .75); shock(h.x, h.y, 140, '255,225,77', .6); embers(h.x, h.y, 10);
      ringTag(String(h.n), { n: 4, dur: 1.6, speed: .6, scale: .55, head: pick(HAPPY) });
    }
  }

  /* ---------- image de chaque instant ---------- */
  function steady(bl) {
    // Image fixe entre deux animations : les caméras la prennent comme fond, elle ne doit pas bouger.
    g2.fillStyle = `rgba(255,244,230,${(playing ? .9 : .55) * bl})`; g2.beginPath(); g2.arc(CX, CY, RB.board * K, 0, TAU); g2.fill();
    ringPath(RB.board, RB.sur); g2.fillStyle = `rgba(255,236,220,${(playing ? .3 : .2) * bl})`; g2.fill();
    g2.save(); g2.globalCompositeOperation = 'lighter'; g2.lineWidth = 12;
    g2.strokeStyle = `rgba(255,122,47,${.6 * bl})`; g2.beginPath(); g2.arc(CX, CY, 355 * K, -2.2, -0.9); g2.stroke();
    g2.strokeStyle = `rgba(255,77,141,${.55 * bl})`; g2.beginPath(); g2.arc(CX, CY, 355 * K, 0.94, 2.24); g2.stroke();
    g2.restore();
  }
  function pattern() {
    // Mire de calibration : anneaux officiels, fils des secteurs, croix aux 4 points de réglage.
    g2.fillStyle = '#000'; g2.fillRect(0, 0, LCW, LCH);
    g2.strokeStyle = '#FFE14D'; g2.lineWidth = 2;
    [RB.bull, RB.obull, RB.tIn, RB.tOut, RB.dIn, RB.dOut, RB.board, RB.sur].forEach(r => { g2.beginPath(); g2.arc(CX, CY, r * K, 0, TAU); g2.stroke(); });
    for (let i = 0; i < 20; i++) { const a = (i * 18 - 9) * Math.PI / 180, [x0, y0] = P2(Math.sin(a) * RB.obull, Math.cos(a) * RB.obull), [x1, y1] = P2(Math.sin(a) * RB.dOut, Math.cos(a) * RB.dOut); g2.beginPath(); g2.moveTo(x0, y0); g2.lineTo(x1, y1); g2.stroke(); }
    g2.strokeStyle = '#FF4D8D'; g2.lineWidth = 3;
    CAL_MM.forEach(([x, y]) => { const [X, Y] = P2(x, y); g2.beginPath(); g2.moveTo(X - 25, Y); g2.lineTo(X + 25, Y); g2.moveTo(X, Y - 25); g2.lineTo(X, Y + 25); g2.stroke(); });
    g2.strokeStyle = 'rgba(255,255,255,.5)'; g2.lineWidth = 1; g2.strokeRect(2, 2, LCW - 4, LCH - 4);
  }
  // Points de réglage, en mm : haut du double 20, 6, 3 et 11 (bord extérieur du fil).
  const CAL_MM = [[0, RB.dOut], [RB.dOut, 0], [0, -RB.dOut], [-RB.dOut, 0]];

  function frame(dt, now, mode) {
    boardLight = 1;
    effects.forEach(e => { e.t += dt; });
    const live = effects.filter(e => e.t >= 0 && e.t < e.dur);
    g2.setTransform(1, 0, 0, 1, 0, 0); g2.globalCompositeOperation = 'source-over'; g2.globalAlpha = 1; g2.filter = 'none';
    if (mode === 'pattern') { pattern(); return; }
    g2.fillStyle = '#000'; g2.fillRect(0, 0, LCW, LCH);
    live.forEach(e => { if (e.base) e.draw(e.t / e.dur, e.t); });
    if (shake > 0) { shake = Math.max(0, shake - dt * 1.1); g2.translate(rnd(-1, 1) * 18 * shake, rnd(-1, 1) * 18 * shake); }
    // Pendant une animation, l'éclairage blanc de la cible baisse fortement : sinon il noie les couleurs.
    const busy = live.some(e => !e.base) || parts.length > 0;
    fxDim += ((busy ? .12 : 1) - fxDim) * Math.min(1, dt * (busy ? 14 : 5));
    boardLight = Math.min(boardLight, fxDim);
    if (boardLight > 0.01) steady(boardLight);
    live.forEach(e => { if (!e.base) { g2.save(); e.draw(e.t / e.dur, e.t); g2.restore(); } });
    effects = effects.filter(e => e.t < e.dur);
    parts = parts.filter(p => { p.life += dt; return p.life < p.max; });
    g2.save(); g2.globalCompositeOperation = 'lighter';
    parts.forEach(p => {
      if (p.life < 0) return;
      p.x += p.vx * dt; p.y += p.vy * dt;
      const k = p.life / p.max, [X, Y] = P2(p.x, p.y);
      if (p.kind === 'fire') { p.vy += 60 * dt; p.vx *= .98; const s = p.size * (1 - k * .6) * K * 1.6, col = k < .25 ? '255,245,170' : k < .55 ? '255,122,47' : '255,77,141';
        const gr = g2.createRadialGradient(X, Y, 0, X, Y, s); gr.addColorStop(0, `rgba(${col},${.85 * (1 - k)})`); gr.addColorStop(1, 'rgba(255,77,141,0)'); g2.fillStyle = gr; g2.beginPath(); g2.arc(X, Y, s, 0, TAU); g2.fill(); }
      else if (p.kind === 'ember') { p.vx += rnd(-80, 80) * dt; g2.fillStyle = `rgba(255,${(180 - 120 * k) | 0},60,${1 - k})`; g2.beginPath(); g2.arc(X, Y, p.size * K, 0, TAU); g2.fill(); }
      else if (p.kind === 'spark') { p.vy -= 220 * dt; p.vx *= .99; g2.fillStyle = p.col; g2.globalAlpha = 1 - k; g2.beginPath(); g2.arc(X, Y, p.size * K, 0, TAU); g2.fill(); g2.globalAlpha = 1; }
      else if (p.kind === 'rain') { g2.strokeStyle = 'rgba(170,200,255,.6)'; g2.lineWidth = 1.5; g2.beginPath(); g2.moveTo(X, Y); g2.lineTo(X + p.vx * .03 * K, Y - p.vy * .03 * K); g2.stroke(); }
      else if (p.kind === 'confetti') { p.vy -= 30 * dt; p.vx += Math.sin(p.life * 5) * 20 * dt; p.rot += p.vr * dt; g2.save(); g2.globalCompositeOperation = 'source-over'; g2.translate(X, Y); g2.rotate(p.rot); g2.fillStyle = p.col; g2.globalAlpha = k > .8 ? (1 - k) / .2 : 1; g2.fillRect(-p.size * K / 2, -p.size * K / 4, p.size * K, p.size * K / 2); g2.restore(); }
    });
    g2.restore();
    g2.setTransform(1, 0, 0, 1, 0, 0);
    clipSurround();
    drawMask();
  }
  // Noir hors du bord extérieur du surround : le mur n'est jamais éclairé (image penchée sinon visible).
  function clipSurround() {
    g2.fillStyle = '#000'; g2.beginPath(); g2.rect(0, 0, LCW, LCH); g2.arc(CX, CY, RB.sur * K, 0, TAU); g2.fill('evenodd');
  }

  // Temps restant avant que l'image redevienne fixe (s), pour mettre les caméras en pause.
  function busyFor() {
    let t = shake > 0 ? shake / 1.1 : 0;
    if (fxDim < .98) t = Math.max(t, .7);  // l'éclairage de la cible remonte encore
    effects.forEach(e => { t = Math.max(t, e.dur - e.t); });
    parts.forEach(p => { t = Math.max(t, p.max - p.life); });
    return t;
  }

  window.FX = {
    MMW, MMH, K, LCW, LCH, CX, CY, CAL_MM, init, frame, dart, busyFor,
    setPlaying(v) { playing = !!v; },
    // Rayons mesurés en calibration (mm). Le fil extérieur du double reste la référence (170).
    setRings(r) {
      if (!r) return;
      const D = { tIn: 99, tOut: 107, dIn: 162, board: 225.5, sur: 380 };
      Object.keys(D).forEach(k => { RB[k] = typeof r[k] === 'number' && r[k] > 20 && r[k] < 600 ? r[k] : D[k]; });
    },
    setProjector(p) { if (p && isFinite(p.x) && isFinite(p.y) && isFinite(p.z)) PROJ = p; },
    // Démonstration complète d'un 180 (fin de tour, pas de fléchette attendue juste après).
    big180() {
      blackout(.5, .1); flash(0, 0, 700); shatter(2.4); shake = 1;
      headAt('p07', { x: 0, y: 0, w: 330, h: 330 }, 1.6, 'pop');
      headCarousel(['p07', 'p03', 'p07', 'p11', 'p07', 'p04', 'p07', 'p08'], 3); sprayTag('180', 0, 0, 200, { dur: 3, rot: -.1 }); ringTag('180', { n: 6, dur: 3, speed: 1.4 });
      confetti(200); [[-420, 250], [420, 250], [-200, 300], [220, 290]].forEach(([x, y], i) => setTimeout(() => fireworks(x, y, [C.fluo, C.crep, C.sunset, C.ciel][i]), 400 + i * 300));
    },
  };
})();
