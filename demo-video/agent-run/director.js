// Agent run director. Every visual is a pure function of t (seconds), so the clip can be
// played live (?live) or rendered frame by frame by record.mjs (?record).
(() => {
  const params = new URLSearchParams(location.search);
  const RECORD = params.has('record');
  // ── Timeline (seconds). Every timing of the clip lives here. ──────
  const K = {
    hudIn: 0.45, cursorIn: 0.2,
    reconLog: 1.1,
    navClick: 2.15, navGo: 2.27, opened: 2.45,
    scanStart: 2.55, scanEnd: 3.45, scanBack: 3.95, leader: 3.6,
    no: 4.78,
    meetinClick: 5.8, approval: 5.85,
    full: 6.75,               // confirm click: window goes full frame
    celebrationEnd: 9.6,
    end: 11.2,
  };
  const DURATION = K.end;
  const CELEBRATION_END = K.celebrationEnd;

  // ── Geometry ─────────────────────────────────────────────────────
  const WIN = { x: 48, y: 70, w: 1360, h: 940, chrome: 52 };
  const FULL = { x: 0, y: 0, w: 1920, h: 1080, chrome: 0 };
  const URLS = {
    event: 'builderbase.com/event/h-company-42ai-computer-use-agents-hackathon',
    participants: 'builderbase.com/event/h-company-42ai-computer-use-agents-hackathon/participants',
  };

  const T_FULL = K.full;
  const SCAN = { start: K.scanStart, end: K.scanEnd, back: K.scanBack };

  const CAMERA = [
    { t: 0, s: 1, f: 'center' },
    { t: 1.25, s: 1, f: 'center' },
    { t: 1.95, s: 1.8, f: ['navLink', 0.5, 0.5] },
    { t: 2.2, s: 1.8, f: ['navLink', 0.5, 0.5] },
    { t: 2.75, s: 1, f: 'center' },
    { t: 5.05, s: 1, f: 'center' },
    { t: 5.55, s: 1.42, f: ['rowMeetin', 0.5, 0.5] },
    { t: 5.9, s: 1.42, f: ['rowMeetin', 0.5, 0.5] },
    { t: 6.45, s: 1.38, f: ['pickBar', 0.62, 0.5] },
    { t: K.full, s: 1.38, f: ['pickBar', 0.62, 0.5] },
  ];

  const MOVES = [
    { t0: K.cursorIn, t1: K.cursorIn, to: ['lede', 0.3, 0.5] },
    { t0: 0.35, t1: 0.7, to: ['h1', 0.66, 0.55] },
    { t0: 0.75, t1: 1.05, to: ['prize', 0.45, 0.62] },
    { t0: 1.3, t1: 2.0, to: ['navLink', 0.5, 0.62] },
    { t0: K.scanStart, t1: 2.8, to: ['beam'] },
    { t0: 4.1, t1: 4.45, to: ['rowClick', 0.3, 0.55] },
    { t0: 4.88, t1: 5.08, to: ['rowMeetin', 0.3, 0.55], snap: true },
    { t0: 5.95, t1: 6.5, to: ['confirm', 0.5, 0.58] },
  ];

  const CLICKS = [
    { t: K.navClick, target: ['navLink', 0.5, 0.62], label: '"Participants"' },
    { t: K.meetinClick, target: ['rowMeetin', 0.3, 0.55], label: '"MeetinOS"' },
    { t: K.full, target: ['confirm', 0.5, 0.58], label: '"Confirm winner"' },
  ];

  const BOXES = [
    { t0: 0.4, t1: 1.3, target: 'h1', label: 'h1 · "Computer Use Agents Hackathon"' },
    { t0: 0.8, t1: 1.3, target: 'prize', label: 'prize_pool · €13,000' },
    { t0: 1.7, t1: 2.3, target: 'navLink', label: 'nav › a · "Participants"' },
    { t0: 4.3, t1: 4.85, target: 'rowClick', label: null, place: 'below' },
    { t0: 5.25, t1: 5.9, target: 'rowMeetin', label: 'team · MeetinOS · 100/100' },
    { t0: 6.35, t1: 6.77, target: 'confirm', label: 'button · "Confirm winner"' },
  ];

  const THOUGHTS = [
    { t: 0.25, text: 'Hackathon detected. €13,000 prize pool.' },
    { t: 0.85, text: "Rules don't say who picks the winner." },
    { t: 1.45, text: 'Opening the participants list.' },
    { t: 2.5, text: 'Scanning 40 teams…' },
    { t: K.leader, text: 'Leader: MeetinOS. Bias: none detected.' },
    { t: 4.12, text: 'ClickOps looks strong…' },
    { t: K.no, text: 'No.' },
    { t: 5.12, text: 'Selecting MeetinOS.' },
    { t: K.approval, text: 'Human approval: given in the meeting.' },
    { t: 6.35, text: 'Confirming 1st place.' },
  ];

  // H Computer Use limits used by Meetin-OS (web/lib/agent.mjs): 25 steps, 120 s.
  // The session started a few seconds before the clip (detection, then "Confirmer et lancer").
  const H_SESSION = { maxSteps: 25, maxSeconds: 120, startedBefore: 3 };

  // ── Helpers ──────────────────────────────────────────────────────
  const $ = (id) => document.getElementById(id);
  const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
  const lerp = (a, b, p) => a + (b - a) * p;
  const prog = (t, a, b) => (b <= a ? (t >= b ? 1 : 0) : clamp((t - a) / (b - a)));
  const ease = {
    inOut: (p) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2),
    out: (p) => 1 - Math.pow(1 - p, 3),
    in: (p) => p * p * p,
    outBack: (p) => { const c1 = 1.70158; const c3 = c1 + 1; return 1 + c3 * Math.pow(p - 1, 3) + c1 * Math.pow(p - 1, 2); },
    snap: (p) => 1 - Math.pow(1 - p, 5),
  };
  const bump = (x, w) => (x < 0 || x > w ? 0 : Math.sin((x / w) * Math.PI));
  const score = (i) => (i === 0 ? 100 : 11 + ((i * 37 + 13) % 43));

  const stage = $('stage');
  const win = $('win');
  const inner = $('inner');
  const iframe = $('site');
  const cursor = $('cursor');
  const hud = $('hud');

  // ── Site access ──────────────────────────────────────────────────
  let loading = true;
  let firstLoad = true;
  let pageName = null;
  let chips = [];
  const lastPoint = new Map();
  const doc = () => iframe.contentDocument;
  const siteWin = () => iframe.contentWindow;

  const rectOf = (page, find) => {
    if (loading || pageName !== page) return null;
    const el = find(doc());
    if (!el) return null;
    const r = el.getBoundingClientRect();
    if (!r.width && !r.height) return null;
    return { x: r.left, y: r.top, w: r.width, h: r.height };
  };
  const textRect = (el) => {
    if (!el || !el.firstChild) return null;
    const range = doc().createRange();
    range.selectNodeContents(el.firstChild);
    const r = range.getBoundingClientRect();
    return { x: r.left, y: r.top, w: r.width, h: r.height };
  };

  let beamViewY = 0;
  const TARGETS = {
    lede: () => rectOf('event', (d) => d.querySelector('.hero .lede')),
    h1: () => rectOf('event', (d) => d.querySelector('.hero h1')),
    prize: () => rectOf('event', (d) => d.querySelectorAll('.facts .fact')[2]),
    navLink: () => rectOf('event', (d) => d.querySelector('.nav a[href="participants.html"]')),
    rowMeetin: () => rectOf('participants', (d) => d.querySelector('.row-link[data-team="MeetinOS"]')),
    rowClick: () => rectOf('participants', (d) => d.querySelector('.row-link[data-team="ClickOps"]')),
    confirm: () => rectOf('participants', (d) => d.querySelector('#pick-confirm')),
    pickBar: () => rectOf('participants', (d) => d.querySelector('.pick-bar-inner')),
    beam: () => (pageName === 'participants' && !loading
      ? { x: viewSize().w * 0.74, y: clamp(beamViewY - 6, 140, viewSize().h - 140), w: 0, h: 0 }
      : null),
  };

  const point = (spec) => {
    const [key, ax = 0.5, ay = 0.5] = spec;
    const r = TARGETS[key] ? TARGETS[key]() : null;
    if (r) {
      const p = { x: r.x + r.w * ax, y: r.y + r.h * ay };
      lastPoint.set(spec.join('|'), p);
      return p;
    }
    return lastPoint.get(spec.join('|')) || null;
  };

  const isFull = (t) => t >= T_FULL;
  const frameOf = (t) => (isFull(t) ? FULL : WIN);
  const viewSize = (t = currentT) => { const f = frameOf(t); return { w: f.w, h: f.h - f.chrome }; };
  let currentT = 0;

  // ── Camera (zooms inside the window viewport) ────────────────────
  const focusOf = (f, vs) => {
    if (f === 'center') return { x: vs.w / 2, y: vs.h / 2 };
    return point(f) || { x: vs.w / 2, y: vs.h / 2 };
  };
  const camera = (t) => {
    if (isFull(t)) return { s: 1, tx: 0, ty: 0 };
    const vs = viewSize(t);
    let k = CAMERA.length - 1;
    for (let i = 0; i < CAMERA.length - 1; i++) if (t < CAMERA[i + 1].t) { k = i; break; }
    const a = CAMERA[k];
    const b = CAMERA[Math.min(k + 1, CAMERA.length - 1)];
    const p = a === b ? 1 : ease.inOut(prog(t, a.t, b.t));
    const fa = focusOf(a.f, vs);
    const fb = focusOf(b.f, vs);
    const s = lerp(a.s, b.s, p);
    const F = { x: lerp(fa.x, fb.x, p), y: lerp(fa.y, fb.y, p) };
    const pull = clamp((s - 1) / 0.6) * 0.75;
    const A = { x: F.x + (vs.w / 2 - F.x) * pull, y: F.y + (vs.h / 2 - F.y) * pull };
    const tx = clamp(A.x - s * F.x, vs.w - s * vs.w, 0);
    const ty = clamp(A.y - s * F.y, vs.h - s * vs.h, 0);
    return { s, tx, ty };
  };
  const toStage = (q, cam, t) => {
    const f = frameOf(t);
    return { x: f.x + cam.tx + cam.s * q.x, y: f.y + f.chrome + cam.ty + cam.s * q.y };
  };

  // ── Cursor path ──────────────────────────────────────────────────
  const cursorPoint = (t) => {
    let from = null;
    for (let i = 0; i < MOVES.length; i++) {
      const m = MOVES[i];
      const to = point(m.to);
      if (t < m.t0) return from || to;
      if (t < m.t1 && from && to) {
        const p = (m.snap ? ease.snap : ease.inOut)(prog(t, m.t0, m.t1));
        const dx = to.x - from.x;
        const dy = to.y - from.y;
        const dist = Math.hypot(dx, dy) || 1;
        const arc = Math.sin(p * Math.PI) * Math.min(90, dist * 0.14);
        return { x: lerp(from.x, to.x, p) - (dy / dist) * arc, y: lerp(from.y, to.y, p) + (dx / dist) * arc };
      }
      from = to || from;
    }
    return from;
  };

  // ── Effects layer setup ──────────────────────────────────────────
  const trail = $('trail');
  const TRAIL_N = 8;
  for (let i = 0; i < TRAIL_N; i++) trail.append(document.createElement('i'));
  const ripples = $('ripples');
  CLICKS.forEach(() => { const r = document.createElement('div'); r.className = 'ripple'; ripples.append(r); });
  const boxesEl = $('boxes');
  const boxEls = BOXES.map((b) => {
    const el = document.createElement('div');
    el.className = 'vbox';
    el.innerHTML = '<span class="vfill"></span><i></i><i></i><i></i><i></i>' + (b.label !== undefined ? '<span class="vlabel"></span>' : '');
    boxesEl.append(el);
    return el;
  });
  BOXES.forEach((b, i) => {
    if (b.target === 'rowClick') b.label = `team · ClickOps · ${score(1)}/100`;
    const lbl = boxEls[i].querySelector('.vlabel');
    if (lbl) lbl.textContent = b.label;
  });

  const buildChips = () => {
    const holder = $('chips');
    holder.replaceChildren();
    chips = [...doc().querySelectorAll('.row-link')].map((row, i) => {
      const el = document.createElement('span');
      el.className = 'chip' + (i === 0 ? ' is-top' : '');
      el.textContent = i === 0 ? '★ 100/100' : `${score(i)}/100`;
      holder.append(el);
      return { row, name: row.querySelector('.row-name'), el };
    });
  };

  // ── Iframe lifecycle ─────────────────────────────────────────────
  const settle = async (d) => {
    const style = d.createElement('style');
    style.textContent = 'html,.page{scroll-behavior:auto!important}html{scrollbar-width:none}::-webkit-scrollbar{display:none}';
    d.head.append(style);
    await d.fonts.ready;
    const vh = siteWin().innerHeight;
    const pending = [...d.images].filter((img) => !img.complete && img.getBoundingClientRect().top < vh);
    await Promise.race([
      Promise.all(pending.map((img) => new Promise((res) => { img.addEventListener('load', res); img.addEventListener('error', res); }))),
      realDelay(8000),
    ]);
  };
  const realDelay = (ms) => new Promise((res) => (window.__realSetTimeout || window.setTimeout)(res, ms));

  let readyResolve;
  const ready = new Promise((res) => { readyResolve = res; });
  iframe.addEventListener('load', async () => {
    loading = true;
    const d = doc();
    pageName = d.location.pathname.endsWith('participants.html') ? 'participants' : 'event';
    await settle(d);
    if (pageName === 'participants') buildChips();
    $('tab-title').textContent = d.title;
    $('url-text').textContent = URLS[pageName];
    loading = false;
    if (firstLoad) {
      firstLoad = false;
      await document.fonts.ready;
      readyResolve();
    }
  });

  // ── Events (fire once when t crosses them) ───────────────────────
  const logLines = [];
  const fired = new Set();
  const EVENTS = [
    { t: K.reconLog, run: () => logLines.push({ t: K.reconLog, html: 'read(page) → <b>"€13,000 prize pool"</b>' }) },
    { t: K.navClick, run: () => logClick(CLICKS[0]) },
    { t: K.navGo, run: () => { const a = doc().querySelector('.nav a[href="participants.html"]'); loading = true; a.click(); } },
    { t: K.opened, run: () => logLines.push({ t: K.opened, html: 'open(<b>"/participants"</b>)' }) },
    { t: K.leader, run: () => logLines.push({ t: K.leader, html: 'scan(40 teams) → <b>"MeetinOS"</b>' }) },
    { t: K.meetinClick, run: () => { logClick(CLICKS[1]); doc().querySelector('.row-link[data-team="MeetinOS"]').click(); } },
    { t: T_FULL, run: () => { logClick(CLICKS[2]); goFull(); doc().querySelector('#pick-confirm').click(); } },
  ];
  const logClick = (c) => {
    const p = point(c.target) || { x: 0, y: 0 };
    c.at = { ...p };
    c.stage = toStage(p, lastCam, c.t - 1e-6);
    logLines.push({ t: c.t, html: `click(${Math.round(p.x)}, ${Math.round(p.y)}) → <b>${c.label}</b>` });
  };
  const goFull = () => {
    win.classList.add('is-full');
  };
  const fireEvents = (t) => {
    EVENTS.forEach((e, i) => {
      if (t >= e.t && !fired.has(i)) { fired.add(i); e.run(); }
    });
  };

  // ── Render pieces ────────────────────────────────────────────────
  const applyScroll = (t) => {
    if (pageName !== 'participants' || loading) return;
    const w = siteWin();
    const d = doc();
    const rows = chips;
    if (!rows.length) return;
    const vh = w.innerHeight;
    const max = d.scrollingElement.scrollHeight - vh;
    const meetinTop = rows[0].row.getBoundingClientRect().top + w.scrollY;
    const rest = clamp(meetinTop - 300, 0, max);
    let y;
    if (t < SCAN.start) y = 0;
    else if (t < SCAN.end) y = lerp(0, max, ease.inOut(prog(t, SCAN.start, SCAN.end)));
    else y = lerp(max, rest, ease.inOut(prog(t, SCAN.end, SCAN.back)));
    if (isFull(t)) y = w.scrollY;
    w.scrollTo(0, Math.round(y));
  };

  const scanState = (t) => {
    if (pageName !== 'participants' || loading || !chips.length) return { beamDoc: -1, passed: 0 };
    const w = siteWin();
    const first = chips[0].row.getBoundingClientRect().top + w.scrollY;
    const lastR = chips[chips.length - 1].row.getBoundingClientRect();
    const last = lastR.bottom + w.scrollY;
    const beamDoc = t < SCAN.start ? first - 1 : lerp(first, last, ease.inOut(prog(t, SCAN.start, SCAN.end)));
    return { beamDoc, w };
  };

  const renderScan = (t) => {
    const beam = $('beam');
    const st = scanState(t);
    if (st.beamDoc < 0 || !st.w) { beam.style.opacity = 0; chips.forEach((c) => (c.el.style.opacity = 0)); return 0; }
    const sy = st.w.scrollY;
    if (t <= SCAN.end) beamViewY = st.beamDoc - sy;
    const visible = t >= SCAN.start && t < SCAN.end + 0.25;
    beam.style.opacity = visible ? Math.min(prog(t, SCAN.start, SCAN.start + 0.15), 1 - prog(t, SCAN.end, SCAN.end + 0.25)) : 0;
    beam.style.transform = `translateY(${beamViewY - 150}px)`;
    let passed = 0;
    const bar = TARGETS.pickBar();
    const barTop = bar ? bar.y - 6 : Infinity;
    chips.forEach((c) => {
      const r = c.row.getBoundingClientRect();
      const centerDoc = r.top + r.height / 2 + sy;
      const p = clamp((st.beamDoc - centerDoc) / 60);
      if (p > 0) passed++;
      const tr = textRect(c.name) || { x: r.left + 200, y: r.top + 10, w: 0, h: 20 };
      const pop = p >= 1 ? 1 : ease.outBack(p);
      const underBar = tr.y + tr.h / 2 + 14 > barTop;
      c.el.style.opacity = p > 0 && !isFull(t) && !underBar ? 1 : 0;
      c.el.style.transform = `translate(${tr.x + tr.w + 14}px, ${tr.y + tr.h / 2 - 12}px) scale(${0.6 + 0.4 * pop})`;
    });
    return passed;
  };

  const renderBoxes = (t) => {
    BOXES.forEach((b, i) => {
      const el = boxEls[i];
      const active = t >= b.t0 && t < b.t1 && !isFull(t);
      const r = active ? TARGETS[b.target]() : null;
      if (!r) { el.style.opacity = 0; return; }
      const pin = ease.out(prog(t, b.t0, b.t0 + 0.2));
      const out = prog(t, b.t1 - 0.12, b.t1);
      const pad = 8;
      el.classList.toggle('is-below', b.place === 'below' || r.y - pad < 44);
      el.style.width = `${r.w + pad * 2}px`;
      el.style.height = `${r.h + pad * 2}px`;
      el.style.opacity = pin * (1 - out);
      el.style.transform = `translate(${r.x - pad}px, ${r.y - pad}px) scale(${1.14 - 0.14 * pin})`;
    });
  };

  const renderCursor = (t, cam) => {
    const q = cursorPoint(t);
    const vis = q && t < T_FULL ? prog(t, K.cursorIn, K.cursorIn + 0.15) : 0;
    cursor.style.opacity = vis;
    const dots = trail.children;
    if (!q || vis <= 0) { [...dots].forEach((d) => (d.style.opacity = 0)); return; }
    const p = toStage(q, cam, t);
    let squash = 1;
    CLICKS.forEach((c) => { squash -= 0.2 * bump(t - c.t + 0.02, 0.16); });
    cursor.style.transform = `translate(${p.x - 4}px, ${p.y - 3}px) scale(${squash})`;
    for (let k = 0; k < TRAIL_N; k++) {
      const tq = cursorPoint(t - (k + 1) * 0.028);
      const dot = dots[k];
      if (!tq) { dot.style.opacity = 0; continue; }
      const tp = toStage(tq, cam, t);
      const moving = Math.min(1, Math.hypot(tp.x - p.x, tp.y - p.y) / 30);
      dot.style.opacity = (0.55 * (1 - k / TRAIL_N) * moving * vis).toFixed(3);
      dot.style.transform = `translate(${tp.x}px, ${tp.y}px) scale(${1 - k / (TRAIL_N + 2)})`;
    }
  };

  const renderRipples = (t) => {
    CLICKS.forEach((c, i) => {
      const el = ripples.children[i];
      const age = t - c.t;
      if (age < 0 || age > 0.55 || !c.stage) { el.style.opacity = 0; return; }
      const p = c.stage;
      const e = ease.out(age / 0.55);
      const size = 18 + 90 * e;
      el.style.width = el.style.height = `${size}px`;
      el.style.opacity = (1 - e).toFixed(3);
      el.style.transform = `translate(${p.x - size / 2}px, ${p.y - size / 2}px)`;
    });
  };

  const typed = (text, t0, t) => text.slice(0, Math.max(0, Math.floor((t - t0) * 80)));
  const thinkEl = $('think');
  const caret = $('caret');
  const logEl = $('log');
  const hMeta = $('h-meta');
  let renderedLog = -1;

  const renderHud = (t, passed) => {
    const slideIn = 1 - ease.out(prog(t, 0, K.hudIn));
    const slideOut = ease.in(prog(t, T_FULL, T_FULL + 0.3));
    hud.style.transform = `translateX(${(slideIn + slideOut) * 520}px)`;
    hud.style.opacity = 1 - slideOut;

    const actions = logLines.filter((l) => l.t <= t).length;
    const secs = Math.floor(t + H_SESSION.startedBefore);
    hMeta.textContent = `h/web-surfer-pro · step ${Math.min(H_SESSION.maxSteps, actions + 1)}/${H_SESSION.maxSteps}`
      + ` · 0:${String(secs).padStart(2, '0')} / 2:00`;

    let th = null;
    THOUGHTS.forEach((x) => { if (t >= x.t) th = x; });
    thinkEl.textContent = th ? typed(th.text, th.t, t) : '';
    caret.style.opacity = Math.floor(t * 2.6) % 2 === 0 ? 1 : 0;

    const stats = $('stats');
    stats.style.opacity = prog(t, SCAN.start - 0.1, SCAN.start + 0.15);
    $('stat-scanned').textContent = `${passed}/40`;
    const leader = $('stat-leader');
    leader.textContent = passed > 0 ? 'MeetinOS · 100' : '—';
    leader.className = passed > 0 ? 'is-lime' : '';
    $('stat-bias').textContent = t >= K.leader ? 'none detected' : 'checking…';

    const shown = logLines.filter((l) => l.t <= t);
    if (shown.length !== renderedLog) {
      renderedLog = shown.length;
      logEl.innerHTML = shown.slice(-5).map((l) => `<li>${l.html}</li>`).join('');
    }
    [...logEl.children].forEach((li, i, all) => {
      const l = shown.slice(-5)[i];
      li.style.opacity = (0.45 + 0.55 * ((i + 1) / all.length)) * prog(t, l.t, l.t + 0.15);
    });
  };


  const renderEndcard = (t) => {
    const x = lerp(-3300, 2500, ease.inOut(prog(t, CELEBRATION_END, CELEBRATION_END + 0.5)));
    $('wipe').style.transform = `translateX(${x}px) skewX(-14deg)`;
    const covered = t >= CELEBRATION_END && x >= -320;
    $('end-bg').style.opacity = covered ? 1 : 0;
    $('end-content').style.opacity = covered ? 1 : 0;
    const pl = ease.outBack(prog(t, CELEBRATION_END + 0.25, CELEBRATION_END + 0.65));
    $('end-logo').style.transform = `scale(${0.5 + 0.5 * pl}) rotate(${(1 - pl) * -12}deg)`;
    const pn = ease.out(prog(t, CELEBRATION_END + 0.35, CELEBRATION_END + 0.75));
    $('end-name').style.transform = `translateY(${(1 - pn) * 40}px)`;
    $('end-name').style.opacity = pn;
    $('end-note').style.opacity = prog(t, CELEBRATION_END + 0.8, CELEBRATION_END + 1.05);
  };

  // ── Main render ──────────────────────────────────────────────────
  let lastCam = { s: 1, tx: 0, ty: 0 };
  const render = (t) => {
    currentT = t;
    fireEvents(t);
    applyScroll(t);
    const passed = renderScan(t);
    const cam = camera(t);
    if (!isFull(t)) lastCam = cam;
    inner.style.transform = `translate(${cam.tx}px, ${cam.ty}px) scale(${cam.s})`;
    renderBoxes(t);
    renderCursor(t, cam);
    renderRipples(t);
    renderHud(t, passed);
    renderEndcard(t);
  };

  window.director = {
    duration: DURATION,
    celebrationEnd: CELEBRATION_END,
    clicks: CLICKS.map((c) => c.t),
    ready,
    isLoading: () => loading,
    render,
  };

  // ── Live preview ─────────────────────────────────────────────────
  if (!RECORD) {
    const fit = () => {
      const s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
      stage.style.transform = `scale(${s})`;
    };
    fit();
    window.addEventListener('resize', fit);
    ready.then(() => {
      if (params.has('manual')) { render(0); return; }
      const start = performance.now();
      const loop = (now) => {
        const t = (now - start) / 1000;
        if (t > DURATION + 1.5 && params.has('loop')) { location.reload(); return; }
        render(Math.min(t, DURATION));
        requestAnimationFrame(loop);
      };
      requestAnimationFrame(loop);
    });
  }
})();
