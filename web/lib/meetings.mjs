// Réunions de démonstration pour la liste et la page Réunion.
// Les engagements (`proposals`) suivent le type Proposition de lib/contract.mjs.
import demo from './reunions-demo.json' with {type: 'json'};

const TIME_ZONE = 'Europe/Paris';
const dayKey = new Intl.DateTimeFormat('fr-CA', {timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit'});
const dayLabel = new Intl.DateTimeFormat('fr-FR', {timeZone: TIME_ZONE, weekday: 'long', day: 'numeric', month: 'long'});
const shortDay = new Intl.DateTimeFormat('fr-FR', {timeZone: TIME_ZONE, weekday: 'short', day: 'numeric', month: 'short'});
const clock = new Intl.DateTimeFormat('fr-FR', {timeZone: TIME_ZONE, hour: '2-digit', minute: '2-digit'});

/** Toutes les réunions, de la plus récente à la plus ancienne. */
export function allMeetings() {
  return demo.meetings.toSorted((a, b) => Date.parse(b.startedAt) - Date.parse(a.startedAt));
}

export function getMeeting(id) {
  return demo.meetings.find((meeting) => meeting.id === id) ?? null;
}

export function pendingCount(meeting) {
  return meeting.proposals.length;
}

/** Réunions groupées par jour (heure de Paris) : « Aujourd'hui », « Hier », puis la date. */
export function groupByDay(meetings, now = new Date()) {
  const today = dayKey.format(now);
  const yesterday = dayKey.format(new Date(now.getTime() - 86_400_000));
  const groups = new Map();
  for (const meeting of meetings) {
    const date = new Date(meeting.startedAt);
    const key = dayKey.format(date);
    if (!groups.has(key)) {
      const label = key === today ? 'Aujourd’hui' : key === yesterday ? 'Hier' : capitalize(dayLabel.format(date));
      groups.set(key, {key, label, meetings: []});
    }
    groups.get(key).meetings.push(meeting);
  }
  return [...groups.values()];
}

/** « sam. 7 nov. · 10:30 » */
export function formatWhen(startedAt) {
  const date = new Date(startedAt);
  return `${capitalize(shortDay.format(date))} · ${clock.format(date)}`;
}

/** 1920000 ms → « 32 min » */
export function formatDuration(ms) {
  const minutes = Math.round(ms / 60000);
  return minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, '0')}`;
}

/** Index du passage de transcription qui contient l'instant `ms`. */
export function transcriptIndexAt(meeting, ms) {
  let found = -1;
  for (let index = 0; index < meeting.transcript.length; index += 1) {
    if (meeting.transcript[index].startMs <= ms) found = index;
    else break;
  }
  return found;
}

function capitalize(text) {
  return text.charAt(0).toUpperCase() + text.slice(1);
}
