import Link from 'next/link';
import SiteHeader from '../site-header';
import Initials from '../initials';
import {allMeetings, formatDuration, formatWhen, groupByDay, pendingCount} from '../../lib/meetings.mjs';

export const metadata = {title: 'Réunions · Meetin-OS'};
export const dynamic = 'force-dynamic'; // « Aujourd'hui » et « Hier » dépendent du jour de la visite.

export default function MeetingsPage() {
  const groups = groupByDay(allMeetings());
  return <>
    <SiteHeader current="reunions" />
    <main className="shell meetings">
      <p className="eyebrow"><span /> Carnet de réunion</p>
      <h1>Réunions</h1>
      <p className="intro">Retrouve tes notes, ce qui a été dit et les engagements à valider.</p>
      {groups.length === 0
        ? <p className="meetings-empty">Aucune réunion pour l’instant. Enregistre un appel depuis l’app Mac ou Windows.</p>
        : groups.map((group) => (
          <section key={group.key} className="meetings-day" aria-labelledby={`jour-${group.key}`}>
            <h2 id={`jour-${group.key}`}>{group.label}</h2>
            <ul className="meetings-list">
              {group.meetings.map((meeting) => <li key={meeting.id}><MeetingCard meeting={meeting} /></li>)}
            </ul>
          </section>
        ))}
    </main>
  </>;
}

function MeetingCard({meeting}) {
  const pending = pendingCount(meeting);
  return <Link className="meeting-card" href={`/reunions/${meeting.id}`}>
    <span className="meeting-card__top">
      <span className="meeting-card__title">{meeting.title}</span>
      {pending > 0
        ? <span className="mt-pill mt-pill--run">{pending} à valider</span>
        : <span className="mt-pill mt-pill--wait">Rien à valider</span>}
    </span>
    <span className="meeting-card__brief">{meeting.brief}</span>
    <span className="meeting-card__meta">
      <span>{formatWhen(meeting.startedAt)} · {formatDuration(meeting.durationMs)} · {meeting.tool}</span>
      <Initials people={meeting.participants} />
    </span>
  </Link>;
}
