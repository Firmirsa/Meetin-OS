import '../brand-tokens.css';
import '../styles.css';
import '../theme-nuit.css'; // thème nuit : chargé en dernier, ne change que les couleurs

export const metadata = {
  icons: { icon: "/meetinos.svg" },
  title: 'Meetin-OS',
  description: 'Télécharge Meetin-OS, le carnet de réunion pour Mac, Windows et Linux.',
};

export const viewport = { themeColor: '#0F1613' };

export default function Layout({children}) {
  return <html lang="fr"><body>{children}</body></html>;
}
