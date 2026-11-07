import HeroPreviewLoop from './hero-preview-loop';
import LangSwitch from './lang-switch';
import DownloadIcon from './download-icon';
import {dict, langFrom, withLang} from '../lib/i18n.mjs';

export default async function Landing({searchParams}) {
  const lang = langFrom(await searchParams);
  const t = dict(lang);
  return <div lang={t.htmlLang}>

  <HeroPreviewLoop pending={t.preview.pending} done={t.preview.done} />
  <header className="shell site-header">
    <a className="brand" href={withLang('/', lang)} aria-label={t.nav.home}>
      <img src="/meetinos.svg" alt="" width="32" height="32" />
      Meetin-OS
    </a>
    <nav aria-label={t.nav.main}>
      <a href="#fonctionnement">{t.nav.journey}</a>
      <a href={withLang('/onboarding', lang)}>{t.nav.firstSteps}</a>
      <a className="nav-link" href="https://github.com/Firmirsa/Meetin-OS">GitHub <span aria-hidden="true">↗</span></a>
      <LangSwitch lang={lang} path="/" label={t.nav.lang} />
    </nav>
  </header>
  <main>
    <section className="shell hero" aria-labelledby="titre">
      <div className="hero-copy">
        <p className="eyebrow"><span></span> {t.hero.eyebrow}</p>
        <h1 id="titre">{t.hero.titleStart}<em>{t.hero.titleHighlight}</em></h1>
        <p className="intro">{t.hero.intro}</p>
        <div className="install-actions" id="installation">
          <a className="button button--download" href={withLang('/telecharger', lang)}>
            <DownloadIcon /> {t.hero.download}
          </a>
        </div>
        <p className="requirements">{t.hero.downloadHint}</p>
      </div>
      <figure className="preview">
        <div className="window">
          <div className="window-bar">
            <div className="lights" aria-hidden="true"><i></i><i></i><i></i></div>
            <span>{t.preview.window}</span>
            <span className="window-badge">{t.preview.badge}</span>
          </div>
          <div className="window-body">
            <p className="meeting-label">{t.preview.label}</p>
            <p className="meeting-title">{t.preview.title}</p>
            <div className="note">
              <strong>{t.preview.notes}</strong>
              <p>{t.preview.note}</p>
            </div>
            <div className="segment">
              <span className="timestamp">00:18</span>
              <p>{t.preview.quoteStart}<mark>{t.preview.quoteHighlight}</mark>{t.preview.quoteEnd}</p>
            </div>
            <div className="task">
              <div>
                <p className="task-label">{t.preview.taskLabel}</p>
                <strong>{t.preview.task}</strong>
                <p className="task-meta">{t.preview.taskMeta}</p>
              </div>
              <span className="task-state" id="etat-apercu">{t.preview.pending}</span>
            </div>
          </div>
        </div>
        <figcaption>{t.preview.caption}</figcaption>
      </figure>
    </section>
    <section className="workflow" id="fonctionnement" aria-labelledby="parcours">
      <div className="shell">
        <p className="eyebrow"><span></span> {t.journey.eyebrow}</p>
        <h2 id="parcours">{t.journey.title}</h2>
        <ol className="steps">
          {t.journey.steps.map(([title, text], i) => (
            <li key={title}>
              <span className="step-index">0{i + 1}{i === 2 && <> <span className="planned">{t.journey.soon}</span></>}</span>
              <h3>{title}</h3><p>{text}</p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  </main>
  <footer className="shell site-footer">
    <span>{t.footer.project}</span>
    <a href="https://github.com/Firmirsa/Meetin-OS#readme">{t.footer.docs} <span aria-hidden="true">↗</span></a>
  </footer>

</div>;
}
