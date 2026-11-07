'use client';

import {useRef, useState} from 'react';
import Notebook from './notebook';
import EngagementCard from './engagements';
import {createFixtureAgent} from '../../../lib/contract.mjs';

const NEXT_CARD_DELAY_MS = 1500;

function scrollBehavior() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth';
}

/** Page Réunion : le carnet à gauche, les engagements à droite. Une seule carte ouverte à la fois. */
export default function Meeting({meeting, scenario}) {
  const [agent] = useState(() => createFixtureAgent({scenario}));
  const [tab, setTab] = useState('notes');
  const [focusMs, setFocusMs] = useState(null);
  const [openId, setOpenId] = useState(meeting.proposals[0]?.proposalId ?? null);
  const [statuses, setStatuses] = useState(() => Object.fromEntries(meeting.proposals.map((p) => [p.proposalId, 'todo'])));
  // Copie à jour des statuts, lue dans les rappels asynchrones (ouverture de la carte suivante).
  const latestStatuses = useRef(statuses);
  const todo = Object.values(statuses).filter((status) => status === 'todo').length;

  function report(id, status) {
    const next = {...latestStatuses.current, [id]: status};
    latestStatuses.current = next;
    setStatuses(next);
  }

  function openCard(id) {
    setOpenId(id);
    document.getElementById(`engagement-${id}`)?.scrollIntoView({block: 'nearest', behavior: scrollBehavior()});
  }

  function showInTranscript(ms) {
    setTab('transcript');
    setFocusMs(ms);
  }

  // Fiche vérifiée : on laisse voir le résultat, puis on ouvre l'engagement suivant à valider.
  function verified(id) {
    report(id, 'done');
    setTimeout(() => {
      const next = meeting.proposals.find((p) => latestStatuses.current[p.proposalId] === 'todo');
      if (next) setOpenId((current) => (current === id ? next.proposalId : current));
    }, NEXT_CARD_DELAY_MS);
  }

  return <div className="meeting-grid">
    <Notebook
      meeting={meeting}
      tab={tab}
      onTab={setTab}
      focusMs={focusMs}
      openId={openId}
      onOpenCard={openCard}
      onShowTime={showInTranscript}
    />
    <aside className="engagements" aria-labelledby="engagements-titre">
      <header className="engagements__head">
        <h2 id="engagements-titre">Engagements</h2>
        {todo > 0
          ? <span className="mt-pill mt-pill--run">{todo} à valider</span>
          : <span className="mt-pill mt-pill--ok">Tout est traité</span>}
      </header>
      {meeting.proposals.length === 0
        ? <p className="engagements__empty">Aucun engagement détecté dans cette réunion.</p>
        : <ol className="engagements__list">
          {meeting.proposals.map((proposal) => (
            <li key={proposal.proposalId}>
              <EngagementCard
                proposal={proposal}
                open={openId === proposal.proposalId}
                onToggle={() => setOpenId((current) => (current === proposal.proposalId ? null : proposal.proposalId))}
                agent={agent}
                onShowTime={showInTranscript}
                onStatus={report}
                onVerified={verified}
              />
            </li>
          ))}
        </ol>}
    </aside>
  </div>;
}
