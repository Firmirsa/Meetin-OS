import test from 'node:test';
import assert from 'node:assert/strict';
import {allMeetings, formatDuration, formatWhen, getMeeting, groupByDay, transcriptIndexAt} from './meetings.mjs';
import {getProposal} from './contract.mjs';

const CIVIL_DATE = /^\d{4}-\d{2}-\d{2}$/;

test('chaque engagement respecte le type Proposition du contrat', () => {
  for (const meeting of allMeetings()) {
    for (const p of meeting.proposals) {
      assert.equal(typeof p.proposalId, 'string');
      assert.ok(p.title.trim(), `${p.proposalId} sans titre`);
      assert.ok(p.assignee === null || typeof p.assignee === 'string');
      assert.ok(p.dueDate === null || CIVIL_DATE.test(p.dueDate), `${p.proposalId} : échéance ${p.dueDate}`);
      assert.ok(Number.isInteger(p.excerpt.startMs) && p.excerpt.endMs > p.excerpt.startMs);
    }
  }
});

test('l’engagement de Karim reprend la fixture du contrat', () => {
  assert.deepEqual(getMeeting('point-de-lancement').proposals[0], getProposal());
});

test('chaque surlignage des notes renvoie vers un engagement de la réunion', () => {
  for (const meeting of allMeetings()) {
    const ids = new Set(meeting.proposals.map((p) => p.proposalId));
    for (const note of meeting.notes) {
      if (note.highlight) assert.ok(ids.has(note.highlight.proposalId), `${meeting.id} : ${note.highlight.proposalId} inconnu`);
    }
  }
});

test('chaque extrait se retrouve dans la transcription, au même instant', () => {
  for (const meeting of allMeetings()) {
    for (const p of meeting.proposals) {
      const segment = meeting.transcript[transcriptIndexAt(meeting, p.excerpt.startMs)];
      assert.ok(segment, `${p.proposalId} : aucun passage à ${p.excerpt.startMs} ms`);
      assert.equal(segment.startMs, p.excerpt.startMs);
      assert.ok(segment.text.includes(p.excerpt.text), `${p.proposalId} : extrait absent du passage`);
    }
  }
});

test('la transcription est triée par horodatage', () => {
  for (const meeting of allMeetings()) {
    const times = meeting.transcript.map((s) => s.startMs);
    assert.deepEqual(times, times.toSorted((a, b) => a - b));
  }
});

test('les réunions sont groupées par jour, heure de Paris', () => {
  const groups = groupByDay(allMeetings(), new Date('2026-11-07T18:00:00+01:00'));
  assert.deepEqual(groups.map((g) => g.label), ['Aujourd’hui', 'Hier', 'Mercredi 4 novembre']);
  assert.deepEqual(groups[1].meetings.map((m) => m.id), ['retro-sprint-12', 'entretien-atlas']);
});

test('formats de date et de durée', () => {
  assert.equal(formatWhen('2026-11-07T10:30:00+01:00'), 'Sam. 7 nov. · 10:30');
  assert.equal(formatDuration(1920000), '32 min');
  assert.equal(formatDuration(5400000), '1 h 30');
});

test('transcriptIndexAt trouve le passage en cours', () => {
  const meeting = getMeeting('point-de-lancement');
  assert.equal(transcriptIndexAt(meeting, 0), -1);
  assert.equal(transcriptIndexAt(meeting, 20000), 2);
  assert.equal(transcriptIndexAt(meeting, 999999999), meeting.transcript.length - 1);
});
