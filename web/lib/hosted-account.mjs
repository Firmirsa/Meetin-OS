import { ApiError, setting } from './integrations.mjs';

export const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const serverMessage = 'Le service de comptes Meetin-OS est indisponible.';
const googleRequired = 'Connectez-vous avec Google pour utiliser Meetin-OS.';
const googleRedirect = 'meetinos-oauth://callback';
const pkceValue = /^[A-Za-z0-9_-]{43}$/;

function isGoogleSession(user, token) {
  const providers = user?.app_metadata?.providers;
  if (!uuid.test(user?.id ?? '') || user.is_anonymous || !user.email || !user.email_confirmed_at ||
      !Array.isArray(providers) || !providers.includes('google') ||
      !providers.every(provider => provider === 'google' || provider === 'email')) return false;
  // The JWT was just issued or verified by Supabase. A linked Google identity alone does not prove OAuth sign-in.
  try {
    const claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
    return claims.sub === user.id && Array.isArray(claims.amr) && claims.amr.some(entry => entry?.method === 'oauth');
  } catch { return false; }
}

function supabaseOrigin(env) {
  let origin;
  try { origin = new URL(env.SUPABASE_URL); } catch { throw new ApiError(503, serverMessage); }
  const local = origin.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(origin.hostname);
  if ((!local && origin.protocol !== 'https:') || origin.username || origin.password ||
      origin.pathname !== '/' || origin.search || origin.hash) throw new ApiError(503, serverMessage);
  return origin.origin;
}

async function supabase(path, {key, bearer, body, method}, env, fetcher) {
  const url = supabaseOrigin(env) + path;
  const headers = {apikey: key};
  if (bearer) headers.authorization = `Bearer ${bearer}`;
  if (body !== undefined) headers['content-type'] = 'application/json';
  try {
    return await fetcher(url, {
      method: method ?? (body === undefined ? 'GET' : 'POST'),
      headers, body: JSON.stringify(body), signal: AbortSignal.timeout(12_000),
      redirect: 'error', cache: 'no-store',
    });
  } catch {
    throw new ApiError(503, serverMessage);
  }
}

export async function rpc(name, args, env = process.env, fetcher = fetch) {
  const key = setting(env, 'SUPABASE_SECRET_KEY');
  const response = await supabase(`/rest/v1/rpc/${name}`, {
    key, bearer: key.startsWith('eyJ') ? key : undefined, body: args,
  }, env, fetcher);
  if (!response.ok) throw new ApiError(503, 'La base Meetin-OS est indisponible ou attend sa migration.');
  return response.status === 204 ? null : response.json();
}

export function bearer(headers) {
  const value = headers.get('authorization');
  return value?.startsWith('Bearer ') ? value.slice(7) : undefined;
}

export async function requireUser(token, env = process.env, fetcher = fetch) {
  if (typeof token !== 'string' || !token || token.length > 8192) {
    throw new ApiError(401, 'Connectez-vous à Meetin-OS pour transcrire.', 'account_required');
  }
  const response = await supabase('/auth/v1/user', {
    key: setting(env, 'SUPABASE_PUBLISHABLE_KEY'), bearer: token,
  }, env, fetcher);
  if (response.status === 401 || response.status === 403) {
    throw new ApiError(401, 'Reconnectez-vous à Meetin-OS.', 'account_required');
  }
  if (!response.ok) throw new ApiError(503, serverMessage);
  const user = await response.json();
  if (!isGoogleSession(user, token)) {
    throw new ApiError(401, googleRequired, 'account_required');
  }
  return user;
}

export async function accountAuth(body, token, env = process.env, fetcher = fetch) {
  const action = body?.action;
  if (action === 'google_start') {
    if (typeof body.challenge !== 'string' || !pkceValue.test(body.challenge)) {
      throw new ApiError(400, 'La demande de connexion Google est invalide.');
    }
    const url = new URL('/auth/v1/authorize', supabaseOrigin(env));
    url.search = new URLSearchParams({
      provider: 'google', redirect_to: googleRedirect, code_challenge: body.challenge,
      code_challenge_method: 's256', prompt: 'select_account',
    });
    return {url: url.href};
  }
  if (!['google_exchange', 'refresh', 'sign_out'].includes(action)) {
    throw new ApiError(400, googleRequired);
  }
  const key = setting(env, 'SUPABASE_PUBLISHABLE_KEY');
  let response;
  if (action === 'google_exchange') {
    if (typeof body.code !== 'string' || !uuid.test(body.code) ||
        typeof body.verifier !== 'string' || !pkceValue.test(body.verifier)) {
      throw new ApiError(400, 'Le retour de la connexion Google est invalide.');
    }
    response = await supabase('/auth/v1/token?grant_type=pkce', {
      key, body: {auth_code: body.code, code_verifier: body.verifier},
    }, env, fetcher);
  } else if (action === 'refresh') {
    if (typeof body.refreshToken !== 'string' || !body.refreshToken || body.refreshToken.length > 512) {
      throw new ApiError(401, 'Reconnectez-vous à Meetin-OS.', 'account_required');
    }
    response = await supabase('/auth/v1/token?grant_type=refresh_token', {
      key, body: {refresh_token: body.refreshToken},
    }, env, fetcher);
  } else if (action === 'sign_out') {
    if (!token) return {signedOut: true};
    response = await supabase('/auth/v1/logout?scope=local', {key, bearer: token, method: 'POST'}, env, fetcher);
    if (response.status === 401 || response.status === 403) return {signedOut: true};
  }
  if (response.status === 429) throw new ApiError(429, 'Patientez avant de réessayer de vous connecter.');
  if (!response.ok) {
    if (response.status >= 500) throw new ApiError(503, serverMessage);
    if (action === 'refresh') throw new ApiError(401, 'Reconnectez-vous à Meetin-OS.', 'account_required');
    if (action === 'google_exchange') throw new ApiError(400, 'La connexion Google a expiré ou a échoué. Réessayez.');
    throw new ApiError(503, 'La déconnexion est momentanément indisponible.');
  }
  if (action === 'sign_out') return {signedOut: true};
  const session = await response.json();
  if (!session?.access_token || !session.refresh_token || !session.user?.email ||
      !Number.isFinite(session.expires_in) || session.expires_in <= 0) throw new ApiError(503, serverMessage);
  if (!isGoogleSession(session.user, session.access_token)) throw new ApiError(401, googleRequired, 'account_required');
  return {
    accessToken: session.access_token, refreshToken: session.refresh_token,
    expiresAt: Math.floor(Date.now() / 1000) + session.expires_in, email: session.user.email,
  };
}

export async function providerKey(provider, env = process.env, fetcher = fetch) {
  const variable = {gladia: 'GLADIA_API_KEY', hcompany: 'HAI_API_KEY', devin: 'DEVIN_API_KEY'}[provider];
  if (!variable) throw new ApiError(503, 'Intégration indisponible.');
  const configured = env[variable]?.trim();
  if (configured) return configured;
  if (!env.SUPABASE_URL || !env.SUPABASE_SECRET_KEY) return null;
  const value = await rpc('meetin_provider_secret', {p_provider: provider}, env, fetcher);
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

export async function agentEnvironment(operation, token, env = process.env, fetcher = fetch) {
  const user = await requireUser(token, env, fetcher);
  const needsDevin = env.DEVIN_ORG_ID && ['agent-access', 'agent-execute'].includes(operation);
  const [hai, devin] = await Promise.all([
    providerKey('hcompany', env, fetcher),
    needsDevin ? providerKey('devin', env, fetcher) : null,
  ]);
  return { userId: user.id, providerEnv: {...env, HAI_API_KEY: hai ?? undefined, DEVIN_API_KEY: devin ?? env.DEVIN_API_KEY} };
}

export function accountQuota(user, env = process.env, fetcher = fetch) {
  return rpc('meetin_account_quota', {p_user: user.id}, env, fetcher);
}

export async function accountStatus(token, env = process.env, fetcher = fetch) {
  const user = await requireUser(token, env, fetcher);
  const {customerId, ...quota} = await accountQuota(user, env, fetcher);
  return {
    ...quota, email: user.email, liveUrl: env.MEETIN_GLADIA_LIVE_URL?.trim() || null,
    checkoutAvailable: Boolean(env.STRIPE_SECRET_KEY && env.STRIPE_PRICE_ID && env.STRIPE_WEBHOOK_SECRET),
    canManageBilling: Boolean(customerId && env.STRIPE_SECRET_KEY),
  };
}
