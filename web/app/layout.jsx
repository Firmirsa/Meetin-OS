import '../brand-tokens.css';
import '../brand-components.css';
import '../styles.css';

export const metadata = {
  icons: { icon: "/meetinos.svg" },
  title: 'Meetin-OS',
  description: 'Le carnet de réunion pour Mac et Windows et son espace agent.',
};

export const viewport = {
  themeColor: [
    {media: '(prefers-color-scheme: light)', color: '#FAF8F1'},
    {media: '(prefers-color-scheme: dark)', color: '#0F1613'},
  ],
};

export default function Layout({children}) {
  return <html lang="fr">
    <head>
      <link rel="preconnect" href="https://fonts.googleapis.com" />
      <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
      <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=EB+Garamond:wght@400;500&family=Figtree:wght@400;500;600&display=swap" />
    </head>
    <body>{children}</body>
  </html>;
}
