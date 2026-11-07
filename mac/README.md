# Meetin-OS pour macOS

Prototype natif SwiftUI pour macOS 15 ou ultérieur. Meetin-OS capture le micro et l’audio du système avec Core Audio, écrit deux pistes CAF et exporte un M4A. Ferme les autres sources sonores pendant la démo pour isoler le son de l’appel.

## Installer depuis le site

Clique sur **Installer sur Mac**, ouvre `Meetin-OS.pkg` dans Téléchargements et confirme dans l’assistant macOS. Celui-ci installe `Meetin-OS.app` dans **Applications**. Le paquet contient une version pour Apple Silicon et Intel. La version de test n’est pas notariée par Apple et macOS peut bloquer son ouverture. [Aide Apple sur l’ouverture des logiciels téléchargés](https://support.apple.com/fr-fr/102445)

## Compiler avec Xcode

Depuis la racine du dépôt :

```sh
./mac/build.sh
open mac/.build/Meetin-OS.app
```

Le script construit et signe localement l’application. Au premier enregistrement, macOS peut demander l’accès au **Microphone** et à **Audio du système uniquement**. Si une piste manque, le carnet propose un lien vers les réglages concernés et conserve la piste disponible. Les deux raccourcis sont aussi dans **Paramètres → Autorisations audio**. Une nouvelle version signée localement peut demander à nouveau les autorisations.

L’**Accueil**, le carnet et l’enregistrement restent disponibles sans compte. **Intégrations**, dans la barre latérale et la fenêtre de réunion, permet d’activer Gladia ou de connecter l’agent plus tard.

1. Lancez un appel de test avec un autre participant. Sur l’**Accueil**, cliquez sur **Commencer à enregistrer** (⌘R), faites parler chaque personne à tour de rôle, puis cliquez sur **Arrêter**.
2. Cliquez sur **Écouter** pour vérifier les deux voix. **Voir les pistes** révèle le dossier de la réunion contenant le mix et les deux pistes séparées.
3. Cliquez sur **Transcrire** pour envoyer les pistes micro et appel séparément. Si une clé Gladia est nécessaire, l’app ouvre le formulaire correspondant et reprend l’envoi quand vous cliquez sur **Transcrire** dans ce formulaire. La clé peut aussi s’ajouter dans **Paramètres** ou **Intégrations** et reste dans le trousseau de ce Mac. La variable d’environnement `GLADIA_API_KEY` a la priorité si le binaire est lancé depuis le terminal. Une version signée localement peut demander l’accès au trousseau après chaque compilation. Le texte indique la piste source et l’horodatage de chaque passage. Un M4A importé est traité comme un fichier unique.
4. Dans l’onglet **Agent**, insère et ajuste l’extrait de transcription ou saisis une demande. Clique sur **Préparer la tâche**, réponds à la question éventuelle, puis relis l’action et sa destination avant de confirmer. Le lien de session s’affiche quand Devin ou H Computer Use accepte le lancement.

Pour activer l’agent, ouvre **Intégrations → Connecter l’agent** ou clique sur **Ouvrir les intégrations sur Mac** depuis la page **Premiers pas** du site de l’équipe. Le site préremplit l’adresse. En local, l’adresse par défaut est `http://localhost:3000`. Le code correspond à `MEETIN_DEMO_TOKEN` côté serveur et reste en mémoire pendant la session. Le catalogue indique la configuration de Trello et Devin et présente Google Calendar comme à venir. Les clés de Devin et H Company restent sur le serveur. [Guide Next.js](../web/README.md) **Compte** rappelle l’adresse et ouvre ce formulaire. **Facturation et abonnement** ouvre `/onboarding#subscription` sur cette adresse.

L’historique est conservé sur ce Mac dans `~/Library/Application Support/Meetin-OS` : `meetings.json` (titre, date, durée, chemin audio, transcription, notes) et un dossier audio par réunion dans `recordings/`. Il se remplit à l’arrêt de l’enregistrement et après la transcription. Pour reprendre un essai, rouvre la réunion depuis **Réunions**. Pour un fichier externe, utilise **Ouvrir un enregistrement** sur cette page et choisis un M4A. Si Gladia refuse la clé, le formulaire Gladia se rouvre et le fichier reste prêt pour une nouvelle tentative.

**Transcription en direct** : avec une clé Gladia et l’option activée dans **Paramètres**, le texte s’écrit pendant l’appel dans la fenêtre de réunion. L’audio est alors envoyé en continu à Gladia, une session par piste. À l’arrêt, ce texte devient la transcription de la réunion, et **Transcrire** le remplace par la version différée. Si le direct échoue, l’enregistrement continue : une notification macOS prévient si la clé est refusée, si le direct ne démarre pas ou s’il reste coupé 30 s, et la réunion affiche alors « Incomplète ».

Au démarrage de la capture, Meetin-OS ouvre une fenêtre dédiée avec les onglets **Transcription** et **Agent**. Le bouton **Afficher la réunion** permet de rouvrir la fenêtre pendant un appel détecté ou un enregistrement. À la fin de la réunion, la fenêtre principale ouvre sa fiche. Tu peux y transcrire le fichier, relire le texte et préparer la tâche. Un fichier importé s’ouvre de la même façon.

Pour ouvrir la fenêtre en rejoignant un appel, active **Ouvrir la fenêtre quand je rejoins une réunion Zoom** dans les **Paramètres** de Meetin-OS et autorise l’app dans **Confidentialité et sécurité → Accessibilité**. Garde la fenêtre principale ouverte. La détection repose sur les titres de fenêtres de Zoom Workplace en français ou en anglais. Clique ensuite sur **Enregistrer** dans la fenêtre de réunion.

[Capture audio Core Audio](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) · [API asynchrone Gladia](https://www.gladia.io/blog/gladia-async-api-for-meeting-transcription-integration-guide-and-best-practices)

Le test audio local utilise des pistes synthétiques et simule les réponses de Gladia. Depuis la racine du dépôt, lance :

```sh
mkdir -p mac/.build
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  mac/Capture.swift mac/Gladia.swift mac/tests/GladiaSmoke.swift -o mac/.build/gladia-smoke
mac/.build/gladia-smoke
```

Le test de l’historique local s’exécute sans audio :

```sh
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  mac/MeetingStore.swift mac/MeetinSite.swift mac/tests/MeetingStoreSmoke.swift -o mac/.build/store-smoke
mac/.build/store-smoke
```

Le test du direct utilise une connexion simulée :

```sh
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  mac/Capture.swift mac/Gladia.swift mac/LiveTranscription.swift mac/tests/LiveTranscriptionSmoke.swift -o mac/.build/live-smoke
mac/.build/live-smoke
```

## Régénérer l’installateur du site

Depuis la racine du dépôt, sur un Mac équipé de Xcode :

```sh
./mac/package.sh --beta web/public/downloads/Meetin-OS.pkg
```

Pour distribuer une version notariée, configure `MEETIN_APP_SIGN_IDENTITY` et `MEETIN_INSTALLER_SIGN_IDENTITY` avec les identités Developer ID installées dans le trousseau. Configure `MEETIN_NOTARY_PROFILE` avec le nom d’un profil `notarytool`, puis exécute la même commande sans `--beta`. Mets à jour la mention sur la page en même temps que le paquet. [Distribution macOS avec Developer ID](https://developer.apple.com/macos/distribution/)
