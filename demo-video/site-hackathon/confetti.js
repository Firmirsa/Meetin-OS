// Small canvas confetti engine: cannons, bursts and rain.
(function () {
  const COLORS = ['#1d4fe0', '#f1e6d0', '#ffffff', '#dcc6a2', '#0c1230', '#5ee08a', '#ff5d73', '#ffd23f'];
  const GRAVITY = 0.16;
  const DRAG = 0.965;
  const MAX = 1400;

  class Confetti {
    constructor(canvas) {
      this.canvas = canvas;
      this.ctx = canvas.getContext('2d');
      this.parts = [];
      this.rainUntil = 0;
      this.running = false;
      this.resize = this.resize.bind(this);
      this.tick = this.tick.bind(this);
    }

    resize() {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.w = window.innerWidth;
      this.h = window.innerHeight;
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    add(x, y, angle, speed) {
      if (this.parts.length >= MAX) return;
      const a = (angle * Math.PI) / 180;
      const r = Math.random();
      this.parts.push({
        x, y,
        vx: Math.cos(a) * speed,
        vy: Math.sin(a) * speed,
        w: 7 + Math.random() * 7,
        h: 10 + Math.random() * 10,
        color: COLORS[(Math.random() * COLORS.length) | 0],
        rot: Math.random() * Math.PI * 2,
        spin: (Math.random() - 0.5) * 0.3,
        flip: Math.random() * Math.PI * 2,
        flipSpeed: 0.08 + Math.random() * 0.16,
        shape: r < 0.2 ? 'dot' : r < 0.35 ? 'strip' : 'rect',
        age: 0,
      });
    }

    // Shoots `count` pieces from (x, y) towards `angle` degrees (0 = right, -90 = up).
    cannon(x, y, angle, spread, count, speed) {
      for (let i = 0; i < count; i++) {
        this.add(x, y, angle + (Math.random() - 0.5) * spread, speed * (0.5 + Math.random() * 0.7));
      }
      this.start();
    }

    burst(x, y, count, speed) {
      this.cannon(x, y, -90, 360, count, speed);
    }

    rain(ms) {
      this.rainUntil = performance.now() + ms;
      this.start();
    }

    start() {
      if (this.running) return;
      this.running = true;
      this.resize();
      window.addEventListener('resize', this.resize);
      requestAnimationFrame(this.tick);
    }

    stop() {
      this.running = false;
      this.parts = [];
      this.rainUntil = 0;
      window.removeEventListener('resize', this.resize);
      if (this.w) this.ctx.clearRect(0, 0, this.w, this.h);
    }

    tick(now) {
      if (!this.running) return;
      const { ctx } = this;
      if (now < this.rainUntil) {
        for (let i = 0; i < 5; i++) this.add(Math.random() * this.w, -20, 90 + (Math.random() - 0.5) * 40, 2 + Math.random() * 3);
      }
      ctx.clearRect(0, 0, this.w, this.h);
      this.parts = this.parts.filter((p) => p.y < this.h + 40 && p.age < 1200);
      for (const p of this.parts) {
        p.vy += GRAVITY;
        p.vx *= DRAG;
        p.vy *= DRAG;
        p.x += p.vx + Math.sin(p.flip) * 0.8;
        p.y += p.vy;
        p.rot += p.spin;
        p.flip += p.flipSpeed;
        p.age++;
        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(p.rot);
        ctx.scale(1, Math.cos(p.flip));
        ctx.fillStyle = p.color;
        if (p.shape === 'dot') {
          ctx.beginPath();
          ctx.arc(0, 0, p.w / 2, 0, Math.PI * 2);
          ctx.fill();
        } else if (p.shape === 'strip') {
          ctx.fillRect(-p.w / 4, -p.h, p.w / 2, p.h * 2);
        } else {
          ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
        }
        ctx.restore();
      }
      if (this.parts.length || now < this.rainUntil) {
        requestAnimationFrame(this.tick);
      } else {
        this.running = false;
        window.removeEventListener('resize', this.resize);
      }
    }
  }

  window.Confetti = Confetti;
})();
