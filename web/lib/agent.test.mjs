import test from 'node:test';
import assert from 'node:assert/strict';
import { agentAccess, prepareTask, detectTasks, executeTask, trelloExecutionStatus } from './agent.mjs';

const token = 'verified-account-id';
const env = {
  HAI_API_KEY: 'holo-fixture', DEVIN_API_KEY: 'devin-fixture',
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
  await assert.rejects(executeTask({confirmed: true, approval: plan.approval}, 'another-account', env, denied, 11), {status: 409});
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

test('a private Trello task waits for the team browser profile and keeps its approval', async () => {
  const setup = {...env, HAI_COMPUTER_USE_URL: 'https://trello.com/b/fixture/demo'};
  assert.deepEqual(agentAccess(setup), {planning: true, trello: false, devin: true});
  const task = 'Créer « Relire le guide » dans À faire.';
  const plan = await prepareTask({task}, token, setup, holo({status: 'ready', executor: 'computer_use', title: 'Relire le guide', task}));
  const approval = {confirmed: true, approval: plan.approval};
  await assert.rejects(executeTask(approval, token, setup, denied), {status: 503, code: 'trello_setup'});

  const configured = {...setup, HAI_BROWSER_PROFILE_ID: '12b9ade5-309f-4508-b82a-52e124a51600'};
  assert.deepEqual(agentAccess(configured), {planning: true, trello: true, devin: true});
  const result = await executeTask(approval, token, configured, async (url, request) => {
    assert.equal(url, 'https://agp.eu.hcompany.ai/api/v2/sessions');
    assert.equal(JSON.parse(request.body).overrides['agent.environments[kind=web].browser_profile_id'], configured.HAI_BROWSER_PROFILE_ID);
    return Response.json({id: '45463597-20b7-4af7-b3b3-f5fb778203ab'});
  });
  assert.equal(result.status, 'pending');
});

test('a detected Trello task returns a card only after H verifies it on the approved board', async () => {
  const configured = {
    ...env,
    HAI_COMPUTER_USE_URL: 'https://trello.com/b/board123/meetin-os-demo',
    HAI_BROWSER_PROFILE_ID: '12b9ade5-309f-4508-b82a-52e124a51600',
  };
  const transcript = 'Je vais créer la fiche Vérifier le guide dans À faire.';
  const {tasks: [plan]} = await detectTasks({transcript}, token, configured, holo({tasks: [{
    executor: 'computer_use', title: 'Vérifier le guide', task: transcript, quote: transcript,
  }]}), 100);
  const id = '45463597-20b7-4af7-b3b3-f5fb778203ab';
  const run = await executeTask({confirmed: true, approval: plan.approval}, token, configured, async (url, request) => {
    const body = JSON.parse(request.body);
    assert.equal(request.method, 'POST');
    assert.equal(request.headers['Idempotency-Key'], plan.id);
    assert.deepEqual(body.overrides['agent.answer_format'].required, ['verified', 'board_url', 'card_url']);
    assert.match(body.messages, /après avoir rouvert la fiche/);
    return Response.json({id});
  }, 101);
  assert.equal(run.status, 'pending');
  const request = {trackingToken: run.trackingToken};
  const read = (status, latest_answer, outcome = 'success') => async (url, options) => {
    assert.equal(url, `https://agp.eu.hcompany.ai/api/v2/sessions/${id}`);
    assert.equal(options.method, 'GET');
    assert.equal(options.body, undefined);
    return Response.json({id, status: {status, outcome}, latest_answer});
  };
  const answer = {
    verified: true, board_url: 'https://www.trello.com/b/board123/new-slug',
    card_url: 'https://trello.com/c/card1234/1-verifier-le-guide',
  };

  assert.deepEqual(await trelloExecutionStatus(request, token, configured, read('running', answer), 102), {status: 'pending'});
  assert.deepEqual(await trelloExecutionStatus(request, token, configured, read('paused', answer), 102), {status: 'attention'});
  assert.deepEqual(await trelloExecutionStatus(request, token, configured, read('completed', answer), 103), {
    status: 'verified', cardUrl: 'https://trello.com/c/card1234',
  });
  for (const untrusted of [
    {...answer, verified: false},
    {...answer, board_url: 'https://trello.com/b/other123/meetin-os-demo'},
    {...answer, card_url: 'https://trello.com.example/c/card1234'},
    {...answer, card_url: 'https://trello.com/b/card1234'},
  ]) {
    assert.deepEqual(await trelloExecutionStatus(request, token, configured, read('completed', untrusted), 103), {status: 'unverified'});
  }
  assert.deepEqual(await trelloExecutionStatus(request, token, configured, read('completed', answer, 'partial'), 103), {status: 'unverified'});
  assert.deepEqual(await trelloExecutionStatus(request, token, configured, read('failed', answer), 103), {status: 'unverified'});
  await assert.rejects(trelloExecutionStatus(request, 'another-account', configured, denied, 103), {status: 409});
  await assert.rejects(trelloExecutionStatus({trackingToken: plan.approval}, token, configured, denied, 103), {code: 'trello_tracking'});
  await assert.rejects(trelloExecutionStatus(request, token, configured, denied, 101 + 48 * 3600 * 1000), {code: 'trello_tracking'});
  const [payload, signature] = run.trackingToken.split('.');
  const other = {...JSON.parse(Buffer.from(payload, 'base64url')), sessionId: '12345678-1234-1234-1234-123456789abc'};
  const forged = `${Buffer.from(JSON.stringify(other)).toString('base64url')}.${signature}`;
  await assert.rejects(trelloExecutionStatus({trackingToken: forged}, token, configured, denied, 103), {code: 'trello_tracking'});
});

test('task detection proposes reviewable plans without executing anything', async () => {
  const transcript = '[00:10] Micro · Karim corrige l’export des notes avant mardi.\n[00:20] Audio de l’appel · D’accord.';
  await assert.rejects(detectTasks({}, token, env, denied), {status: 400});
  const result = await detectTasks({transcript}, token, env, holo({tasks: [{
    ref: null, executor: 'devin', title: 'Corriger l’export', task: 'Corriger l’export des notes.',
    quote: 'Karim corrige l’export des notes avant mardi.',
  }]}, payload => {
    assert.equal(payload.transcript, transcript);
    assert.deepEqual(payload.known, []);
    assert.equal(payload.destinations.devin, 'Firmirsa/Meetin-OS');
  }));
  assert.equal(result.tasks.length, 1);
  assert.equal(result.tasks[0].replaces, null);
  await assert.rejects(executeTask({approval: result.tasks[0].approval}, token, env, denied), {status: 400});
  let launches = 0;
  await executeTask({confirmed: true, approval: result.tasks[0].approval}, token, env, async () => {
    launches++;
    return Response.json({url: 'https://app.devin.ai/sessions/detected', session_id: 'detected'});
  });
  assert.equal(launches, 1, 'only an explicit confirmation launches a detected task');
});

test('task detection drops invented quotes and unsupported tools, and keeps valid tasks', async () => {
  const transcript = 'Karim corrige l’export. Léa crée la fiche Relire le guide.';
  const good = {ref: null, executor: 'computer_use', title: 'Relire le guide', task: 'Créer la fiche Relire le guide.', quote: 'Léa crée la fiche Relire le guide.'};
  const result = await detectTasks({transcript}, token, env, holo({tasks: [
    {...good, quote: 'Citation inventée'},
    {...good, executor: 'constructor'},
    {...good, executor: 'shell'},
    {...good, title: ''},
    good,
  ]}));
  assert.equal(result.tasks.length, 0, 'only the first 3 entries are read, all invalid');
  const kept = await detectTasks({transcript}, token, env, holo({tasks: [{...good, quote: 'Citation inventée'}, good]}));
  assert.deepEqual(kept.tasks.map(task => task.title), ['Relire le guide']);
  assert.equal(kept.tasks[0].destination, 'https://board.example/test');
  await assert.rejects(detectTasks({transcript}, token, env, async () => Response.json({choices: [{message: {content: 'pas du json'}}]})), {status: 502});
});

test('a corrected commitment updates the known task instead of adding one', async () => {
  const transcript = 'Léa s’en charge… finalement, Karim le fait mardi.';
  const known = [{ref: 'k1', title: 'Envoyer le devis', task: 'Léa envoie le devis à Atlas.'}];
  const update = {executor: 'devin', title: 'Envoyer le devis', task: 'Karim envoie le devis mardi.', quote: 'finalement, Karim le fait mardi.'};
  const result = await detectTasks({transcript, known}, token, env, holo({tasks: [{...update, ref: 'k1'}]}, payload => {
    assert.deepEqual(payload.known, known);
  }));
  assert.equal(result.tasks[0].replaces, 'k1');
  const unknown = await detectTasks({transcript, known}, token, env, holo({tasks: [{...update, ref: 'autre'}]}));
  assert.equal(unknown.tasks[0].replaces, null);
  await assert.rejects(detectTasks({transcript, known: Array(11).fill(known[0])}, token, env, denied), {status: 400});
});

test('task detection skips Holo when no destination is configured', async () => {
  const bare = {HAI_API_KEY: 'holo-fixture'};
  assert.deepEqual(await detectTasks({transcript: 'Karim corrige l’export.'}, token, bare, denied), {tasks: []});
});
