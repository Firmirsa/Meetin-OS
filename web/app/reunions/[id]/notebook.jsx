'use client';

import {useEffect} from 'react';
import {formatMs} from '../../../lib/contract.mjs';
import {transcriptIndexAt} from '../../../lib/meetings.mjs';

const TABS = [
  {key: 'notes', label: 'Notes'},
  {key: 'transcript', label: 'Transcription'},
];

/** Le carnet : tes notes en encre, l'IA en encre secondaire, les accords au surligneur. */
export default function Notebook({meeting, tab, onTab, focusMs, openId, onOpenCard, onShowTime}) {
  // Onglets ARIA : flèches gauche et droite pour passer d'un onglet à l'autre.
  function onTabKey(event) {
    if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return;
    event.preventDefault();
    const index = TABS.findIndex((item) => item.key === tab);
    const next = TABS[(index + (event.key === 'ArrowRight' ? 1 : TABS.length - 1)) % TABS.length];
    onTab(next.key);
    document.getElementById(`onglet-${next.key}`)?.focus();
  }

  return <section className="notebook" aria-labelledby="carnet-titre">
    <h2 id="carnet-titre" className="visually-hidden">Carnet de la réunion</h2>
    <div className="notebook__tabs" role="tablist" aria-label="Vue du carnet">
      {TABS.map((item) => (
        <button
          key={item.key}
          id={`onglet-${item.key}`}
          type="button"
          role="tab"
          aria-selected={tab === item.key}
          aria-controls={`panneau-${item.key}`}
          tabIndex={tab === item.key ? 0 : -1}
          className="notebook__tab"
          onClick={() => onTab(item.key)}
          onKeyDown={onTabKey}
        >{item.label}</button>
      ))}
    </div>
    <div id="panneau-notes" role="tabpanel" aria-labelledby="onglet-notes" className="notebook__panel" hidden={tab !== 'notes'}>
      <Notes meeting={meeting} openId={openId} onOpenCard={onOpenCard} onShowTime={onShowTime} />
    </div>
    <div id="panneau-transcript" role="tabpanel" aria-labelledby="onglet-transcript" className="notebook__panel" hidden={tab !== 'transcript'}>
      <Transcript meeting={meeting} visible={tab === 'transcript'} focusMs={focusMs} openId={openId} onOpenCard={onOpenCard} />
    </div>
  </section>;
}

function Highlight({proposalId, text, openId, onOpenCard}) {
  return <button
    type="button"
    className="mt-hl note-hl"
    data-active={openId === proposalId}
    aria-label={`${text} Ouvrir l’engagement`}
    onClick={() => onOpenCard(proposalId)}
  >{text}</button>;
}

function Notes({meeting, openId, onOpenCard, onShowTime}) {
  return <div className="notes">
    <div className="notes__brief">
      <p className="mt-label">En bref</p>
      <p>{meeting.brief}</p>
    </div>
    <div className="notes__legend" aria-hidden="true">
      <span className="notes__legend-mine">Tes notes</span>
      <span className="notes__legend-ai">Ajouté par Meetin-OS</span>
    </div>
    {meeting.notes.map((note, index) => {
      if (note.kind === 'heading') return <h3 key={index} className="notes__heading">{note.text}</h3>;
      if (note.kind === 'marker') {
        return <p key={index} className="notes__marker">
          <span aria-hidden="true">⚑</span>
          <button type="button" className="time-link" onClick={() => onShowTime(note.atMs)}>
            <time>{formatMs(note.atMs)}</time>
          </button>
          <span>{note.text}</span>
        </p>;
      }
      return <p key={index} className={note.kind === 'mine' ? 'notes__mine' : 'notes__ai'}>
        {note.kind === 'ai' ? <span className="visually-hidden">Ajouté par Meetin-OS : </span> : null}
        {note.text}
        {note.highlight
          ? <Highlight proposalId={note.highlight.proposalId} text={note.highlight.text} openId={openId} onOpenCard={onOpenCard} />
          : null}
      </p>;
    })}
  </div>;
}

function Transcript({meeting, visible, focusMs, openId, onOpenCard}) {
  const activeIndex = focusMs === null ? -1 : transcriptIndexAt(meeting, focusMs);
  const excerpts = new Map(meeting.proposals.map((p) => [p.excerpt.startMs, p]));

  // Synchronisation avec le DOM : amener le passage demandé à l'écran.
  useEffect(() => {
    if (!visible || activeIndex < 0) return;
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    document.getElementById(`passage-${activeIndex}`)?.scrollIntoView({block: 'center', behavior: reduce ? 'auto' : 'smooth'});
  }, [visible, activeIndex]);

  if (meeting.transcript.length === 0) {
    return <p className="notes__empty">Pas encore de transcription. Lance « Transcrire » dans l’app Mac ou Windows.</p>;
  }

  return <ol className="transcript">
    {meeting.transcript.map((segment, index) => {
      const proposal = excerpts.get(segment.startMs);
      const at = proposal ? segment.text.indexOf(proposal.excerpt.text) : -1;
      return <li key={segment.startMs} id={`passage-${index}`} className="transcript__item" data-active={index === activeIndex}>
        <p className="transcript__who">
          <span className="transcript__speaker">{segment.speaker}</span>
          <time className="transcript__time">{formatMs(segment.startMs)}</time>
        </p>
        <p className="transcript__text">
          {at >= 0
            ? <>
                {segment.text.slice(0, at)}
                <Highlight proposalId={proposal.proposalId} text={proposal.excerpt.text} openId={openId} onOpenCard={onOpenCard} />
                {segment.text.slice(at + proposal.excerpt.text.length)}
              </>
            : segment.text}
        </p>
      </li>;
    })}
  </ol>;
}
