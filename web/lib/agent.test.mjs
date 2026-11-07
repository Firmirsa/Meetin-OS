import test from 'node:test';
import assert from 'node:assert/strict';
import { prepareTask, executeTask } from './agent.mjs';

const token = 'test-only-team-access-token';
const env = {
  MEETIN_DEMO_TOKEN: token, HAI_API_KEY: 'holo-fixture', DEVIN_API_KEY: 'devin-fixture',
  DEVIN_ORG_ID: 'org-1', DEVIN_REPO: 'Firmirsa/Meetin-OS', HAI_COMPUTER_USE_URL: 'https://board.example/test',
};
const denied = () => assert.fail('Execution provider called without a valid confirmation');
const draft = {status: 'ready', executor: 'devin', title: 'Corriger l’export', task: 'Corriger l’export des notes en Markdown.'};
function holo(result, inspect = () => {}) {
  return async (url, request) => {
    assert.equal(url, 'https://api.hcompany.ai/v1/chat/completions');
    inspect(JSON.parse(JSON.parse(request.body).messages[1].content));
    return Response.json({choices: [{message: {content: JSON.stringify(result)}}]});
  };
}

test('an unclear request asks for context and cannot start an execution', async () => {
  await assert.rejects(prepareTask({task: 'Corriger ça'}, 'incorrect', env, denied), {status: 401});
  const result = await prepareTask({task: 'Corriger ça'}, token, env, holo({
    status: 'needs_clarification', question: 'Quel export faut-il corriger ?',
  }));
  assert.deepEqual(result, {status: 'needs_clarification', question: 'Quel export faut-il corriger ?'});
  await assert.rejects(executeTask({confirmed: true, task: 'Corriger ça'}, token, env, denied), {status: 409});
  const clarifications = [{question: result.question, answer: 'L’export des notes en Markdown.'}];
  const plan = await prepareTask({task: 'Corriger ça', clarifications}, token, env, holo(draft, payload => {
    assert.deepEqual(payload.clarifications, clarifications);
  }));
  assert.equal(plan.status, 'ready');
  assert.deepEqual(plan.clarifications, clarifications);
  await assert.rejects(executeTask({approval: plan.approval}, token, env, denied), {status: 400});
});

test('the review rejects invented meeting quotes and expired or changed plans', async () => {
  const transcript = 'Il faut corriger l’export des notes.';
  await assert.rejects(prepareTask({transcript}, token, env, holo({...draft, quote: 'Citation inventée'})), {status: 422});
  const plan = await prepareTask({transcript}, token, env, holo({...draft, quote: transcript}), 10);
  const [payload, signature] = plan.approval.split('.');
  const modified = {...JSON.parse(Buffer.from(payload, 'base64url')), executor: 'computer_use'};
  const forged = `${Buffer.from(JSON.stringify(modified)).toString('base64url')}.${signature}`;
  await assert.rejects(executeTask({confirmed: true, approval: forged}, token, env, denied, 11), {status: 409});
  await assert.rejects(executeTask({confirmed: true, approval: plan.approval}, token, env, denied, plan.expiresAt), {status: 409});
  await assert.rejects(executeTask({confirmed: true, approval: plan.approval}, token, {...env, DEVIN_REPO: 'Other/repo'}, denied, 11), {status: 409});
});

test('a confirmed code task reaches Devin once for concurrent clicks on the same instance', async () => {
  const plan = await prepareTask({task: draft.task}, token, env, holo(draft));
  let launches = 0;
  const create = async (url, request) => {
    launches++;
    assert.equal(url, 'https://api.devin.ai/v3/organizations/org-1/sessions');
    assert.equal(request.headers.authorization, 'Bearer devin-fixture');
    const {prompt} = JSON.parse(request.body);
    assert.match(prompt, /Firmirsa\/Meetin-OS/);
    assert.match(prompt, /Markdown/);
    assert.doesNotMatch(prompt, /Autre dépôt/);
    return Response.json({url: 'https://app.devin.ai/sessions/devin-fixture', session_id: 'devin-fixture'});
  };
  const request = {confirmed: true, approval: plan.approval, task: 'Autre dépôt'};
  const [first, second] = await Promise.all([executeTask(request, token, env, create), executeTask(request, token, env, create)]);
  assert.equal(launches, 1);
  assert.equal(first.executor, 'devin');
  assert.equal(first.status, 'pending');
  assert.deepEqual(first, second);
});

test('a confirmed UI task is sent to H with its approved target and idempotency key', async () => {
  const task = 'Sur le tableau de test, crée la fiche « Relire le guide ».';
  const plan = await prepareTask({task}, token, env, holo({status: 'ready', executor: 'computer_use', title: 'Relire le guide', task}));
  assert.equal(plan.destination, env.HAI_COMPUTER_USE_URL);
  const sessionId = '45463597-20b7-4af7-b3b3-f5fb778203ab';
  const result = await executeTask({confirmed: true, approval: plan.approval}, token, env, async (url, request) => {
    assert.equal(url, 'https://agp.eu.hcompany.ai/api/v2/sessions');
    assert.equal(request.headers['Idempotency-Key'], plan.id);
    const body = JSON.parse(request.body);
    assert.equal(body.agent, 'h/web-surfer-pro');
    assert.equal(body.overrides['agent.environments[kind=web].start_url'], env.HAI_COMPUTER_USE_URL);
    assert.match(body.messages, /Relire le guide/);
    return Response.json({id: sessionId, agent_view_url: 'https://invalid.example/not-the-provider'});
  });
  assert.deepEqual(result, {status: 'pending', executor: 'computer_use', sessionId, url: `https://platform.hcompany.ai/agent-view/${sessionId}`});
});
