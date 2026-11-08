import test, {after, before} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {createServer} from 'node:net';
import {fileURLToPath} from 'node:url';
import {LANGS, dict, withLang} from '../../lib/i18n.mjs';

// Rend /telecharger avec `next dev`, ou avec le site indiqué par MEETIN_SITE_TEST_URL.
const web = fileURLToPath(new URL('../../', import.meta.url));
const downloads = new URL('../../public/downloads/', import.meta.url);
let base = process.env.MEETIN_SITE_TEST_URL?.replace(/\/$/, '');
let server;

before(async () => {
  if (base) return;
  const port = await freePort();
  const next = createRequire(import.meta.url).resolve('next/dist/bin/next');
  server = spawn(process.execPath, [next, 'dev', '--port', String(port)], {
    cwd: web, env: {...process.env, NEXT_TELEMETRY_DISABLED: '1'}, stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  server.stdout.on('data', (chunk) => { output += chunk; });
  server.stderr.on('data', (chunk) => { output += chunk; });
  base = `http://127.0.0.1:${port}`;
  await waitFor(`${base}/telecharger`, () => output);
}, {timeout: 120_000});

after(() => server?.kill());

for (const lang of LANGS) {
  test(`/telecharger (${lang}) offre Mac et Windows, Linux bientôt`, {timeout: 60_000}, async () => {
    const d = dict(lang).download;
    const response = await fetch(`${base}${withLang('/telecharger', lang)}`);
    assert.equal(response.status, 200);
    const html = await response.text();

    assert.equal(text(match(html, /<title>([\s\S]*?)<\/title>/)), d.metaTitle);
    assert.match(html, new RegExp(`<div lang="${dict(lang).htmlLang}">`));
    assert.equal(text(match(html, /<h1 id="titre">([\s\S]*?)<\/h1>/)), d.title);

    const mac = card(html, 'mac');
    assert.match(mac.tag, /data-recommended="true"/);
    assert.deepEqual(downloadLinks(mac.body), [{href: '/downloads/Meetin-OS.pkg', label: d.mac.cta}]);
    assert.equal(text(match(mac.body, /<p class="platform__file">([\s\S]*?)<\/p>/)), d.mac.file);

    const windows = card(html, 'windows');
    assert.doesNotMatch(windows.tag, /data-recommended/);
    assert.deepEqual(downloadLinks(windows.body), [{href: `/downloads/${d.windows.file}`, label: d.windows.cta}]);
    assert.equal(text(match(windows.body, /<p class="platform__file">([\s\S]*?)<\/p>/)), d.windows.file);

    const linux = card(html, 'linux');
    assert.match(linux.tag, /data-soon="true"/);
    assert.deepEqual(downloadLinks(linux.body), []);
    assert.equal(text(match(linux.body, /<span class="mt-btn platform__cta" aria-disabled="true">([\s\S]*?)<\/span>/)), d.linux.cta);

    assert.equal(downloadLinks(html).length, 2);
    assert.match(html, new RegExp(`<a href="${escape(withLang('/onboarding', lang))}">${escape(d.nextLink)}</a>`));
    for (const code of LANGS) assert.match(html, new RegExp(`<a href="/telecharger(\\?lang=${code})?" hrefLang="${code}"`));
  });
}

test('les fichiers liés sont servis tels quels et le manifeste Windows correspond', {timeout: 60_000}, async () => {
  const manifest = JSON.parse(await readFile(new URL('Meetin-OS-Windows-0.1.1.json', downloads), 'utf8'));
  const windowsFile = `Meetin-OS-Windows-${manifest.version}.exe`;
  for (const lang of LANGS) {
    assert.equal(dict(lang).download.windows.file, windowsFile);
    assert.ok(dict(lang).download.windows.cta.endsWith(manifest.version));
  }

  for (const file of ['Meetin-OS.pkg', windowsFile, 'Meetin-OS-Windows.exe']) {
    const response = await fetch(`${base}/downloads/${file}`);
    assert.equal(response.status, 200, file);
    const served = Buffer.from(await response.arrayBuffer());
    assert.equal(sha256(served), sha256(await readFile(new URL(file, downloads))), file);
    if (file.endsWith('.exe')) assert.equal(sha256(served), manifest.installerSHA256.toLowerCase(), file);
  }
});

function card(html, os) {
  const [, tag, body] = html.match(new RegExp(`(<li class="platform mt-card" data-os="${os}"[^>]*>)([\\s\\S]*?)</li>`)) ?? [];
  assert.ok(tag, `Carte ${os} absente`);
  return {tag, body};
}

function downloadLinks(html) {
  return [...html.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/g)]
    .filter(([, attrs]) => /\sdownload(=""|\s|$)/.test(attrs))
    .map(([, attrs, inner]) => ({href: attrs.match(/href="([^"]*)"/)?.[1], label: text(inner)}));
}

function match(html, pattern) {
  const found = html.match(pattern);
  assert.ok(found, `Motif absent : ${pattern}`);
  return found[1];
}

function text(html) {
  return html.replace(/<!--[\s\S]*?-->/g, '').replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#x27;/g, "'")
    .replace(/\s+/g, ' ').trim();
}

const escape = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const sha256 = (buffer) => createHash('sha256').update(buffer).digest('hex');

function freePort() {
  return new Promise((resolve, reject) => {
    const probe = createServer().once('error', reject).listen(0, '127.0.0.1', () => {
      const {port} = probe.address();
      probe.close(() => resolve(port));
    });
  });
}

async function waitFor(url, logs) {
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    if (server.exitCode !== null) throw new Error(`next dev s'est arrêté :\n${logs()}`);
    try {
      if ((await fetch(url)).ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`${url} ne répond pas :\n${logs()}`);
}
