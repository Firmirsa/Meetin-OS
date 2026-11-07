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
    windows: {name: 'Windows', req: 'Windows 10 ou 11 (x64)', cta: 'Télécharger pour Windows', file: 'Meetin-OS-Windows.exe',
      note: 'Ouvre l’installateur pour ajouter Meetin-OS au menu Démarrer. Windows peut signaler cette version de test non signée.'},
    linux: {name: 'Linux', req: 'Ubuntu, Debian, Fedora', cta: 'En préparation',
      note: 'La version Linux est en préparation. En attendant, Meetin-OS fonctionne sur Mac et Windows.'},
    next: 'Ensuite : ', nextLink: 'les premiers pas',
  },
  onboarding: {
    metaTitle: 'Premiers pas · Meetin-OS', back: '← Meetin-OS', nav: 'Navigation',
    title: 'Premiers pas', intro: 'Prépare l’app avant ta première réunion.',
    install: 'Installer', installLink: 'Télécharge Meetin-OS', installRest: ' pour Mac ou Windows et ouvre l’installateur.',
    sound: 'Autoriser le son', soundText: 'Au premier enregistrement, accorde à l’app l’accès au micro et à l’audio du système si elle le demande.',
    config: 'Configurer l’app', configText: 'Saisis ta clé Gladia dans les réglages de l’app. Sur Mac, ajoute l’adresse du site de ton équipe et son code d’accès pour utiliser l’onglet Agent.',
    returned: 'Retour de Stripe. Vérifie le statut de l’abonnement de test dans Stripe.',
    canceled: 'Checkout de test annulé.',
    stripeLabel: 'STRIPE · MODE TEST', stripeTitle: 'Essayer l’abonnement',
    checkout: {code: 'Code d’accès de l’équipe', open: 'Ouvrir Stripe Checkout', opening: 'Ouverture…', unavailable: 'Stripe Checkout est indisponible.'},
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
    windows: {name: 'Windows', req: 'Windows 10 or 11 (x64)', cta: 'Download for Windows', file: 'Meetin-OS-Windows.exe',
      note: 'Run the installer to add Meetin-OS to the Start menu. Windows may flag this unsigned test build.'},
    linux: {name: 'Linux', req: 'Ubuntu, Debian, Fedora', cta: 'In progress',
      note: 'The Linux version is in progress. Meanwhile, Meetin-OS runs on Mac and Windows.'},
    next: 'Next: ', nextLink: 'get started',
  },
  onboarding: {
    metaTitle: 'Get started · Meetin-OS', back: '← Meetin-OS', nav: 'Navigation',
    title: 'Get started', intro: 'Set up the app before your first meeting.',
    install: 'Install', installLink: 'Download Meetin-OS', installRest: ' for Mac or Windows and open the installer.',
    sound: 'Allow audio', soundText: 'On your first recording, give the app access to the microphone and system audio if it asks.',
    config: 'Set up the app', configText: 'Enter your Gladia key in the app settings. On Mac, add your team’s site address and access code to use the Agent tab.',
    returned: 'Back from Stripe. Check the test subscription status in Stripe.',
    canceled: 'Test checkout canceled.',
    stripeLabel: 'STRIPE · TEST MODE', stripeTitle: 'Try the subscription',
    checkout: {code: 'Team access code', open: 'Open Stripe Checkout', opening: 'Opening…', unavailable: 'Stripe Checkout is unavailable.'},
  },
};

export const DICT = {fr, en};
export function dict(lang) { return DICT[lang] ?? DICT[DEFAULT_LANG]; }
