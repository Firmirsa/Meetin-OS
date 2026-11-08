// Renders the agent clip frame by frame with a virtual clock, then encodes two MP4s with a
// click sound on each agent click:
//   out/agent-run-endcard.mp4      (with the Meetin-OS end card)
//   out/agent-run-celebration.mp4  (ends on the celebration)
// Usage: node record.mjs [--draft] [--frames 1.5,3.3,5]
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';
import ffmpegPath from 'ffmpeg-static';
import { writeClickTrack } from './sfx.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '..', '..');
const outDir = path.join(here, 'out');
const args = process.argv.slice(2);
const draft = args.includes('--draft');
const framesArg = args.indexOf('--frames');
const stills = framesArg >= 0 ? args[framesArg + 1].split(',').map(Number) : (draft ? [1, 2.15, 3.2, 4.5, 5.7, 6.6, 8.6, 10.8] : []);

const FPS = draft ? 30 : 60;
const DSF = draft ? 1 : 2;
const PORT = 4301;
const suffix = draft ? '-draft' : '';

const findChrome = () => {
  const candidates = [
    process.env.CHROME_PATH,
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ].filter(Boolean);
  const found = candidates.find((p) => fs.existsSync(p));
  if (!found) throw new Error('Chrome not found. Set CHROME_PATH.');
  return found;
};

const sleep = (ms) => new Promise((res) => setTimeout(res, ms));

const startServer = async () => {
  const server = spawn(process.execPath, [path.join(repoRoot, 'demo-video', 'serve.mjs'), repoRoot, String(PORT)], { stdio: 'ignore' });
  for (let i = 0; i < 50; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${PORT}/demo-video/agent-run/index.html`);
      if (res.ok) return server;
    } catch { /* not up yet */ }
    await sleep(100);
  }
  server.kill();
  throw new Error(`Local server did not start on port ${PORT}`);
};

const encoder = (file, audio, seconds) => {
  const proc = spawn(ffmpegPath, [
    '-y', '-loglevel', 'error',
    '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
    '-i', audio,
    '-map', '0:v', '-map', '1:a',
    '-vf', 'scale=1920:1080:flags=lanczos,format=yuv420p',
    '-c:v', 'libx264', '-preset', draft ? 'veryfast' : 'slow', '-crf', draft ? '22' : '16',
    '-c:a', 'aac', '-b:a', '192k', '-ac', '2',
    '-r', String(FPS), '-t', seconds.toFixed(3), '-shortest', '-movflags', '+faststart', file,
  ], { stdio: ['pipe', 'inherit', 'inherit'] });
  proc.stdin.on('error', (err) => console.error(`[ffmpeg stdin] ${err.message}`));
  const done = new Promise((res, rej) => proc.on('close', (code) => (code === 0 ? res() : rej(new Error(`ffmpeg exited with ${code} for ${file}`)))));
  return { proc, done };
};

const write = (stream, buf) => new Promise((res) => {
  if (stream.write(buf)) res();
  else stream.once('drain', res);
});

// Fails a step that takes too long, so a stuck Chrome turns into a retry instead of a hang.
const within = (ms, promise, what) => Promise.race([
  promise,
  new Promise((_, rej) => setTimeout(() => rej(new Error(`${what} took more than ${ms / 1000}s`)), ms)),
]);

const renderOnce = async (attempt) => {
  const browser = await chromium.launch({
    executablePath: findChrome(),
    headless: true,
    args: ['--hide-scrollbars', '--force-color-profile=srgb', '--autoplay-policy=no-user-gesture-required'],
  });
  const encoders = [];
  try {
    const context = await browser.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: DSF });
    await context.addInitScript({ path: path.join(here, 'time-shim.js') });
    const page = await context.newPage();
    let crashed = null;
    const crash = new Promise((_, rej) => page.on('crash', () => { crashed = new Error('Chrome page crashed'); rej(crashed); }));
    crash.catch(() => {});
    const step = (ms, promise, what) => within(ms, Promise.race([promise, crash]), what);
    page.on('pageerror', (err) => console.error('[page error]', err.message));
    page.on('console', (msg) => { if (msg.type() === 'error') console.error('[console]', msg.text()); });

    await step(30000, page.goto(`http://127.0.0.1:${PORT}/demo-video/agent-run/index.html?record`, { waitUntil: 'load' }), 'Loading the page');
    await step(30000, page.evaluate(() => window.director.ready), 'Waiting for the site');
    const { duration, celebrationEnd, clicks } = await step(10000,
      page.evaluate(() => ({ duration: window.director.duration, celebrationEnd: window.director.celebrationEnd, clicks: window.director.clicks })),
      'Reading the timeline');

    const audio = path.join(outDir, 'clicks.wav');
    const { sample } = writeClickTrack(audio, clicks, duration);
    if (attempt === 1) console.log(`Clicks at ${clicks.map((c) => `${c}s`).join(', ')} (${sample ? 'click.wav' : 'synthesized'})`);

    const total = Math.round(duration * FPS);
    const cutAt = Math.round(celebrationEnd * FPS);
    const full = encoder(path.join(outDir, `agent-run-endcard${suffix}.mp4`), audio, duration);
    const short = encoder(path.join(outDir, `agent-run-celebration${suffix}.mp4`), audio, celebrationEnd);
    encoders.push(full, short);
    const stillFrames = new Set(stills.map((x) => Math.round(x * FPS)));
    const started = Date.now();

    for (let i = 0; i < total; i++) {
      const t = i / FPS;
      await step(15000, page.evaluate((tt) => window.director.render(tt), t), `Frame ${i}`);
      if (await step(5000, page.evaluate(() => window.director.isLoading()), `Frame ${i}`)) {
        for (let w = 0; w < 300 && await step(5000, page.evaluate(() => window.director.isLoading()), 'Navigation'); w++) await sleep(50);
        await step(15000, page.evaluate((tt) => window.director.render(tt), t), `Frame ${i}`);
      }
      for (const frame of page.frames()) {
        await step(15000, frame.evaluate((ms) => window.__vt && window.__vt.advanceTo(ms), t * 1000).catch(() => {}), `Frame ${i}`);
      }
      const shot = await step(30000, page.screenshot({ type: 'jpeg', quality: 94 }), `Frame ${i} capture`);
      await write(full.proc.stdin, shot);
      if (i < cutAt) await write(short.proc.stdin, shot);
      if (i === cutAt - 1) short.proc.stdin.end();
      if (stillFrames.has(i)) fs.writeFileSync(path.join(outDir, `frame-${t.toFixed(2)}s${suffix}.jpg`), shot);
      if (i % FPS === 0) {
        const secs = (Date.now() - started) / 1000;
        process.stdout.write(`${t.toFixed(0).padStart(2)}s / ${duration}s rendered · ${secs.toFixed(0)}s elapsed   `);
      }
    }
    full.proc.stdin.end();
    await within(120000, Promise.all([full.done, short.done]), 'Encoding');
    fs.rmSync(audio, { force: true });
    process.stdout.write(`
Done in ${((Date.now() - started) / 1000).toFixed(0)}s → ${outDir}
`);
  } catch (err) {
    encoders.forEach((e) => e.proc.kill());
    throw err;
  } finally {
    await within(10000, browser.close(), 'Closing Chrome').catch(() => {});
  }
};

const main = async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const server = await startServer();
  try {
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        await renderOnce(attempt);
        return;
      } catch (err) {
        console.error(`
Attempt ${attempt} failed: ${err.message}`);
        if (attempt === 3) throw err;
        console.error('Retrying with a fresh Chrome…');
      }
    }
  } finally {
    server.kill();
  }
};

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
