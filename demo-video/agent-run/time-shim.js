// Virtual clock for frame-by-frame recording. Injected by record.mjs into every frame
// before page scripts run. Time only moves when the recorder calls __vt.advanceTo(ms).
(() => {
  if (window.__vt) return;

  let now = 0;
  let seq = 0;
  const epoch = Date.now();
  const timers = new Map(); // id -> { at, fn, args, every }
  let rafs = [];            // [{ id, fn }]
  const seen = new WeakMap(); // Animation -> virtual start time

  window.__realSetTimeout = window.setTimeout.bind(window);
  performance.now = () => now;
  Date.now = () => epoch + now;

  window.setTimeout = (fn, ms = 0, ...args) => {
    const id = ++seq;
    timers.set(id, { at: now + Math.max(0, Number(ms) || 0), fn, args, every: 0 });
    return id;
  };
  window.setInterval = (fn, ms = 0, ...args) => {
    const id = ++seq;
    const every = Math.max(1, Number(ms) || 0);
    timers.set(id, { at: now + every, fn, args, every });
    return id;
  };
  window.clearTimeout = window.clearInterval = (id) => { timers.delete(id); };
  window.requestAnimationFrame = (fn) => {
    const id = ++seq;
    rafs.push({ id, fn });
    return id;
  };
  window.cancelAnimationFrame = (id) => { rafs = rafs.filter((r) => r.id !== id); };

  const run = (fn, args) => {
    try {
      if (typeof fn === 'function') fn(...args);
    } catch (err) {
      console.error(err);
    }
  };

  // CSS animations and transitions follow the virtual clock too.
  const syncAnimations = () => {
    for (const anim of document.getAnimations()) {
      let start = seen.get(anim);
      if (start === undefined) {
        start = now;
        seen.set(anim, start);
        try { anim.pause(); } catch { /* ignore */ }
      }
      try { anim.currentTime = now - start; } catch { /* ignore */ }
    }
  };

  window.__vt = {
    get now() { return now; },
    advanceTo(target) {
      if (target < now) target = now;
      for (;;) {
        let nextId = null;
        let next = null;
        for (const [id, t] of timers) {
          if (t.at <= target && (!next || t.at < next.at || (t.at === next.at && id < nextId))) {
            nextId = id;
            next = t;
          }
        }
        if (!next) break;
        now = Math.max(now, next.at);
        if (next.every) next.at += next.every;
        else timers.delete(nextId);
        run(next.fn, next.args);
      }
      now = target;
      const batch = rafs;
      rafs = [];
      for (const r of batch) run(r.fn, [now]);
      syncAnimations();
    },
  };
})();
