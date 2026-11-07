import {LANGS} from '../lib/i18n.mjs';

/** Bascule FR / EN. Garde la page courante, ne change que ?lang. */
export default function LangSwitch({lang, path, label}) {
  return <span className="lang-switch" role="group" aria-label={label}>
    {LANGS.map((code) => (
      <a key={code} href={code === 'fr' ? path : `${path}?lang=${code}`} hrefLang={code} lang={code}
        aria-current={code === lang ? 'true' : undefined}>{code.toUpperCase()}</a>
    ))}
  </span>;
}
