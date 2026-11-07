'use client';

import {useRef, useState} from 'react';

const DEFAULT_LABELS = {code: 'Code d’accès de l’équipe', open: 'Ouvrir Stripe Checkout', opening: 'Ouverture…', unavailable: 'Stripe Checkout est indisponible.'};

export default function OnboardingCheckout({labels = DEFAULT_LABELS}) {
  const [token, setToken] = useState('');
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');
  const inFlight = useRef(false);

  async function checkout(event) {
    event.preventDefault();
    const code = token.trim();
    if (!code || inFlight.current) return;
    inFlight.current = true;
    setPending(true);
    setError('');
    try {
      const response = await fetch('/api/checkout', {
        method: 'POST',
        headers: {'Content-Type': 'application/json', Authorization: `Bearer ${code}`},
        body: '{}',
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || labels.unavailable);
      window.location.assign(result.url);
    } catch (failure) {
      setError(failure.message);
      setPending(false);
      inFlight.current = false;
    }
  }

  return <form onSubmit={checkout}>
    <label>{labels.code}
      <input type="password" value={token} disabled={pending} onChange={(event) => setToken(event.target.value)} autoComplete="off" required />
    </label>
    <button className="mt-btn mt-btn--ghost" disabled={pending || !token.trim()}>{pending ? labels.opening : labels.open}</button>
    {error && <p className="checkout-error" role="alert">{error}</p>}
  </form>;
}
