import LangSwitch from '../lang-switch';
import DownloadIcon from '../download-icon';
import PlatformPick from './platform-pick';
import {dict, langFrom, withLang} from '../../lib/i18n.mjs';

export async function generateMetadata({searchParams}) {
  return {title: dict(langFrom(await searchParams)).download.metaTitle};
}

/** Une carte par système. Mac est mis en avant par défaut ; PlatformPick ajuste selon l'appareil. */
export default async function DownloadPage({searchParams}) {
  const lang = langFrom(await searchParams);
  const t = dict(lang);
  const d = t.download;
  return <div lang={t.htmlLang}>
    <header className="shell site-header">
      <a className="brand" href={withLang('/', lang)} aria-label={t.nav.home}>
        <img src="/meetinos.svg" alt="" width="32" height="32" />
        Meetin-OS
      </a>
      <nav aria-label={t.nav.main}>
        <a href={withLang('/onboarding', lang)}>{t.nav.firstSteps}</a>
        <a className="nav-link" href="https://github.com/Firmirsa/Meetin-OS">GitHub <span aria-hidden="true">↗</span></a>
        <LangSwitch lang={lang} path="/telecharger" label={t.nav.lang} />
      </nav>
    </header>
    <main className="shell download" aria-labelledby="titre">
      <p className="eyebrow"><span></span> {d.eyebrow}</p>
      <h1 id="titre">{d.title}</h1>
      <p className="intro">{d.intro}</p>

      <ul className="platforms">
        <li className="platform mt-card" data-os="mac" data-recommended="true">
          <span className="platform__tag">{d.recommended}</span>
          <OsIcon os="mac" />
          <h2>{d.mac.name}</h2>
          <p className="platform__req">{d.mac.req}</p>
          <a className="mt-btn platform__cta" href="/downloads/Meetin-OS.pkg" download>
            <DownloadIcon size={16} /> {d.mac.cta}
          </a>
          <p className="platform__note">{d.mac.note} <a href="https://support.apple.com/fr-fr/102445">{d.mac.help}</a></p>
          <p className="platform__file">{d.mac.file}</p>
        </li>
        <li className="platform mt-card" data-os="windows">
          <span className="platform__tag">{d.recommended}</span>
          <OsIcon os="windows" />
          <h2>{d.windows.name}</h2>
          <p className="platform__req">{d.windows.req}</p>
          <a className="mt-btn platform__cta" href="/downloads/Meetin-OS-Windows.exe" download>
            <DownloadIcon size={16} /> {d.windows.cta}
          </a>
          <p className="platform__note">{d.windows.note}</p>
          <p className="platform__file">{d.windows.file}</p>
        </li>
        <li className="platform mt-card" data-os="linux" data-soon="true">
          <span className="platform__tag platform__tag--soon">{d.soon}</span>
          <OsIcon os="linux" />
          <h2>{d.linux.name}</h2>
          <p className="platform__req">{d.linux.req}</p>
          <span className="mt-btn platform__cta" aria-disabled="true">{d.linux.cta}</span>
          <p className="platform__note">{d.linux.note}</p>
        </li>
      </ul>

      <p className="download__next">{d.next}<a href={withLang('/onboarding', lang)}>{d.nextLink}</a> →</p>
    </main>
    <PlatformPick />
  </div>;
}

/** Pictos système simplifiés et génériques (pas de logos de marque). */
function OsIcon({os}) {
  const common = {className: 'platform__icon', width: 28, height: 28, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor',
    strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': 'true', focusable: 'false'};
  if (os === 'mac') return <svg {...common}><rect x="3" y="4" width="18" height="12" rx="2" /><path d="M2 20h20" /></svg>;
  if (os === 'windows') return <svg {...common}><rect x="3" y="4" width="18" height="13" rx="2" /><path d="M8 21h8M12 17v4" /></svg>;
  return <svg {...common}><path d="M4 5h16v14H4z" /><path d="m7.5 10 2.5 2-2.5 2M12 14h4" /></svg>;
}
