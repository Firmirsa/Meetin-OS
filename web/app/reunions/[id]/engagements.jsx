'use client';

import {useEffect, useState} from 'react';
import {
  canValidate, fieldsFromProposal, formatDueDate, formatDueShort, formatMs,
  nextValidationId, splitExcerpt, toValidation,
} from '../../../lib/contract.mjs';

const STEP_COUNT = 5;
const STEP_INTERVAL_MS = 280;
const STATUS_LABEL = {pending: 'à faire', running: 'en cours', done: 'fait', error: 'en erreur'};
const AGENT_PILLS = {
  pending: ['mt-pill--run', 'En cours'],
  verified: ['mt-pill--ok', 'Terminé'],
  needs_clarification: ['mt-pill--err', 'Précision requise'],
  failed: ['mt-pill--err', 'Échec'],
};

/** Pastille de la carte : état de la revue, puis de l'exécution. */
function cardPill(state, execution) {
  if (state === 'ignored') return ['mt-pill--wait', 'Ignoré'];
  if (execution?.status === 'verified') return ['mt-pill--ok', 'Fiche à jour'];
  if (execution) return AGENT_PILLS[execution.status];
  return ['mt-pill--wait', 'À valider'];
}

/** Étapes de l'agent, dérivées pendant le rendu à partir de l'exécution. */
function agentSteps(validation, execution, runningIndex) {
  const steps = [
    {t: `Retrouve la fiche « ${validation.title} »`, m: 'Tableau de suivi'},
    {t: 'Ouvre la fiche'},
    {t: `Passe le responsable à ${validation.assignee}`},
    {t: validation.dueDate ? `Fixe l’échéance au ${formatDueDate(validation.dueDate)}` : 'Laisse l’échéance vide'},
    {t: 'Relit la fiche pour vérifier'},
  ];
  const status = execution.status;
  return steps.map((step, index) => {
    if (status === 'pending') {
      return {...step, status: index < runningIndex ? 'done' : index === runningIndex ? 'running' : 'pending'};
    }
    if (status === 'verified') return {...step, status: 'done'};
    if (status === 'needs_clarification' && index === 0) return {...step, status: 'error', m: 'Plusieurs fiches correspondent'};
    if (status === 'failed') {
      const last = index === STEP_COUNT - 1;
      return {...step, status: last ? 'error' : 'done', m: last ? execution.message : step.m};
    }
    return {...step, status: 'pending'};
  });
}

/** Un engagement : repliée, la carte montre l'essentiel. Ouverte, elle porte le seul bouton citron de l'écran. */
export default function EngagementCard({proposal, open, onToggle, agent, onShowTime, onStatus, onVerified}) {
  const [fields, setFields] = useState(() => fieldsFromProposal(proposal));
  const [editingTitle, setEditingTitle] = useState(false);
  const [state, setState] = useState('proposed');
  const [validation, setValidation] = useState(null);
  const [execution, setExecution] = useState(null);
  const [replayed, setReplayed] = useState(false);
  const [runningIndex, setRunningIndex] = useState(0);
  const sending = execution?.status === 'pending';
  const id = proposal.proposalId;
  const bodyId = `engagement-corps-${id}`;

  // Seul effet : l'animation des étapes pendant l'envoi.
  useEffect(() => {
    if (!sending) return undefined;
    const timer = setInterval(() => setRunningIndex((index) => Math.min(index + 1, STEP_COUNT - 1)), STEP_INTERVAL_MS);
    return () => clearInterval(timer);
  }, [sending]);

  async function send(next, replay = false) {
    if (sending) return;
    setValidation(next);
    setReplayed(false);
    setRunningIndex(0);
    setExecution({validationId: next.validationId, status: 'pending'});
    const result = await agent.submit(next);
    setExecution(result.execution);
    setReplayed(replay && result.replayed);
    if (result.execution.status === 'verified') {
      if (!replay) onVerified(id);
    } else {
      onStatus(id, 'todo');
      // Cible ambiguë ou échec : la carte redevient modifiable.
      if (result.execution.status === 'needs_clarification') setState('proposed');
    }
  }

  function validate() {
    if (!canValidate(fields) || sending) return;
    setEditingTitle(false);
    setState('validated');
    void send(toValidation(proposal, fields, nextValidationId(validation, proposal, fields)));
  }

  function ignore() {
    setEditingTitle(false);
    setState('ignored');
    onStatus(id, 'ignored');
  }

  function resume() {
    setState('proposed');
    onStatus(id, 'todo');
  }

  function update(key) {
    return (event) => {
      const {value} = event.target;
      setFields((current) => ({...current, [key]: value}));
    };
  }

  const [pillClass, pillText] = cardPill(state, execution);
  const locked = state !== 'proposed' || sending;
  const missingAssignee = !fields.assignee.trim();
  const excerpt = splitExcerpt(proposal.excerpt.text);

  return <article id={`engagement-${id}`} className="mt-review engagement" data-state={state} data-open={open}>
    <h3 className="engagement__heading">
      <button type="button" className="engagement__toggle" aria-expanded={open} aria-controls={bodyId} onClick={onToggle}>
        <span className="engagement__title">{fields.title || 'Sans titre'}</span>
        <span className="engagement__meta">
          {fields.assignee.trim() || 'Responsable à préciser'} · {formatDueShort(fields.dueDate || null)}
        </span>
        <span className={`mt-pill ${pillClass}`}>{pillText}</span>
      </button>
    </h3>

    <div id={bodyId} className="engagement__body" hidden={!open}>
      {editingTitle
        ? <label className="mt-field"><span className="mt-label">Titre</span>
            <input autoFocus className="mt-input" name="title" autoComplete="off" required value={fields.title} onChange={update('title')}
              onKeyDown={(event) => { if (event.key === 'Enter') setEditingTitle(false); }} />
          </label>
        : null}
      <div className="mt-review__fields">
        <label className="mt-field"><span className="mt-label">Responsable</span>
          <input className="mt-input" name="assignee" autoComplete="off" required disabled={locked} value={fields.assignee} onChange={update('assignee')}
            placeholder="Qui s’en charge ?" aria-invalid={missingAssignee} />
        </label>
        <label className="mt-field"><span className="mt-label">Échéance</span>
          <input className="mt-input" name="dueDate" type="date" disabled={locked} value={fields.dueDate} onChange={update('dueDate')} />
        </label>
      </div>
      {missingAssignee && state === 'proposed'
        ? <p className="review-hint" role="note">Personne n’a été désigné. Renseigne le responsable pour pouvoir valider.</p>
        : null}
      {execution?.status === 'needs_clarification' && state === 'proposed'
        ? <p className="review-hint review-hint--warn" role="alert">{execution.message} Corrige le titre pour désigner la bonne fiche, puis valide à nouveau.</p>
        : null}

      <blockquote className="mt-source">
        <div>
          <p>« {excerpt.before}<mark className="mt-hl">{excerpt.highlight}</mark> »</p>
          <footer>
            <button type="button" className="time-link" onClick={() => onShowTime(proposal.excerpt.startMs)}>
              <time>{formatMs(proposal.excerpt.startMs)}</time> · Voir dans la transcription
            </button>
          </footer>
        </div>
      </blockquote>

      <footer className="mt-review__actions">
        <button className="mt-btn mt-btn--primary" type="button" onClick={validate} disabled={!canValidate(fields) || sending}>Valider</button>
        <button className="mt-btn mt-btn--ghost" type="button" onClick={() => setEditingTitle((on) => !on)} disabled={sending}>
          {editingTitle ? 'Terminer' : 'Corriger le titre'}
        </button>
        <button className="mt-btn mt-btn--quiet" type="button" onClick={ignore} disabled={sending}>Ignorer</button>
      </footer>
      <div className="mt-review__done">
        {state === 'ignored'
          ? <>Ignoré. Rien n’est envoyé à l’agent. <button type="button" className="mt-btn mt-btn--quiet review-inline" onClick={resume}>Reprendre</button></>
          : 'Validé et envoyé à l’agent.'}
      </div>

      {execution !== null && validation !== null
        ? <AgentTrack validation={validation} execution={execution} replayed={replayed} runningIndex={runningIndex}
            sending={sending} onRetry={() => void send(validation)} onReplay={() => void send(validation, true)} />
        : null}
    </div>
  </article>;
}

function AgentTrack({validation, execution, replayed, runningIndex, sending, onRetry, onReplay}) {
  const [pillClass, pillText] = AGENT_PILLS[execution.status];
  const observed = execution.status === 'verified' ? execution.observed : null;
  const matches = observed !== null
    && observed.title === validation.title && observed.assignee === validation.assignee && observed.dueDate === validation.dueDate;

  return <section className="mt-agent engagement__agent" data-done={observed !== null} data-replay={replayed} aria-live="polite" aria-busy={sending}>
    <header className="mt-agent__head">
      <h4 className="mt-agent__title">L’agent</h4>
      <span className={`mt-pill ${pillClass}`}>{pillText}</span>
    </header>
    <ol className="mt-steps">
      {agentSteps(validation, execution, runningIndex).map((step, index) => (
        <li key={index} className="mt-step" data-status={step.status}>
          <span className="mt-step__dot" aria-hidden="true" />
          <div>
            <p className="mt-step__t">{step.t}<span className="visually-hidden"> · {STATUS_LABEL[step.status]}</span></p>
            {step.m ? <p className="mt-step__m">{step.m}</p> : null}
          </div>
        </li>
      ))}
    </ol>
    {execution.status === 'failed'
      ? <div className="review-message review-message--err">
          <p>{execution.message}</p>
          <button className="mt-btn mt-btn--ghost" type="button" onClick={onRetry}>Relancer</button>
        </div>
      : null}
    <div className="mt-proof">
      <h5>Valeurs relues sur la fiche</h5>
      {observed !== null
        ? <table className="mt-diff">
            <tbody>
              <tr><th scope="row">Titre</th><td>{observed.title}</td></tr>
              <tr><th scope="row">Responsable</th><td><mark className="mt-hl">{observed.assignee}</mark></td></tr>
              <tr><th scope="row">Échéance</th><td><mark className="mt-hl">{formatDueDate(observed.dueDate)}</mark></td></tr>
            </tbody>
          </table>
        : null}
      <p className="review-check">{matches ? 'Identiques à ta validation.' : 'Attention : la fiche ne correspond pas à ta validation.'}</p>
      <p className="mt-note">Fiche déjà à jour : aucune nouvelle fiche créée.</p>
      <p className="engagement__links">
        {observed !== null
          ? <a className="mt-link" href={execution.taskUrl} target="_blank" rel="noreferrer">Ouvrir la fiche ↗</a>
          : null}
        <button className="mt-btn mt-btn--quiet review-inline" type="button" onClick={onReplay} disabled={sending}>Rejouer la validation</button>
      </p>
    </div>
  </section>;
}
