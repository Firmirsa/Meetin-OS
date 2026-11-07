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
