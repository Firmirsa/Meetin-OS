import test from 'node:test';
import assert from 'node:assert/strict';
import { execute } from './integrations.mjs';

const token = 'test-only-team-access-token';
const env = {
  MEETIN_DEMO_TOKEN: token, LINKUP_API_KEY: 'fixture', DEVIN_API_KEY: 'fixture',
  DEVIN_ORG_ID: 'org-1', DEVIN_REPO: 'Firmirsa/Meetin-OS',
  STRIPE_SECRET_KEY: 'sk_test_fixture', STRIPE_PRICE_ID: 'price_fixture',
  MEETIN_WEB_URL: 'http://localhost:3000',
};
const unexpected = () => assert.fail('Provider called without permission');

test('paid providers fail closed and the direct Devin route is disabled', async () => {
  await assert.rejects(execute('linkup', {}, 'bad', env, unexpected), {status: 401});
  await assert.rejects(execute('devin', {task: 'Fix', confirmed: true}, token, env, unexpected), {status: 404});
  await assert.rejects(execute('checkout', {}, token, {...env, STRIPE_SECRET_KEY: 'sk_live_fixture'}, unexpected), {status: 503});
});

test('Linkup includes sources and rejects unsafe link schemes', async () => {
  const result = await execute('linkup', {query: 'query'}, token, env, async (url, request) => {
    assert.equal(url, 'https://api.linkup.so/v1/search');
    assert.equal(JSON.parse(request.body).outputType, 'sourcedAnswer');
    return Response.json({answer: 'Answer', sources: [{name: 'Source', url: 'https://example.com/'}, {url: 'javascript:alert(1)'}]});
  });
  assert.deepEqual(result, {answer: 'Answer', sources: [{name: 'Source', url: 'https://example.com/'}]});
});

test('Checkout uses a recurring test price and a configured return origin', async () => {
  const result = await execute('checkout', {}, token, env, async (url, request) => {
    assert.equal(url, 'https://api.stripe.com/v1/checkout/sessions');
    assert.equal(request.body.get('mode'), 'subscription');
    assert.equal(request.body.get('line_items[0][price]'), 'price_fixture');
    assert.equal(request.body.get('success_url'), 'http://localhost:3000/onboarding?checkout=returned');
    assert.equal(request.body.get('cancel_url'), 'http://localhost:3000/onboarding?checkout=canceled');
    return Response.json({url: 'https://checkout.stripe.com/c/pay/cs_test_fixture', livemode: false});
  });
  assert.match(result.url, /cs_test/);
});
