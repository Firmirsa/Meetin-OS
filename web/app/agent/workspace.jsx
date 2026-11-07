'use client';

import {useState, useRef} from 'react';

export default function AgentWorkspace() {
  const [token, setToken] = useState('');
  const [context, setContext] = useState('');
  const [task, setTask] = useState('');
  const [draft, setDraft] = useState(null);
  const [query, setQuery] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [results, setResults] = useState({});
  const [error, setError] = useState('');
  const [pending, setPending] = useState('');
  const inFlight = useRef(false);

  async function run(operation, body) {
    if (inFlight.current) return;
    inFlight.current = true;
    setError('');
    setPending(operation);
    try {
      const route = operation === 'draft' ? '/api/agent/draft' : `/api/${operation}`;
      const response = await fetch(route, {
        method: 'POST',
        headers: {'Content-Type': 'application/json', Authorization: `Bearer ${token.trim()}`},
        body: JSON.stringify(body),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Cette action a échoué.');
      if (operation === 'checkout') {
        window.location.assign(result.url);
        return;
      }
      if (operation === 'draft') {
        setDraft(result);
        setTask(result.task);
        setConfirmed(false);
      } else {
        setResults((current) => ({...current, [operation]: result}));
        if (operation === 'devin') setConfirmed(false);
      }
    } catch (failure) {
      setError(failure.message);
      if (operation === 'devin') setConfirmed(false);
    } finally {
      setPending('');
      inFlight.current = false;
    }
  }

  const locked = !token.trim() || Boolean(pending);

  return <>
    <label className="access-field">
      Code d’accès de l’équipe
      <input type="password" value={token} onChange={(event) => setToken(event.target.value)} autoComplete="off" />
    </label>
    {error && <p role="alert" className="workspace-error">{error}</p>}
    <div className="workspace-grid">
      <section className="mt-card">
        <p className="mt-label">01 · EXPLORER</p>
        <h2>Recherche sourcée</h2>
        <form onSubmit={(event) => {event.preventDefault(); void run('linkup', {query});}}>
          <label>Question publique pour Linkup<input required maxLength={500} value={query} onChange={(event) => setQuery(event.target.value)} /></label>
          <button className="mt-btn mt-btn--ghost" disabled={locked || !query.trim()}>{pending === 'linkup' ? 'Recherche…' : 'Chercher des sources'}</button>
        </form>
        {results.linkup && <div className="workspace-result" aria-live="polite">
          <p>{results.linkup.answer}</p>
          <ul>{results.linkup.sources.map((source, index) => <li key={index}><a href={source.url} target="_blank" rel="noreferrer">{source.name} ↗</a></li>)}</ul>
        </div>}
      </section>
      <section className="mt-card">
        <p className="mt-label">02 · PRÉPARER</p>
        <h2>Tâche de code</h2>
        <form onSubmit={(event) => {event.preventDefault(); void run('devin', {task, context, confirmed});}}>
          <label>Extrait de réunion facultatif<textarea maxLength={5000} rows={3} disabled={Boolean(pending)} value={context} onChange={(event) => {
            setContext(event.target.value);
            setConfirmed(false);
            setDraft(null);
          }} /></label>
          <button type="button" className="mt-btn mt-btn--ghost" disabled={locked || !context.trim()} onClick={() => void run('draft', {transcript: context})}>
            {pending === 'draft' ? 'Analyse…' : 'Proposer une tâche'}
          </button>
          {draft && <blockquote className="mt-quote"><strong>{draft.title}</strong><br />{draft.quote}</blockquote>}
          <label>Tâche à transmettre à Devin<textarea required maxLength={3000} rows={4} disabled={Boolean(pending)} value={task} onChange={(event) => {
            setTask(event.target.value);
            setConfirmed(false);
          }} /></label>
          <label className="confirm"><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /> J’ai relu la tâche et l’extrait. Je confirme leur envoi à Devin.</label>
          <button className="mt-btn mt-btn--primary" disabled={locked || !confirmed || !task.trim()}>{pending === 'devin' ? 'Création de la session…' : 'Envoyer à Devin'}</button>
        </form>
        {results.devin && <p role="status"><a href={results.devin.url} target="_blank" rel="noreferrer">Suivre la session Devin ↗</a></p>}
      </section>
    </div>
    <section className="mt-card checkout">
      <div><p className="mt-label">STRIPE · MODE TEST</p><h2>Essayer l’abonnement</h2></div>
      <button className="mt-btn mt-btn--ghost" disabled={locked} onClick={() => void run('checkout', {})}>{pending === 'checkout' ? 'Ouverture…' : 'Ouvrir Stripe Checkout'}</button>
    </section>
  </>;
}
