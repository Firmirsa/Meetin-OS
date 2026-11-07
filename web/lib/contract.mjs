// Adaptateur du contrat front ↔ agent (docs/contrat-front-agent.md).
// Les vues de revue ne parlent qu'à ce module. Pour brancher la vraie route agent,
// remplace createFixtureAgent par un client HTTP qui garde la même signature.
import fixture from './revue-tache.json' with {type: 'json'};

/** @typedef {{text: string, startMs: number, endMs: number}} Extrait */
/** @typedef {{proposalId: string, title: string, assignee: string | null, dueDate: string | null, excerpt: Extrait}} Proposition */
/** @typedef {{validationId: string, proposalId: string, title: string, assignee: string, dueDate: string | null}} Validation */
/**
 * @typedef {{validationId: string, status: 'pending'}
 *   | {validationId: string, status: 'verified', taskUrl: string, observed: {title: string, assignee: string, dueDate: string | null}}
 *   | {validationId: string, status: 'needs_clarification' | 'failed', message: string}} Execution
 */
/** @typedef {{title: string, assignee: string, dueDate: string}} ChampsRevue */

/** Scénarios de démonstration, sélectionnés par `?scenario=`. */
export const SCENARIOS = {
  verified: 'Fiche mise à jour',
  ambigu: 'Fiche ambiguë',
  failed: 'Échec puis relance',
};

/** @returns {Proposition} */
export function getProposal() {
  return structuredClone(fixture.proposal);
}

/** Millisecondes depuis le début de l'audio → « mm:ss ». */
export function formatMs(ms) {
  const total = Math.max(0, Math.floor(ms / 1000));
  const minutes = Math.floor(total / 60);
  const seconds = total % 60;
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

/** Date civile « YYYY-MM-DD » → « mardi 10 novembre 2026 », sans conversion de fuseau. */
export function formatDueDate(dueDate) {
  if (!dueDate) return 'Aucune';
  const [year, month, day] = dueDate.split('-').map(Number);
  return new Intl.DateTimeFormat('fr-FR', {weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC'})
    .format(new Date(Date.UTC(year, month - 1, day)));
}

const LAST_SENTENCE = /^(.*[.!?…]\s+)([^.!?…]+[.!?…]?)$/s;

/** Sépare la dernière phrase de l'extrait, celle qu'on passe au surligneur. */
export function splitExcerpt(text) {
  const match = LAST_SENTENCE.exec(text);
  return match ? {before: match[1], highlight: match[2]} : {before: '', highlight: text};
}

/** « 2026-11-10 » → « mar. 10 nov. », pour les cartes repliées. */
export function formatDueShort(dueDate) {
  if (!dueDate) return 'Sans échéance';
  const [year, month, day] = dueDate.split('-').map(Number);
  return new Intl.DateTimeFormat('fr-FR', {weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC'})
    .format(new Date(Date.UTC(year, month - 1, day)));
}

/** @param {Proposition} proposal @returns {ChampsRevue} */
export function fieldsFromProposal(proposal) {
  return {title: proposal.title, assignee: proposal.assignee ?? '', dueDate: proposal.dueDate ?? ''};
}

/** Le titre et le responsable sont requis. L'échéance peut rester vide. */
export function canValidate(fields) {
  return Boolean(fields.title.trim() && fields.assignee.trim());
}

/**
 * L'extrait n'est jamais renvoyé. Une échéance vide part en `null`.
 * @param {Proposition} proposal @param {ChampsRevue} fields @param {string} validationId
 * @returns {Validation}
 */
export function toValidation(proposal, fields, validationId) {
  return {
    validationId,
    proposalId: proposal.proposalId,
    title: fields.title.trim(),
    assignee: fields.assignee.trim(),
    dueDate: fields.dueDate || null,
  };
}

/**
 * Même contenu que la dernière validation envoyée → même UUID (relance sans doublon).
 * Contenu modifié → nouvel UUID.
 * @param {Validation | null} previous
 */
export function nextValidationId(previous, proposal, fields, makeId = () => crypto.randomUUID()) {
  const draft = toValidation(proposal, fields, '');
  const unchanged = previous
    && previous.proposalId === draft.proposalId
    && previous.title === draft.title
    && previous.assignee === draft.assignee
    && previous.dueDate === draft.dueDate;
  return unchanged ? previous.validationId : makeId();
}

/**
 * Agent simulé à partir de la fixture. Il est idempotent : une validation déjà vérifiée
 * renvoie le même résultat avec `replayed: true`, sans nouvelle fiche.
 * - `verified` : la fiche est mise à jour.
 * - `ambigu` : la première validation demande une précision. Une validation corrigée passe.
 * - `failed` : le premier envoi échoue. La relance avec le même UUID passe.
 */
export function createFixtureAgent({scenario = 'verified', delayMs = 1400} = {}) {
  /** @type {Map<string, Execution>} */
  const results = new Map();
  let firstId = null;
  let attempts = 0;

  /** @param {Validation} validation @returns {Promise<{execution: Execution, replayed: boolean}>} */
  async function submit(validation) {
    if (delayMs) await new Promise((resolve) => setTimeout(resolve, delayMs));
    const {validationId} = validation;
    const known = results.get(validationId);
    if (known?.status === 'verified') return {execution: known, replayed: true};

    attempts += 1;
    firstId ??= validationId;
    /** @type {Execution} */
    let execution;
    const isFixtureProposal = validation.proposalId === fixture.proposal.proposalId;
    if (scenario === 'ambigu' && validationId === firstId) {
      execution = isFixtureProposal
        ? {...fixture.execution.needsClarification, validationId}
        : {validationId, status: 'needs_clarification', message: `Deux fiches correspondent à « ${validation.title} ». Précisez le projet.`};
    } else if (scenario === 'failed' && attempts === 1) {
      execution = {...fixture.execution.failed, validationId};
    } else {
      execution = {
        validationId,
        status: 'verified',
        taskUrl: isFixtureProposal ? fixture.execution.verified.taskUrl : `https://example.com/tasks/${validation.proposalId}`,
        observed: {title: validation.title, assignee: validation.assignee, dueDate: validation.dueDate},
      };
    }
    results.set(validationId, execution);
    return {execution, replayed: false};
  }

  return {submit};
}
