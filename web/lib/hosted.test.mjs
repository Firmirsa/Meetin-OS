import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter, once } from 'node:events';
import Stripe from 'stripe';
import { accountAuth, agentEnvironment, requireUser } from './hosted-account.mjs';
import { agentAccess, executeTask, prepareTask } from './agent.mjs';
import { batchResult, startBatch } from './gladia-hosted.mjs';
import { relayGladia } from './gladia-relay.mjs';
import { accountBilling, stripeWebhook } from './hosted-stripe.mjs';

const user = {
  id: '927135e3-68c8-4c7f-9d37-e80ea311f25a', email: 'recette@example.com', email_confirmed_at: '2026-11-07',
  app_metadata: {providers: ['email', 'google']},
};
const fixtureToken = method => `fixture.${Buffer.from(JSON.stringify({sub: user.id, amr: [{method}]})).toString('base64url')}.fixture`;
const googleToken = fixtureToken('oauth');
const audioID = '11111111-1111-4111-8111-111111111111';
const env = {
  MEETIN_WEB_URL: 'https://meetin.example.test', SUPABASE_URL: 'https://db.example.test',
  SUPABASE_PUBLISHABLE_KEY: 'publishable_fixture', SUPABASE_SECRET_KEY: 'secret_fixture', GLADIA_API_KEY: 'gladia_fixture',
};
const audioURL = env.MEETIN_WEB_URL + '/api/gladia';

test('Google PKCE exchanges the code, and legacy OTP cannot open a session', async () => {
  const challenge = 'a'.repeat(43);
  const verifier = 'b'.repeat(43);
  const fetcher = async (url, options) => {
    assert.equal(url, `${env.SUPABASE_URL}/auth/v1/token?grant_type=pkce`);
    assert.deepEqual(JSON.parse(options.body), {auth_code: audioID, code_verifier: verifier});
    return Response.json({access_token: googleToken, refresh_token: 'refresh_fixture', expires_in: 3600, user});
  };
  const {url} = await accountAuth({action: 'google_start', challenge, redirect_to: 'https://example.com'}, null, env, fetcher);
  const target = new URL(url);
  assert.equal(target.searchParams.get('provider'), 'google');
  assert.equal(target.searchParams.get('redirect_to'), 'meetinos-oauth://callback');
  assert.equal(target.searchParams.get('code_challenge'), challenge);
  const tokens = await accountAuth({action: 'google_exchange', code: audioID, verifier}, null, env, fetcher);
  assert.equal(tokens.accessToken, googleToken);
  for (const action of ['send_code', 'verify_code']) {
    await assert.rejects(accountAuth({action, email: user.email}, null, env, fetcher), {status: 400});
  }
  await assert.rejects(requireUser(fixtureToken('otp'), env, async () => Response.json(user)), {status: 401});
  await assert.rejects(requireUser(googleToken, env, async () => Response.json({
    ...user, app_metadata: {providers: ['google', 'github']},
  })), {status: 401});
});

test('the agent accepts verified Google sessions and rejects the old shared code', async () => {
  const configured = {...env, MEETIN_DEMO_TOKEN: 'old-code', HAI_API_KEY: 'holo-fixture'};
  const fetcher = async (url, options) => {
    assert.equal(url, configured.SUPABASE_URL + '/auth/v1/user');
    if (new Headers(options.headers).get('authorization') !== 'Bearer ' + googleToken) {
      return new Response(null, {status: 401});
    }
    return Response.json(user);
  };
  await assert.rejects(agentEnvironment('agent-access', 'old-code', configured, fetcher), {status: 401});
  await assert.rejects(agentEnvironment('agent-access', null, configured, fetcher), {status: 401});
  const access = await agentEnvironment('agent-access', googleToken, configured, fetcher);
  assert.equal(access.userId, user.id);
  assert.equal(access.providerEnv.HAI_API_KEY, 'holo-fixture');
});

test('Google users cannot inherit or execute through a shared Trello browser profile', async () => {
  const oldConfig = {...env, HAI_API_KEY: 'holo-fixture', HAI_COMPUTER_USE_URL: 'https://trello.com/b/fixture', HAI_BROWSER_PROFILE_ID: 'shared-fixture'};
  const other = {...user, id: 'c4c859c9-a0a8-445e-830c-e1cc4bc177ef', email: 'other@example.test'};
  const otherToken = `fixture.${Buffer.from(JSON.stringify({sub: other.id, amr: [{method: 'oauth'}]})).toString('base64url')}.fixture`;
  const auth = async (url, options) => {
    assert.equal(url, oldConfig.SUPABASE_URL + '/auth/v1/user');
    const bearer = new Headers(options.headers).get('authorization');
    return Response.json(bearer === `Bearer ${googleToken}` ? user : other);
  };
  const task = 'Déplacer la fiche Relire le guide.';
  const holo = async () => Response.json({choices: [{message: {content: JSON.stringify({
    status: 'ready', executor: 'computer_use', title: 'Relire le guide', task, target: 'Relire le guide',
  })}}]});
  const denied = () => assert.fail('H was called using a shared browser profile');

  for (const [id, token] of [[user.id, googleToken], [other.id, otherToken]]) {
    const legacy = await prepareTask({task}, id, oldConfig, holo);
    const current = await agentEnvironment('agent-execute', token, oldConfig, auth);
    assert.equal(current.userId, id);
    assert.equal(agentAccess(current.providerEnv).trello, false);
    assert.equal(current.providerEnv.HAI_BROWSER_PROFILE_ID, undefined);
    assert.equal(current.providerEnv.HAI_COMPUTER_USE_URL, undefined);
    await assert.rejects(executeTask({confirmed: true, approval: legacy.approval}, id, current.providerEnv, denied), {status: 503});
    await assert.rejects(agentEnvironment('agent-trello-status', token, oldConfig, auth), {status: 409});
  }

  const nonTrello = {...oldConfig, HAI_COMPUTER_USE_URL: 'https://example.test/board'};
  const otherSite = await agentEnvironment('agent-execute', googleToken, nonTrello, auth);
  assert.equal(otherSite.providerEnv.HAI_COMPUTER_USE_URL, nonTrello.HAI_COMPUTER_USE_URL);
  assert.equal(otherSite.providerEnv.HAI_BROWSER_PROFILE_ID, undefined);
});

test('paid audio requires a confirmed user and budget, and a foreign job is unavailable', async () => {
  let providerCalls = 0;
  const fetcher = async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return Response.json(user);
    if (url.endsWith('/meetin_reserve_audio')) {
      assert.equal(JSON.parse(options.body).p_user, user.id);
      return Response.json({status: 'quota'});
    }
    if (url.endsWith('/meetin_audio_job')) {
      assert.deepEqual(JSON.parse(options.body), {p_user: user.id, p_id: audioID});
      return Response.json(null);
    }
    providerCalls++;
    throw new Error('Unexpected request');
  };
  const post = token => new Request(audioURL, {
    method: 'POST', headers: {
      'content-type': 'application/octet-stream', 'idempotency-key': audioID,
      ...(token ? {authorization: `Bearer ${token}`} : {}),
    }, body: Buffer.alloc(32_000),
  });
  await assert.rejects(startBatch(post(), env, fetcher), {status: 401});
  await assert.rejects(startBatch(post(googleToken), env, fetcher), {status: 429, code: 'audio_quota'});
  await assert.rejects(batchResult(new Request(`${audioURL}?id=${audioID}`, {
    headers: {authorization: `Bearer ${googleToken}`},
  }), env, fetcher), {status: 404});
  assert.equal(providerCalls, 0);
});

test('live relay forwards only the remaining audio and settles actual usage', {timeout: 1_000}, async () => {
  let reservations = 0;
  const settlements = [];
  const fetcher = async (url, options) => {
    if (url.endsWith('/meetin_reserve_audio')) {
      return Response.json(++reservations === 1 ? {status: 'reserved', reservedMs: 1_000} : {status: 'quota'});
    }
    if (url.endsWith('/meetin_finish_audio')) {
      settlements.push(JSON.parse(options.body).p_ms);
      return new Response(null, {status: 204});
    }
    assert.equal(url, 'https://api.gladia.io/v2/live');
    return Response.json({url: 'wss://api.gladia.io/v2/live?token=fixture'});
  };
  class Socket extends EventEmitter {
    readyState = 1;
    sent = [];
    send(data, options, complete) {
      this.sent.push(data);
      if (data === '{"type":"stop_recording"}') queueMicrotask(() => this.close(1000));
      complete?.();
    }
    close(code) { this.readyState = 3; this.emit('close', code); }
  }
  const client = new Socket();
  const upstream = new Socket();
  relayGladia(client, user, env, fetcher, async () => upstream);
  const closed = once(client, 'close');
  client.emit('message', Buffer.alloc(64_000), true);
  await closed;
  assert.equal(upstream.sent.filter(Buffer.isBuffer).reduce((size, chunk) => size + chunk.length, 0), 32_000);
  assert.deepEqual(settlements, [1_000]);
  assert.equal(JSON.parse(client.sent[0]).type, 'meetinos_limit');
});

test('Checkout uses the signed-in identity and only a signed eligible subscription grants Premium', async () => {
  const stripe = new Stripe('sk_test_meetin_fixture');
  const webhookSecret = 'whsec_fixture';
  const calls = [];
  let itemPrice = 'price_unrelated';
  const ends = Math.floor(Date.now() / 1000) + 3600;
  const config = () => ({price: 'price_meetin', live: false, webhookSecret, client: {
    webhooks: stripe.webhooks,
    checkout: {sessions: {create: async body => {
      assert.equal(body.mode, 'subscription');
      assert.equal(body.customer_email, user.email);
      assert.equal(body.subscription_data.metadata.meetin_user_id, user.id);
      assert.equal(body.line_items[0].price, 'price_meetin');
      return {url: 'https://checkout.stripe.com/c/pay/fixture'};
    }}},
    subscriptions: {retrieve: async () => ({
      livemode: false, customer: 'cus_fixture', status: 'active', metadata: {meetin_user_id: user.id},
      items: {data: [{price: {id: itemPrice}, quantity: 1, current_period_end: ends}]},
    })},
  }});
  const fetcher = async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return Response.json(user);
    if (url.endsWith('/meetin_account_quota')) return Response.json({plan: 'free'});
    assert.ok(url.endsWith('/meetin_sync_subscription'));
    calls.push(JSON.parse(options.body));
    return new Response(null, {status: 204});
  };
  await assert.rejects(accountBilling({action: 'checkout'}, null, env, fetcher, config), {status: 401});
  await accountBilling({action: 'checkout', email: 'ignored@example.com'}, googleToken, env, fetcher, config);
  const raw = JSON.stringify({
    type: 'customer.subscription.updated', created: Math.floor(Date.now() / 1000), livemode: false,
    data: {object: {id: 'sub_fixture'}},
  });
  await assert.rejects(stripeWebhook(raw, 'invalid', env, fetcher, config), {status: 400});
  assert.deepEqual(calls, []);
  const signature = stripe.webhooks.generateTestHeaderString({payload: raw, secret: webhookSecret});
  await stripeWebhook(raw, signature, env, fetcher, config);
  assert.equal(calls[0].p_premium_until, null);
  itemPrice = 'price_meetin';
  await stripeWebhook(raw, signature, env, fetcher, config);
  assert.equal(calls[1].p_user, user.id);
  assert.equal(calls[1].p_premium_until, new Date(ends * 1000).toISOString());
});
