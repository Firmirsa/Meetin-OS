import Link from 'next/link';

const LINKS = [
  {href: '/reunions', label: 'Réunions', key: 'reunions'},
  {href: '/agent', label: 'Espace agent', key: 'agent'},
];

/** En-tête de l'app web (réunions, espace agent). La landing garde le sien. */
export default function SiteHeader({current, children}) {
  return <header className="shell site-header app-header">
    <Link className="brand" href="/" aria-label="Meetin-OS, accueil">
      <img src="/meetinos.svg" alt="" width="28" height="28" />
      <span translate="no">Meetin-OS</span>
    </Link>
    <nav aria-label="Navigation principale">
      {LINKS.map((link) => (
        <Link key={link.key} href={link.href} aria-current={link.key === current ? 'page' : undefined}>{link.label}</Link>
      ))}
      {children}
    </nav>
  </header>;
}
