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

Le script construit et signe localement l’application. Au premier enregistrement, macOS peut demander l’accès au **Microphone** et à **Audio du système uniquement**. Si une piste manque, le carnet propose un lien vers les réglages concernés et conserve la piste disponible. Les deux raccourcis sont aussi dans **Réglages → Autorisations audio**. Une nouvelle version signée localement peut demander à nouveau les autorisations.

1. Lancez un appel de test avec un autre participant. Cliquez sur **Enregistrer**, faites parler chaque personne à tour de rôle, puis cliquez sur **Arrêter**.
2. Cliquez sur **Écouter** pour vérifier les deux voix. **Voir les pistes** révèle le dossier temporaire contenant le mix et les deux pistes séparées.
3. Ouvrez **Réglages** (roue dentée) pour saisir une clé Gladia, puis cliquez sur **Transcrire** pour envoyer les pistes micro et appel séparément. Le texte indique la piste source et l’horodatage de chaque passage. Un M4A importé est traité comme un fichier unique. Si aucune clé n’est configurée, le bouton ouvre les réglages. La clé reste en mémoire pour cette session et peut aussi être fournie par la variable d’environnement `GLADIA_API_KEY` si le binaire est lancé depuis le terminal.
4. Dans l’onglet **Agent**, insère et ajuste l’extrait de transcription ou saisis une demande. Clique sur **Préparer la tâche**, réponds à la question éventuelle, puis relis l’action et sa destination avant de confirmer. Le lien de session s’affiche quand Devin ou H Computer Use accepte le lancement.

Pour activer l’agent, renseigne l’**Adresse du site Meetin-OS** et le **Code d’accès agent** dans la roue dentée. En local, l’adresse par défaut est `http://localhost:3000`. Pour la démo, utilise l’adresse HTTPS de l’équipe. Le code correspond à `MEETIN_DEMO_TOKEN` côté serveur et reste en mémoire pendant la session. Les clés de Devin et H Company restent sur le serveur, comme décrit dans le [guide Next.js](../web/README.md).

Pour reprendre un essai après avoir relancé l’app, utilise **Ouvrir un enregistrement** et choisis le fichier M4A. Avant de quitter l’app, **Voir les pistes** permet de retrouver et copier ce fichier hors du dossier temporaire. Si Gladia refuse la clé, les réglages se rouvrent et le fichier reste prêt pour une nouvelle tentative.

Au démarrage de la capture, Meetin-OS ouvre une fenêtre dédiée avec les onglets **Transcription** et **Agent**. Le bouton **Afficher la réunion** permet de rouvrir la fenêtre pendant un appel détecté ou un enregistrement. À la fin de la réunion, le carnet principal reprend la main. Tu peux y transcrire le fichier, relire le texte et préparer la tâche. Un fichier importé s’ouvre directement dans le carnet.

Pour ouvrir la fenêtre en rejoignant un appel, active **Ouvrir la fenêtre quand je rejoins une réunion Zoom** dans les réglages de Meetin-OS et autorise l’app dans **Confidentialité et sécurité → Accessibilité**. Garde le carnet principal ouvert. La détection repose sur les titres de fenêtres de Zoom Workplace en français ou en anglais. Clique ensuite sur **Enregistrer** dans la fenêtre de réunion.

[Capture audio Core Audio](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) · [API asynchrone Gladia](https://www.gladia.io/blog/gladia-async-api-for-meeting-transcription-integration-guide-and-best-practices)

Le test audio local utilise des pistes synthétiques et simule les réponses de Gladia. Depuis la racine du dépôt, lance :

```sh
mkdir -p mac/.build
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  mac/Capture.swift mac/Gladia.swift mac/tests/GladiaSmoke.swift -o mac/.build/gladia-smoke
mac/.build/gladia-smoke
```

## Régénérer l’installateur du site

Depuis la racine du dépôt, sur un Mac équipé de Xcode :

```sh
./mac/package.sh --beta web/public/downloads/Meetin-OS.pkg
```

Pour distribuer une version notariée, configure `MEETIN_APP_SIGN_IDENTITY` et `MEETIN_INSTALLER_SIGN_IDENTITY` avec les identités Developer ID installées dans le trousseau. Configure `MEETIN_NOTARY_PROFILE` avec le nom d’un profil `notarytool`, puis exécute la même commande sans `--beta`. Mets à jour la mention sur la page en même temps que le paquet. [Distribution macOS avec Developer ID](https://developer.apple.com/macos/distribution/)
