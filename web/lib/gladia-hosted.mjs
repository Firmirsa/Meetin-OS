import { createHash } from 'node:crypto';
import { ApiError, safeURL } from './integrations.mjs';
import { bearer, providerKey, requireUser, rpc, uuid } from './hosted-account.mjs';
import { boundedBody } from './hosted-response.mjs';

const gladiaURL = 'https://api.gladia.io';
export const bytesPerMillisecond = 32; // PCM 16 kHz mono, signed 16-bit little endian
export const batchBytes = 90_000 * bytesPerMillisecond;
const language_config = {languages: ['fr', 'en'], code_switching: true};
// Names Gladia otherwise mishears in meetings ("Lenny" → "L'ENIA", "H Company" → "H compagnie").
export const custom_vocabulary_config = {
  default_intensity: 0.5,
  vocabulary: [
    {value: 'Lenny', intensity: 0.7, pronunciations: ['Leni', 'Léni', 'Lény', 'Leny', 'Lenni', 'Lennie', "L'ENIA", "L'Enia"]},
    {value: 'Wael', pronunciations: ['Waël', 'Wail', 'Waelle']},
    'Samy',
    {value: 'H Company', pronunciations: ['H compagnie', 'Ash Company', 'Hache company', 'H-Company']},
    {value: 'Holo', pronunciations: ['Hollow', 'Olo']},
    'Devin', 'YouTube', 'Trello', 'Gladia', 'Linkup',
    {value: 'Meetin-OS', pronunciations: ['Meeting OS', 'Mitin OS']},
  ],
};

export async function gladiaKey(env, fetcher) {
  const key = await providerKey('gladia', env, fetcher);
  if (!key) throw new ApiError(503, 'La transcription reste à configurer côté serveur.');
  return key;
}

async function gladia(path, key, body, fetcher) {
  const headers = {'x-gladia-key': key};
  if (typeof body === 'string') headers['content-type'] = 'application/json';
  try {
    return await fetcher(gladiaURL + path, {
      method: body === undefined ? 'GET' : 'POST', headers, body,
      signal: AbortSignal.timeout(25_000), redirect: 'error', cache: 'no-store',
    });
  } catch {
    throw new ApiError(502, 'Gladia n’a pas répondu à temps.');
  }
}

function wav(pcm) {
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write('WAVEfmt ', 8);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(16_000, 24);
  header.writeUInt32LE(32_000, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write('data', 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

export function reserveAudio(user, id, ms, kind, fingerprint, env, fetcher) {
  return rpc('meetin_reserve_audio', {p_user: user.id, p_id: id, p_ms: ms, p_kind: kind, p_fingerprint: fingerprint}, env, fetcher);
}

export function finishAudio(user, id, ms, job, env, fetcher) {
  return rpc('meetin_finish_audio', {p_user: user.id, p_id: id, p_ms: ms, p_job: job}, env, fetcher);
}

export function quotaExceeded() {
  return new ApiError(429, 'Votre quota audio est insuffisant. Consultez votre plan dans Compte.', 'audio_quota');
}

export async function startBatch(request, env = process.env, fetcher = fetch) {
  const user = await requireUser(bearer(request.headers), env, fetcher);
  const id = request.headers.get('idempotency-key');
  if (!uuid.test(id ?? '') || request.headers.get('content-type') !== 'application/octet-stream') {
    throw new ApiError(400, 'Envoi audio invalide.');
  }
  const pcm = await boundedBody(request, batchBytes);
  if (!pcm.length || pcm.length % 2) throw new ApiError(400, 'Audio PCM invalide.');
  const ms = Math.ceil(pcm.length / bytesPerMillisecond);
  const key = await gladiaKey(env, fetcher);
  const fingerprint = createHash('sha256').update(pcm).digest('hex');
  const reservation = await reserveAudio(user, id, ms, 'batch', fingerprint, env, fetcher);
  if (reservation.status === 'quota') throw quotaExceeded();
  if (reservation.status === 'conflict') throw new ApiError(409, 'Cet identifiant audio a déjà été utilisé.');
  if (reservation.status === 'existing') return {id};
  if (reservation.status !== 'reserved') throw new ApiError(503, 'Le quota audio est indisponible.');

  let charged = 0;
  let job = null;
  try {
    const upload = new FormData();
    upload.append('audio', new Blob([wav(pcm)], {type: 'audio/wav'}), 'extrait.wav');
    const uploaded = await gladia('/v2/upload', key, upload, fetcher);
    const audio = uploaded.ok && safeURL((await uploaded.json())?.audio_url);
    if (!audio) throw new ApiError(502, 'Gladia a refusé l’audio.');

    // After dispatch, an unknown outcome keeps the reservation charged.
    charged = ms;
    const started = await gladia('/v2/pre-recorded', key, JSON.stringify({audio_url: audio, diarization: true, language_config, custom_vocabulary: true, custom_vocabulary_config}), fetcher);
    if (!started.ok) {
      if (started.status < 500) charged = 0;
      throw new ApiError(502, 'Gladia n’a pas démarré la transcription.');
    }
    const result = await started.json();
    if (!uuid.test(result?.id ?? '')) throw new ApiError(502, 'Gladia n’a pas confirmé la transcription.');
    job = result.id;
  } finally {
    await finishAudio(user, id, charged, job, env, fetcher);
  }
  return {id};
}

export async function batchResult(request, env = process.env, fetcher = fetch) {
  const user = await requireUser(bearer(request.headers), env, fetcher);
  const id = new URL(request.url).searchParams.get('id');
  if (!uuid.test(id ?? '')) throw new ApiError(400, 'Identifiant audio invalide.');
  const record = await rpc('meetin_audio_job', {p_user: user.id, p_id: id}, env, fetcher);
  if (!record) throw new ApiError(404, 'Transcription introuvable.');
  if (!uuid.test(record.job ?? '')) return {status: record.starting ? 'pending' : 'failed'};
  const key = await gladiaKey(env, fetcher);
  const response = await gladia('/v2/pre-recorded/' + record.job, key, undefined, fetcher);
  if (!response.ok) throw new ApiError(502, 'Le résultat Gladia est indisponible.');
  const result = await response.json();
  if (['error', 'failed'].includes(result.status)) return {status: 'failed'};
  if (result.status !== 'done') return {status: 'pending'};
  const transcription = result.result?.transcription;
  if (!transcription) return {status: 'failed'};
  const utterances = Array.isArray(transcription.utterances) ? transcription.utterances : [];
  const segments = utterances.filter(segment => typeof segment?.text === 'string' && Number.isFinite(segment.start))
    .map(({start, speaker, text}) => ({start, speaker: Number.isInteger(speaker) ? speaker : null, text}));
  if (!segments.length && transcription.full_transcript?.trim()) {
    segments.push({start: 0, speaker: null, text: transcription.full_transcript.trim()});
  }
  return {status: 'done', segments};
}

export async function upstreamLiveURL(key, fetcher) {
  const response = await gladia('/v2/live', key, JSON.stringify({
    encoding: 'wav/pcm', sample_rate: 16_000, bit_depth: 16, channels: 1, language_config,
    messages_config: {receive_partial_transcripts: true, receive_final_transcripts: true},
    realtime_processing: {custom_vocabulary: true, custom_vocabulary_config},
  }), fetcher);
  if (!response.ok) throw new ApiError(502, 'Le direct Gladia est indisponible.');
  const created = await response.json();
  let url;
  try { url = new URL(created.url); } catch { throw new ApiError(502, 'Le direct Gladia est indisponible.'); }
  if (url.protocol !== 'wss:' || url.host !== 'api.gladia.io' || url.username || url.password || url.pathname !== '/v2/live') {
    throw new ApiError(502, 'Le direct Gladia est indisponible.');
  }
  return url;
}
