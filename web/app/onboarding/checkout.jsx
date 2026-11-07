'use client';

import {useRef, useState} from 'react';

export default function OnboardingCheckout() {
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
      if (!response.ok) throw new Error(result.error || 'Stripe Checkout est indisponible.');
      window.location.assign(result.url);
    } catch (failure) {
      setError(failure.message);
      setPending(false);
      inFlight.current = false;
    }
  }

  return <form onSubmit={checkout}>
    <label>Code d’accès de l’équipe
      <input type="password" value={token} disabled={pending} onChange={(event) => setToken(event.target.value)} autoComplete="off" required />
    </label>
    <button className="mt-btn mt-btn--ghost" disabled={pending || !token.trim()}>{pending ? 'Ouverture…' : 'Ouvrir Stripe Checkout'}</button>
    {error && <p className="checkout-error" role="alert">{error}</p>}
  </form>;
}
