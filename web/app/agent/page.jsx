import { redirect } from 'next/navigation';

export default async function LegacyAgentPage({searchParams}) {
  const {checkout} = await searchParams;
  redirect(checkout === 'returned' || checkout === 'canceled' ? `/onboarding?checkout=${checkout}` : '/onboarding');
}
