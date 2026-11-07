/** Participants en pastilles d'initiales, sans photo. */
export default function Initials({people}) {
  return <span className="initials" role="img" aria-label={`Participants : ${people.map((p) => p.name).join(', ')}`}>
    {people.map((person) => <span key={person.name} className="initials__chip" title={person.name} aria-hidden="true">{person.initials}</span>)}
  </span>;
}
