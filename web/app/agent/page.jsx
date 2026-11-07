import AgentWorkspace from './workspace';

export const metadata = { title: 'Espace agent · Meetin-OS' };

export default async function AgentPage({searchParams}) {
  const {checkout} = await searchParams;
  return <main className="shell workspace">
    <nav aria-label="Navigation"><a href="/">← Meetin-OS</a> <a href="/reunions">Réunions</a></nav>
    <p className="eyebrow"><span /> Carnet de réunion</p>
    <h1>Espace agent</h1>
    <p className="intro">Pars d’un extrait, vérifie les sources et prépare une tâche de code.</p>
    {checkout === 'returned' && <p role="status">Retour de Stripe. Vérifie le statut de l’abonnement de test dans Stripe.</p>}
    {checkout === 'canceled' && <p role="status">Checkout de test annulé.</p>}
    <AgentWorkspace />
  </main>;
}
