import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {
  canValidate, createFixtureAgent, fieldsFromProposal, formatDueDate, formatMs,
  getProposal, nextValidationId, splitExcerpt, toValidation,
} from './contract.mjs';

const ids = (...values) => () => values.shift();

test('la fixture du site reste identique à celle de docs/', async () => {
  const read = async (url) => JSON.parse(await readFile(new URL(url, import.meta.url), 'utf8'));
  assert.deepEqual(await read('./revue-tache.json'), await read('../../docs/fixtures/revue-tache.json'));
});

test('les données de démo de l’app Mac restent alignées sur le site', async () => {
  const swift = await readFile(new URL('../../mac/Review.swift', import.meta.url), 'utf8');
  const {execution} = JSON.parse(await readFile(new URL('./revue-tache.json', import.meta.url), 'utf8'));
  const {meetings} = JSON.parse(await readFile(new URL('./reunions-demo.json', import.meta.url), 'utf8'));
  const values = [execution.verified.taskUrl, execution.needsClarification.message, execution.failed.message];
  for (const p of meetings.find((m) => m.id === 'point-de-lancement').proposals) {
    values.push(p.proposalId, p.title, p.excerpt.text, `startMs: ${p.excerpt.startMs}`, `endMs: ${p.excerpt.endMs}`);
    values.push(p.assignee === null ? 'assignee: nil' : `assignee: "${p.assignee}"`);
    values.push(p.dueDate === null ? 'dueDate: nil' : `dueDate: "${p.dueDate}"`);
  }
  for (const value of values) assert.ok(swift.includes(value), `mac/Review.swift ne contient pas ${value}`);
});

test('les horodatages s’affichent en minutes et secondes', () => {
  assert.equal(formatMs(18000), '00:18');
  assert.equal(formatMs(761000), '12:41');
  assert.equal(formatMs(-5), '00:00');
});

test('la dernière phrase de l’extrait passe au surligneur', () => {
  assert.deepEqual(splitExcerpt(getProposal().excerpt.text), {
    before: 'Léa devait relire le guide. ',
    highlight: 'Finalement, Karim s’en charge mardi.',
  });
  assert.deepEqual(splitExcerpt('Une seule phrase.'), {before: '', highlight: 'Une seule phrase.'});
});

test('l’échéance est une date civile, sans décalage de fuseau', () => {
  assert.equal(formatDueDate('2026-11-10'), 'mardi 10 novembre 2026');
  assert.equal(formatDueDate(null), 'Aucune');
});

test('un responsable inconnu bloque la validation', () => {
  const proposal = {...getProposal(), assignee: null};
  const fields = fieldsFromProposal(proposal);
  assert.equal(fields.assignee, '');
  assert.equal(canValidate(fields), false);
  assert.equal(canValidate({...fields, assignee: 'Karim'}), true);
  assert.equal(canValidate({...fields, assignee: 'Karim', title: '  '}), false);
});

test('la validation n’envoie pas l’extrait et met une échéance vide à null', () => {
  const proposal = getProposal();
  const validation = toValidation(proposal, {title: ' Relire ', assignee: 'Karim ', dueDate: ''}, 'id-1');
  assert.deepEqual(validation, {validationId: 'id-1', proposalId: 'proposal-demo-001', title: 'Relire', assignee: 'Karim', dueDate: null});
  assert.equal('excerpt' in validation, false);
});

test('même contenu → même UUID, contenu modifié → nouvel UUID', () => {
  const proposal = getProposal();
  const fields = fieldsFromProposal(proposal);
  const makeId = ids('id-1', 'id-2');
  const first = toValidation(proposal, fields, nextValidationId(null, proposal, fields, makeId));
  assert.equal(first.validationId, 'id-1');
  assert.equal(nextValidationId(first, proposal, {...fields, title: `${fields.title} `}, makeId), 'id-1');
  assert.equal(nextValidationId(first, proposal, {...fields, dueDate: '2026-11-12'}, makeId), 'id-2');
});

test('une validation rejouée renvoie la même fiche sans doublon', async () => {
  const proposal = getProposal();
  const agent = createFixtureAgent({delayMs: 0});
  const validation = toValidation(proposal, {...fieldsFromProposal(proposal), dueDate: '2026-11-12'}, 'id-1');
  const first = await agent.submit(validation);
  assert.equal(first.execution.status, 'verified');
  assert.equal(first.replayed, false);
  assert.deepEqual(first.execution.observed, {title: 'Relire le guide de lancement', assignee: 'Karim', dueDate: '2026-11-12'});
  const again = await agent.submit(validation);
  assert.equal(again.replayed, true);
  assert.deepEqual(again.execution, first.execution);
});

test('le cas ambigu demande une précision, puis accepte une validation corrigée', async () => {
  const proposal = getProposal();
  const agent = createFixtureAgent({scenario: 'ambigu', delayMs: 0});
  const fields = fieldsFromProposal(proposal);
  const blocked = await agent.submit(toValidation(proposal, fields, 'id-1'));
  assert.equal(blocked.execution.status, 'needs_clarification');
  assert.match(blocked.execution.message, /Deux fiches/);
  const clarified = await agent.submit(toValidation(proposal, {...fields, title: 'Relire le guide de lancement · Atlas'}, 'id-2'));
  assert.equal(clarified.execution.status, 'verified');
});

test('un échec se relance avec le même UUID', async () => {
  const proposal = getProposal();
  const agent = createFixtureAgent({scenario: 'failed', delayMs: 0});
  const validation = toValidation(proposal, fieldsFromProposal(proposal), 'id-1');
  assert.equal((await agent.submit(validation)).execution.status, 'failed');
  const retry = await agent.submit(validation);
  assert.equal(retry.execution.status, 'verified');
  assert.equal(retry.execution.validationId, 'id-1');
});
