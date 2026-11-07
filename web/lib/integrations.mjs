import { timingSafeEqual, createHash } from 'node:crypto';

export class ApiError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function requireAccess(token, env) {
  const secret = env.MEETIN_DEMO_TOKEN;
  if (!secret || secret.length < 24) throw new ApiError(503, 'Accès de démonstration non configuré.');
  const digest = (value) => createHash('sha256').update(value).digest();
  if (typeof token !== 'string' || !timingSafeEqual(digest(token), digest(secret))) {
    throw new ApiError(401, 'Code d’accès incorrect.');
  }
}

export function setting(env, name) {
  const value = env[name]?.trim();
  if (!value) throw new ApiError(503, 'Cette intégration reste à configurer.');
  return value;
}

export function input(value, limit) {
  if (typeof value !== 'string' || !value.trim() || value.length > limit) {
    throw new ApiError(400, 'Vérifie le contenu et sa longueur.');
  }
  return value.trim();
}

export function safeURL(value, host) {
  if (typeof value !== 'string') return null;
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password || (host && url.host !== host)) return null;
    return url.href;
  } catch { return null; }
}

export async function provider(fetcher, url, key, body, label, contentType = 'application/json', headers = {}) {
  const read = body === undefined;
  try {
    const response = await fetcher(url, {
      method: read ? 'GET' : 'POST',
      headers: { ...headers, authorization: `Bearer ${key}`, ...(!read && {'content-type': contentType}) },
      body: contentType === 'application/json' ? JSON.stringify(body) : body,
      signal: AbortSignal.timeout(20_000),
      redirect: 'error',
      cache: 'no-store',
    });
    if (!response.ok) throw new Error();
    return await response.json();
  } catch {
    throw new ApiError(502, `${label} n’a pas confirmé la requête. Vérifie son tableau de bord avant de réessayer.`);
  }
}

export async function execute(operation, body, token, env = process.env, fetcher = fetch) {
  requireAccess(token, env);
  if (!body || typeof body !== 'object') throw new ApiError(400, 'Requête invalide.');

  if (operation === 'linkup') {
    const q = input(body.query, 500);
    const result = await provider(fetcher, 'https://api.linkup.so/v1/search', setting(env, 'LINKUP_API_KEY'),
      { q, depth: 'standard', outputType: 'sourcedAnswer' }, 'Linkup');
    const sources = Array.isArray(result?.sources) ? result.sources.slice(0, 10).flatMap((source) => {
      const url = safeURL(source?.url);
      return url ? [{ name: typeof source.name === 'string' ? source.name : url, url }] : [];
    }) : [];
    if (typeof result?.answer !== 'string') throw new ApiError(502, 'Linkup a renvoyé une réponse inattendue.');
    return { answer: result.answer, sources };
  }

  throw new ApiError(404, 'Action inconnue.');
}
