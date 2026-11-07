import '../brand-tokens.css';
import '../styles.css';

export const metadata = {
  icons: { icon: "/meetinos.svg" },
  title: 'Meetin-OS',
  description: 'Télécharge Meetin-OS, le carnet de réunion pour Mac et Windows.',
};

export default function Layout({children}) {
  return <html lang="fr"><body>{children}</body></html>;
}
