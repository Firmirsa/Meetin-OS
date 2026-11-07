import {redirect} from 'next/navigation';
import {SCENARIOS} from '../../lib/contract.mjs';

// La revue des tâches vit maintenant dans la page Réunion.
export default async function ReviewRedirect({searchParams}) {
  const {scenario} = await searchParams;
  const query = Object.hasOwn(SCENARIOS, scenario ?? '') ? `?scenario=${scenario}` : '';
  redirect(`/reunions/point-de-lancement${query}`);
}
