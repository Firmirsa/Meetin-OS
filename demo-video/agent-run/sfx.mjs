// Builds the clip's audio track: a mouse click at each agent click.
// The click is synthesized (no sample needed). Drop a `click.wav` (16-bit PCM) next to this
// file to use a real recording instead.
import fs from 'node:fs';
import path from 'node:path';

const SR = 48000;

const readSample = (file) => {
  const buf = fs.readFileSync(file);
  let pos = 12;
  let channels = 1;
  let rate = SR;
  let bits = 16;
  while (pos + 8 <= buf.length) {
    const id = buf.toString('ascii', pos, pos + 4);
    const size = buf.readUInt32LE(pos + 4);
    if (id === 'fmt ') {
      channels = buf.readUInt16LE(pos + 10);
      rate = buf.readUInt32LE(pos + 12);
      bits = buf.readUInt16LE(pos + 22);
    } else if (id === 'data') {
      if (bits !== 16) throw new Error('click.wav must be 16-bit PCM');
      const frames = Math.floor(size / (2 * channels));
      const out = new Float32Array(Math.round((frames * SR) / rate));
      for (let i = 0; i < out.length; i++) {
        const src = Math.min(frames - 1, Math.floor((i * rate) / SR));
        let v = 0;
        for (let c = 0; c < channels; c++) v += buf.readInt16LE(pos + 8 + (src * channels + c) * 2) / 32768;
        out[i] = v / channels;
      }
      return out;
    }
    pos += 8 + size + (size % 2);
  }
  throw new Error('click.wav has no data chunk');
};

// One click = a press and a softer release ~70 ms later. Each transient mixes a crisp
// high-passed noise burst, a short high "tick" and a small low thump for body.
const synthClick = (strength) => {
  const out = new Float32Array(Math.round(0.16 * SR));
  let seed = 12345;
  const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return (seed / 4294967296) * 2 - 1; };
  const transient = (offset, gain, tone) => {
    let hp = 0;
    let prev = 0;
    for (let i = 0; i < Math.round(0.06 * SR); i++) {
      const idx = offset + i;
      if (idx >= out.length) break;
      const t = i / SR;
      const white = rnd();
      hp = 0.82 * (hp + white - prev);
      prev = white;
      const noise = hp * Math.exp(-t / 0.0014) * 0.95;
      const tick = Math.sin(2 * Math.PI * tone * t) * Math.exp(-t / 0.0045) * 0.5;
      const body = Math.sin(2 * Math.PI * 185 * t) * Math.exp(-t / 0.014) * 0.38;
      out[idx] += gain * (noise + tick + body);
    }
  };
  transient(0, strength, 2900);
  transient(Math.round(0.072 * SR), strength * 0.5, 3500);
  return out;
};

// times: seconds of each click; the last one (the confirm) is a bit stronger.
export const writeClickTrack = (file, times, duration, sampleFile = path.join(path.dirname(file), '..', 'click.wav')) => {
  const total = Math.ceil(duration * SR);
  const mix = new Float32Array(total);
  const sample = fs.existsSync(sampleFile) ? readSample(sampleFile) : null;
  times.forEach((time, i) => {
    const strong = i === times.length - 1;
    const click = sample || synthClick(strong ? 1 : 0.85);
    const gain = sample ? (strong ? 1 : 0.85) : 1;
    const start = Math.max(0, Math.round((time - 0.008) * SR));
    for (let j = 0; j < click.length && start + j < total; j++) mix[start + j] += click[j] * gain;
  });

  let peak = 0;
  for (const v of mix) peak = Math.max(peak, Math.abs(v));
  const norm = peak ? 0.89 / peak : 1; // about -1 dBFS

  const out = Buffer.alloc(44 + total * 2);
  out.write('RIFF', 0, 'ascii');
  out.writeUInt32LE(36 + total * 2, 4);
  out.write('WAVE', 8, 'ascii');
  out.write('fmt ', 12, 'ascii');
  out.writeUInt32LE(16, 16);
  out.writeUInt16LE(1, 20);
  out.writeUInt16LE(1, 22);
  out.writeUInt32LE(SR, 24);
  out.writeUInt32LE(SR * 2, 28);
  out.writeUInt16LE(2, 32);
  out.writeUInt16LE(16, 34);
  out.write('data', 36, 'ascii');
  out.writeUInt32LE(total * 2, 40);
  for (let i = 0; i < total; i++) {
    const v = Math.max(-1, Math.min(1, mix[i] * norm));
    out.writeInt16LE(Math.round(v * 32767), 44 + i * 2);
  }
  fs.writeFileSync(file, out);
  return { sample: Boolean(sample) };
};
