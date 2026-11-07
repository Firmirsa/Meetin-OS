import OpenMacIntegrations from './open-mac';
import LangSwitch from '../lang-switch';
import {dict, langFrom, withLang} from '../../lib/i18n.mjs';

export async function generateMetadata({searchParams}) {
  return {title: dict(langFrom(await searchParams)).onboarding.metaTitle};
}

export default async function OnboardingPage({searchParams}) {
  const params = await searchParams;
  const {checkout} = params;
  const lang = langFrom(params);
  const t = dict(lang);
  const o = t.onboarding;
  return <main className="shell onboarding" lang={t.htmlLang}>
    <nav aria-label={o.nav}>
      <a href={withLang('/', lang)}>{o.back}</a>
      <LangSwitch lang={lang} path="/onboarding" label={t.nav.lang} />
    </nav>
    <h1>{o.title}</h1>
    <p className="intro">{o.intro}</p>
    <ol className="steps">
      <li><h3>{o.install}</h3><p><a href={withLang('/telecharger', lang)}>{o.installLink}</a>{o.installRest}</p></li>
      <li><h3>{o.sound}</h3><p>{o.soundText}</p></li>
      <li><h3>{o.config}</h3><p>{o.configText}</p></li>
    </ol>
    <section className="mt-card onboarding-options" id="outils" aria-labelledby="integrations-heading">
      <h2 id="integrations-heading">{o.toolsTitle}</h2>
      <p>{o.toolsIntro}</p>
      <ul className="onboarding-tools">
        {o.tools.map(([name, purpose]) => <li key={name}><strong>{name}</strong><span>{purpose}</span></li>)}
      </ul>
      <OpenMacIntegrations label={o.openMac} />
      <p className="onboarding-help">{o.openMacHelp}</p>
    </section>
    {checkout === 'returned' && <p role="status">{o.returned}</p>}
    {checkout === 'canceled' && <p role="status">{o.canceled}</p>}
    <section className="mt-card checkout" id="subscription" aria-labelledby="subscription-heading">
      <p className="mt-label">{o.stripeLabel}</p>
      <h2 id="subscription-heading">{o.stripeTitle}</h2>
      <p>{o.stripeText}</p>
      <OpenMacIntegrations label={o.openAccount} account />
    </section>
  </main>;
}
