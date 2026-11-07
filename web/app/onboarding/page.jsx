import OnboardingCheckout from './checkout';

export const metadata = { title: 'Premiers pas · Meetin-OS' };

export default async function OnboardingPage({searchParams}) {
  const {checkout} = await searchParams;
  return <main className="shell onboarding">
    <nav aria-label="Navigation"><a href="/">← Meetin-OS</a></nav>
    <h1>Premiers pas</h1>
    <p className="intro">Prépare l’app avant ta première réunion.</p>
    <ol className="steps">
      <li><h3>Installer</h3><p><a href="/#installation">Télécharge Meetin-OS</a> pour Mac ou Windows et ouvre l’installateur.</p></li>
      <li><h3>Autoriser le son</h3><p>Au premier enregistrement, accorde à l’app l’accès au micro et à l’audio du système si elle le demande.</p></li>
      <li><h3>Configurer l’app</h3><p>Saisis ta clé Gladia dans les réglages de l’app. Sur Mac, ajoute l’adresse du site de ton équipe et son code d’accès pour utiliser l’onglet Agent.</p></li>
    </ol>
    {checkout === 'returned' && <p role="status">Retour de Stripe. Vérifie le statut de l’abonnement de test dans Stripe.</p>}
    {checkout === 'canceled' && <p role="status">Checkout de test annulé.</p>}
    <section className="mt-card checkout" id="subscription" aria-labelledby="subscription-heading">
      <p className="mt-label">STRIPE · MODE TEST</p>
      <h2 id="subscription-heading">Essayer l’abonnement</h2>
      <OnboardingCheckout />
    </section>
  </main>;
}
