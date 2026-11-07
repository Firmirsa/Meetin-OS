import { randomUUID } from 'node:crypto';
import WebSocket from 'ws';
import { ApiError } from './integrations.mjs';
import { bytesPerMillisecond, finishAudio, gladiaKey, quotaExceeded, reserveAudio, upstreamLiveURL } from './gladia-hosted.mjs';

const blockMs = 10_000;
const stopRecording = '{"type":"stop_recording"}';

function openUpstream(url) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url, {handshakeTimeout: 10_000, maxPayload: 256_000});
    socket.once('open', () => resolve(socket));
    socket.once('error', reject);
  });
}

export function relayGladia(client, user, env = process.env, fetcher = fetch, open = openUpstream) {
  let upstream;
  let lease;
  let closed = false;
  let stopCode;
  let queued = 0;
  let chain = Promise.resolve();
  let idle;
  let stopTimer;
  const rotation = setTimeout(() => enqueue(() => stop(1012)), 275_000);
  rotation.unref();

  async function settle() {
    if (!lease) return;
    const previous = lease;
    lease = undefined;
    await finishAudio(user, previous.id, Math.ceil(previous.bytes / bytesPerMillisecond), null, env, fetcher);
  }

  function cleanup() {
    if (closed) return;
    closed = true;
    clearTimeout(idle);
    clearTimeout(rotation);
    clearTimeout(stopTimer);
    if (upstream?.readyState === WebSocket.OPEN) upstream.close();
    void chain.then(settle).catch(() => {});
  }

  function closeClient(code) {
    if (client.readyState === WebSocket.OPEN) client.close(code);
    cleanup();
  }

  function enqueue(action) {
    chain = chain.then(async () => {
      if (!closed) await action();
    }).catch(async error => {
      if (closed) return;
      if (error?.code === 'audio_quota') {
        if (client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify({type: 'meetinos_limit', message: error.message}));
        }
        await stop(1000).catch(() => closeClient(1000));
      } else {
        if (client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify({type: 'meetinos_error', message: error instanceof ApiError ? error.message : 'Le direct a été interrompu.'}));
        }
        closeClient(1011);
      }
    });
  }

  function touch() {
    clearTimeout(idle);
    idle = setTimeout(() => closeClient(1001), 45_000);
    idle.unref();
  }

  async function stop(code) {
    if (stopCode) return;
    stopCode = code;
    await settle();
    if (!upstream || upstream.readyState !== WebSocket.OPEN) {
      closeClient(code);
      return;
    }
    upstream.send(stopRecording);
    stopTimer = setTimeout(() => closeClient(code), 7_000);
    stopTimer.unref();
  }

  async function newLease() {
    const id = randomUUID();
    const result = await reserveAudio(user, id, blockMs, 'live', null, env, fetcher);
    if (result.status === 'quota') throw quotaExceeded();
    if (result.status !== 'reserved') throw new ApiError(503, 'Le quota audio est indisponible.');
    lease = {id, capacity: result.reservedMs * bytesPerMillisecond, bytes: 0};
  }

  async function forward(buffer) {
    if (stopCode) return;
    while (buffer.length && !closed) {
      if (!lease || lease.bytes === lease.capacity) {
        await settle();
        await newLease();
      }
      if (!upstream && !closed) {
        upstream = await open(await upstreamLiveURL(await gladiaKey(env, fetcher), fetcher));
        upstream.on('message', data => {
          if (client.readyState !== WebSocket.OPEN) return;
          const text = data.toString();
          let type;
          try { type = JSON.parse(text).type; } catch { return; }
          if (type === 'transcript') client.send(text);
        });
        upstream.on('error', () => closeClient(1011));
        upstream.on('close', () => closeClient(stopCode ?? 1011));
        if (closed) upstream.close();
      }
      if (closed) return;
      const bytes = Math.min(buffer.length, lease.capacity - lease.bytes);
      const chunk = buffer.subarray(0, bytes);
      lease.bytes += bytes;
      await new Promise((resolve, reject) => upstream.send(chunk, {binary: true}, error => error ? reject(error) : resolve()));
      buffer = buffer.subarray(bytes);
    }
  }

  touch();
  client.on('close', cleanup);
  client.on('error', cleanup);
  client.on('message', (data, isBinary) => {
    const buffer = Buffer.from(data);
    if (!isBinary) {
      if (buffer.toString() === stopRecording) enqueue(() => stop(1000));
      else closeClient(1008);
      return;
    }
    if (!buffer.length || buffer.length % 2 || buffer.length > 64_000 || queued + buffer.length > 1_024_000) {
      closeClient(1009);
      return;
    }
    queued += buffer.length;
    touch();
    enqueue(async () => {
      try { await forward(buffer); } finally { queued -= buffer.length; }
    });
  });
}
