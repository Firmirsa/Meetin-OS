import test from 'node:test';
import assert from 'node:assert/strict';
import { execute } from './integrations.mjs';

const token = 'test-only-team-access-token';
const env = {
  MEETIN_DEMO_TOKEN: token, LINKUP_API_KEY: 'fixture', DEVIN_API_KEY: 'fixture',
  DEVIN_ORG_ID: 'org-1', DEVIN_REPO: 'Firmirsa/Meetin-OS',
};
const unexpected = () => assert.fail('Provider called without permission');

test('paid providers fail closed and the direct Devin and legacy Checkout routes are disabled', async () => {
  await assert.rejects(execute('linkup', {}, 'bad', env, unexpected), {status: 401});
  await assert.rejects(execute('devin', {task: 'Fix', confirmed: true}, token, env, unexpected), {status: 404});
  await assert.rejects(execute('checkout', {}, token, env, unexpected), {status: 404});
});

test('Linkup includes sources and rejects unsafe link schemes', async () => {
  const result = await execute('linkup', {query: 'query'}, token, env, async (url, request) => {
    assert.equal(url, 'https://api.linkup.so/v1/search');
    assert.equal(JSON.parse(request.body).outputType, 'sourcedAnswer');
    return Response.json({answer: 'Answer', sources: [{name: 'Source', url: 'https://example.com/'}, {url: 'javascript:alert(1)'}]});
  });
  assert.deepEqual(result, {answer: 'Answer', sources: [{name: 'Source', url: 'https://example.com/'}]});
});

test('agent-research requires Google and sends only the explicit public question to Linkup', async (t) => {
  const { POST } = await import('../app/api/[operation]/route.js');
  const userId = '927135e3-68c8-4c7f-9d37-e80ea311f25a';
  const session = (method) => `fixture.${Buffer.from(JSON.stringify({sub: userId, amr: [{method}]})).toString('base64url')}.fixture`;
  const google = session('oauth');
  const otp = session('otp');
  for (const [key, value] of Object.entries({
    SUPABASE_URL: 'https://auth.example.test', SUPABASE_PUBLISHABLE_KEY: 'public-fixture',
    SUPABASE_SECRET_KEY: 'server-fixture', LINKUP_API_KEY: 'linkup-fixture',
    MEETIN_DEMO_TOKEN: token, HAI_API_KEY: '',
  })) {
    const previous = process.env[key];
    t.after(() => {
      if (previous === undefined) delete process.env[key];
      else process.env[key] = previous;
    });
    process.env[key] = value;
  }
  let linkupCalls = 0;
  let outcome = 'success';
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    if (url === 'https://auth.example.test/auth/v1/user') {
      if (![google, otp].some(value => options.headers.authorization === `Bearer ${value}`)) {
        return new Response(null, {status: 401});
      }
      return Response.json({id: userId, email: 'recette@example.test', email_confirmed_at: '2026-11-07', app_metadata: {providers: ['google']}});
    }
    assert.equal(url, 'https://api.linkup.so/v1/search');
    linkupCalls++;
    assert.equal(options.headers.authorization, 'Bearer linkup-fixture');
    assert.deepEqual(JSON.parse(options.body), {q: 'Question publique ?', depth: 'standard', outputType: 'sourcedAnswer'});
    if (outcome === 'failure') return new Response('private-provider-error', {status: 429});
    if (outcome === 'malformed') return Response.json({answer: []});
    return Response.json({answer: 'Réponse', sources: [
      {name: 'Source', url: 'https://example.test/guide'},
      {url: 'javascript:alert(1)'}, {url: 'http://example.test/'},
      {url: 'https://user:pass@example.test/'}, {url: '/relative'}, null,
    ]});
  });

  const post = (bearer, query = '  Question publique ?  ') => POST(new Request('https://meetin.example.test/api/agent-research', {
    method: 'POST',
    headers: {'content-type': 'application/json', ...(bearer ? {authorization: `Bearer ${bearer}`} : {})},
    body: JSON.stringify({query, transcript: 'private transcript fixture', task: 'unapproved task fixture'}),
  }), {params: Promise.resolve({operation: 'agent-research'})});

  for (const bearer of [null, token, otp]) assert.equal((await post(bearer)).status, 401);
  for (const query of ['', '   ', 'a'.repeat(501)]) assert.equal((await post(google, query)).status, 400);
  assert.equal(linkupCalls, 0);

  const response = await post(google);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await response.json(), {
    answer: 'Réponse', sources: [{name: 'Source', url: 'https://example.test/guide'}],
  });

  for (const mode of ['failure', 'malformed']) {
    outcome = mode;
    const failure = await post(google);
    assert.equal(failure.status, 502);
    assert.match((await failure.json()).error, /^Linkup/);
  }

  delete process.env.LINKUP_API_KEY;
  assert.equal((await post(google)).status, 503);
  assert.equal(linkupCalls, 3);
});
