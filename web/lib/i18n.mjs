// Traductions du site (FR par défaut, EN avec ?lang=en).
// Pas de bibliothèque : un dictionnaire par langue, mêmes clés partout.
// Pour ajouter une langue : copier le bloc `en`, traduire, l'ajouter à LANGS.

export const LANGS = ['fr', 'en'];
export const DEFAULT_LANG = 'fr';

/** Langue demandée par l'URL (?lang=en), sinon le français. */
export function langFrom(searchParams) {
  const lang = searchParams?.lang;
  return LANGS.includes(lang) ? lang : DEFAULT_LANG;
}

/** Ajoute ?lang=… à un lien interne quand la langue n'est pas celle par défaut. */
export function withLang(href, lang) {
  if (lang === DEFAULT_LANG) return href;
  const [path, hash] = href.split('#');
  const sep = path.includes('?') ? '&' : '?';
  return `${path}${sep}lang=${lang}${hash ? `#${hash}` : ''}`;
}

const fr = {
  htmlLang: 'fr',
  nav: {home: 'Meetin-OS, accueil', main: 'Navigation principale', journey: 'Le parcours', firstSteps: 'Premiers pas', download: 'Télécharger', lang: 'Langue'},
  hero: {
    eyebrow: 'Prototype pour Mac et Windows',
    titleStart: 'De l’appel à la ',
    titleHighlight: 'tâche validée.',
    intro: 'Prends tes notes pendant l’appel. Retrouve ensuite ce qui a été dit et garde le contexte des décisions.',
    download: 'Télécharger',
    downloadHint: 'Gratuit · macOS et Windows · Linux bientôt',
  },
  preview: {
    window: 'Carnet de réunion', badge: 'APERÇU', label: 'RÉUNION PRODUIT', title: 'Point de lancement',
    notes: 'Notes', note: 'Relire le guide avant le prochain point.',
    quoteStart: '« Finalement, ', quoteHighlight: 'Karim s’en charge mardi.', quoteEnd: ' »',
    taskLabel: 'ENGAGEMENT PROPOSÉ', task: 'Relire le guide', taskMeta: 'Karim · Mardi',
    pending: 'À valider', done: 'Fiche à jour', caption: 'Aperçu du parcours dans l’app Mac',
  },
  journey: {
    eyebrow: 'Le parcours', title: 'Garder le fil après l’appel.', soon: 'À venir',
    steps: [
      ['Capturer', 'Enregistre le micro et le son de l’appel. Note les points clés dans le même carnet.'],
      ['Relire', 'Lance la transcription avec Gladia et retrouve les passages grâce à leurs repères temporels.'],
      ['Valider', 'Confirme l’engagement, son responsable et son échéance avant la mise à jour de la tâche.'],
    ],
  },
  footer: {project: 'Meetin-OS · Projet du hackathon H Company × 42AI', docs: 'Documentation'},
  download: {
    metaTitle: 'Télécharger · Meetin-OS',
    eyebrow: 'Télécharger',
    title: 'Meetin-OS sur ton ordinateur.',
    intro: 'Choisis ton système. L’installation prend moins d’une minute.',
    recommended: 'Pour cet appareil',
    soon: 'Bientôt',
    mac: {name: 'macOS', req: 'macOS 15 ou plus récent', cta: 'Télécharger pour Mac', file: 'Meetin-OS.pkg',
      note: 'Ouvre le paquet pour ajouter Meetin-OS à Applications. La version de test n’est pas notariée.', help: 'Aide Apple'},
    windows: {name: 'Windows', req: 'Windows 10 ou 11 (x64)', cta: 'Télécharger la bêta 0.1.0', file: 'Meetin-OS-Windows.exe · 0.1.0', test: 'Tester Windows 0.1.1 (compte GitHub requis)',
      note: 'Ouvre l’installateur pour ajouter Meetin-OS au menu Démarrer. Windows peut signaler cette version de test non signée.'},
    linux: {name: 'Linux', req: 'Ubuntu, Debian, Fedora', cta: 'En préparation',
      note: 'La version Linux est en préparation. En attendant, Meetin-OS fonctionne sur Mac et Windows.'},
    next: 'Ensuite : ', nextLink: 'les premiers pas',
  },
  onboarding: {
    metaTitle: 'Premiers pas · Meetin-OS', back: '← Meetin-OS', nav: 'Navigation',
    title: 'Premiers pas', intro: 'Installe Meetin-OS pour retrouver tes réunions et les actions à suivre.',
    install: 'Installer', installLink: 'Télécharge Meetin-OS', installRest: ' pour Mac ou Windows et ouvre l’installateur.',
    sound: 'Se connecter sur Mac', soundText: 'Ouvre Meetin-OS et clique sur Se connecter avec Google.',
    config: 'Enregistrer une réunion', configText: 'Au premier appel, autorise le micro et l’audio du système. Le plan Gratuit inclut un quota de transcription.',
    toolsTitle: 'Outils facultatifs', toolsIntro: 'Sur Mac, le code de ton équipe donne accès aux outils qu’elle a configurés.',
    tools: [['Trello', 'Fiches de suivi'], ['Google Calendar', 'À venir'], ['Devin', 'Tâches de code']],
    openMac: 'Ouvrir les intégrations sur Mac',
    openMacHelp: 'Si le navigateur demande d’ouvrir Meetin-OS, confirme l’ouverture. Tu peux aussi ouvrir Intégrations dans l’app.',
    returned: 'Retour de Stripe. Ouvre Compte dans l’app pour consulter ton plan.',
    canceled: 'Paiement annulé.',
    stripeLabel: 'ABONNEMENT', stripeTitle: 'Passer à Premium',
    stripeText: 'Consulte ton quota dans Compte. Tu peux passer à Premium via Stripe depuis l’app Mac.',
    openAccount: 'Ouvrir mon compte sur Mac',
  },
};

const en = {
  htmlLang: 'en',
  nav: {home: 'Meetin-OS, home', main: 'Main navigation', journey: 'How it works', firstSteps: 'Get started', download: 'Download', lang: 'Language'},
  hero: {
    eyebrow: 'Prototype for Mac and Windows',
    titleStart: 'From call to ',
    titleHighlight: 'approved task.',
    intro: 'Take notes during the call. Then find what was said and keep the context behind every decision.',
    download: 'Download',
    downloadHint: 'Free · macOS and Windows · Linux soon',
  },
  preview: {
    window: 'Meeting notebook', badge: 'PREVIEW', label: 'PRODUCT MEETING', title: 'Launch sync',
    notes: 'Notes', note: 'Review the guide before the next sync.',
    quoteStart: '“Actually, ', quoteHighlight: 'Karim will handle it Tuesday.', quoteEnd: '”',
    taskLabel: 'PROPOSED COMMITMENT', task: 'Review the guide', taskMeta: 'Karim · Tuesday',
    pending: 'To review', done: 'Card updated', caption: 'Preview of the flow in the Mac app',
  },
  journey: {
    eyebrow: 'How it works', title: 'Keep the thread after the call.', soon: 'Coming soon',
    steps: [
      ['Capture', 'Record your mic and the call audio. Jot key points in the same notebook.'],
      ['Review', 'Transcribe with Gladia and jump to any passage with its timestamp.'],
      ['Approve', 'Confirm the commitment, its owner and due date before the task is updated.'],
    ],
  },
  footer: {project: 'Meetin-OS · H Company × 42AI hackathon project', docs: 'Documentation'},
  download: {
    metaTitle: 'Download · Meetin-OS',
    eyebrow: 'Download',
    title: 'Meetin-OS on your computer.',
    intro: 'Pick your system. Setup takes less than a minute.',
    recommended: 'For this device',
    soon: 'Soon',
    mac: {name: 'macOS', req: 'macOS 15 or later', cta: 'Download for Mac', file: 'Meetin-OS.pkg',
      note: 'Open the package to add Meetin-OS to Applications. This test build is not notarized.', help: 'Apple help'},
    windows: {name: 'Windows', req: 'Windows 10 or 11 (x64)', cta: 'Download beta 0.1.0', file: 'Meetin-OS-Windows.exe · 0.1.0', test: 'Test Windows 0.1.1 (GitHub sign-in required)',
      note: 'Run the installer to add Meetin-OS to the Start menu. Windows may flag this unsigned test build.'},
    linux: {name: 'Linux', req: 'Ubuntu, Debian, Fedora', cta: 'In progress',
      note: 'The Linux version is in progress. Meanwhile, Meetin-OS runs on Mac and Windows.'},
    next: 'Next: ', nextLink: 'get started',
  },
  onboarding: {
    metaTitle: 'Get started · Meetin-OS', back: '← Meetin-OS', nav: 'Navigation',
    title: 'Get started', intro: 'Install Meetin-OS to keep your meetings and follow-up actions together.',
    install: 'Install', installLink: 'Download Meetin-OS', installRest: ' for Mac or Windows and open the installer.',
    sound: 'Sign in on Mac', soundText: 'Open Meetin-OS and select Sign in with Google.',
    config: 'Record a meeting', configText: 'On your first call, allow microphone and system audio access. The Free plan includes a transcription allowance.',
    toolsTitle: 'Optional tools', toolsIntro: 'On Mac, your team’s access code unlocks the tools it has configured.',
    tools: [['Trello', 'Follow-up cards'], ['Google Calendar', 'Coming soon'], ['Devin', 'Coding tasks']],
    openMac: 'Open integrations on Mac',
    openMacHelp: 'If the browser asks to open Meetin-OS, confirm. You can also open Integrations inside the app.',
    returned: 'Back from Stripe. Open Account in the app to view your plan.',
    canceled: 'Payment canceled.',
    stripeLabel: 'SUBSCRIPTION', stripeTitle: 'Upgrade to Premium',
    stripeText: 'View your allowance under Account. You can upgrade to Premium through Stripe from the Mac app.',
    openAccount: 'Open my account on Mac',
  },
};

export const DICT = {fr, en};
export function dict(lang) { return DICT[lang] ?? DICT[DEFAULT_LANG]; }
