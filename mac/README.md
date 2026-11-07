# Meetin-OS pour macOS

Prototype natif SwiftUI pour macOS 15 ou ultérieur, à compiler avec Xcode. La capture utilise ScreenCaptureKit et écrit le micro et l’audio système dans deux pistes CAF, puis exporte un M4A mixé. Aucune image n’est enregistrée. Fermez les autres sources sonores pendant la démo : le prototype capte le son système de la session.

Depuis la racine du dépôt :

```sh
./mac/build.sh
open mac/.build/Meetin-OS.app
```

Le script construit et signe localement l’application. Au premier lancement de la capture, accordez le microphone et l’accès à l’enregistrement de l’écran et de l’audio système. Relancez l’application si macOS le demande.

1. Lancez un appel de test avec un autre participant. Cliquez sur **Enregistrer**, faites parler chaque personne à tour de rôle, puis cliquez sur **Arrêter**.
2. Cliquez sur **Écouter** pour vérifier les deux voix. **Voir les pistes** révèle le dossier temporaire contenant le mix et les deux pistes séparées.
3. Ouvrez **Réglages de transcription** (roue dentée) pour saisir une clé Gladia, puis cliquez sur **Transcrire** pour envoyer les pistes micro et appel séparément. Le texte indique la piste source et l’horodatage de chaque passage. Un M4A importé est traité comme un fichier unique. Si aucune clé n’est configurée, le bouton ouvre les réglages. La clé reste en mémoire pour cette session et peut aussi être fournie par la variable d’environnement `GLADIA_API_KEY` si le binaire est lancé depuis le terminal.
4. Copiez le transcript horodaté depuis l’app. Le prototype appelle Gladia directement. Dans l’onglet **Agent**, ouvre l’espace web et colle l’extrait que tu souhaites utiliser. L’adresse du site se règle dans la roue dentée. Par défaut, elle pointe vers le serveur Next.js local.

Pour reprendre un essai après avoir relancé l’app, utilise **Ouvrir un enregistrement** et choisis le fichier M4A. Avant de quitter l’app, **Voir les pistes** permet de retrouver et copier ce fichier hors du dossier temporaire. Si Gladia refuse la clé, les réglages se rouvrent et le fichier reste prêt pour une nouvelle tentative.

Au démarrage de la capture, Meetin-OS ouvre une fenêtre dédiée. L’onglet **Transcription** regroupe les notes et le texte renvoyé par Gladia après l’appel. L’onglet **Agent** permet de copier la transcription et d’ouvrir l’espace de revue des tâches. Le bouton **Afficher la réunion** permet de rouvrir la fenêtre.

Pour ouvrir la fenêtre en rejoignant un appel, active **Ouvrir la fenêtre quand je rejoins une réunion Zoom** dans les réglages de Meetin-OS et autorise l’app dans **Confidentialité et sécurité → Accessibilité**. Garde le carnet principal ouvert. La détection repose sur les titres de fenêtres de Zoom Workplace en français ou en anglais. Clique ensuite sur **Enregistrer** dans la fenêtre de réunion.

[Capture Apple](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) · [API asynchrone Gladia](https://www.gladia.io/blog/gladia-async-api-for-meeting-transcription-integration-guide-and-best-practices)

Le test audio local utilise des pistes synthétiques et simule les réponses de Gladia. Depuis la racine du dépôt, lance :

```sh
mkdir -p mac/.build
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  mac/Capture.swift mac/Gladia.swift mac/tests/GladiaSmoke.swift -o mac/.build/gladia-smoke
mac/.build/gladia-smoke
```
