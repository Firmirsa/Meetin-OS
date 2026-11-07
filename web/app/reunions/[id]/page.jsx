import Link from 'next/link';
import {notFound} from 'next/navigation';
import SiteHeader from '../../site-header';
import Initials from '../../initials';
import Meeting from './meeting';
import {SCENARIOS} from '../../../lib/contract.mjs';
import {formatDuration, formatWhen, getMeeting} from '../../../lib/meetings.mjs';

export async function generateMetadata({params}) {
  const {id} = await params;
  const meeting = getMeeting(id);
  return {title: meeting ? `${meeting.title} · Meetin-OS` : 'Réunion introuvable · Meetin-OS'};
}

export default async function MeetingPage({params, searchParams}) {
  const [{id}, {scenario: requested}] = await Promise.all([params, searchParams]);
  const meeting = getMeeting(id);
  if (!meeting) notFound();
  const scenario = Object.hasOwn(SCENARIOS, requested ?? '') ? requested : 'verified';

  return <>
    <SiteHeader current="reunions">
      <DemoMenu id={meeting.id} scenario={scenario} />
    </SiteHeader>
    <main className="shell meeting">
      <Link className="meeting-back" href="/reunions">← Réunions</Link>
      <header className="meeting-head">
        <h1>{meeting.title}</h1>
        <p className="meeting-meta">
          <span>{formatWhen(meeting.startedAt)} · {formatDuration(meeting.durationMs)} · {meeting.tool}</span>
          <Initials people={meeting.participants} />
        </p>
      </header>
      <Meeting key={scenario} meeting={meeting} scenario={scenario} />
    </main>
  </>;
}

/** Choix du scénario de l'agent simulé, pour montrer chaque cas au jury. */
function DemoMenu({id, scenario}) {
  return <details className="demo-menu">
    <summary>Démo</summary>
    <ul>
      {Object.entries(SCENARIOS).map(([key, label]) => (
        <li key={key}>
          <Link href={`/reunions/${id}?scenario=${key}`} aria-current={key === scenario ? 'true' : undefined}>{label}</Link>
        </li>
      ))}
    </ul>
  </details>;
}
