# Meetin-OS pour macOS

Prototype natif SwiftUI pour macOS 15 ou ultérieur. Meetin-OS capture le micro et l’audio du système avec Core Audio, écrit deux pistes CAF et exporte un M4A. Ferme les autres sources sonores pendant la démo pour isoler le son de l’appel.

## Installer depuis le site

Clique sur **Installer sur Mac**, ouvre `Meetin-OS.pkg` dans Téléchargements et confirme dans l’assistant macOS. Celui-ci installe `Meetin-OS.app` dans **Applications**. Le paquet contient une version pour Apple Silicon et Intel. La version de test n’est pas notariée par Apple et macOS peut bloquer son ouverture. Le paquet publié avant la version 0.1.4 utilise encore le réglage Gladia local. [Aide Apple sur l’ouverture des logiciels téléchargés](https://support.apple.com/fr-fr/102445)

## Compiler avec Xcode

Depuis la racine du dépôt :

```sh
./mac/build.sh
open mac/.build/Meetin-OS.app
```

Le script construit et signe localement l’application. Au premier enregistrement, macOS peut demander l’accès au **Microphone** et à **Audio du système uniquement**. Si une piste manque, le carnet propose un lien vers les réglages concernés et conserve la piste disponible. Les deux raccourcis sont aussi dans **Paramètres → Autorisations audio**. Une nouvelle version signée localement peut demander à nouveau les autorisations. Si la détection d’appels reste inactive alors que Meetin-OS apparaît activé dans **Confidentialité et sécurité → Accessibilité**, retire l’entrée de l’ancien build et ajoute à nouveau la copie de Meetin-OS que tu ouvres.

Au lancement de Mac 0.1.5, clique sur **Se connecter avec Google** pour ouvrir ton carnet. Compile la version de recette avec `MEETIN_WEB_URL` défini sur l’adresse du serveur de test. Le serveur Meetin-OS utilise la clé Gladia de l’équipe. **Compte** affiche le quota restant et permet de passer à Premium via Stripe si le paiement est configuré. [Configuration du serveur](../web/README.md#comptes-transcription-et-abonnement-mac)

1. Lancez un appel de test avec un autre participant. Sur l’**Accueil**, cliquez sur **Commencer à enregistrer** (⌘R), faites parler chaque personne à tour de rôle, puis cliquez sur **Arrêter**.
2. Cliquez sur **Écouter** pour vérifier les deux voix. **Voir les pistes** révèle le dossier de la réunion contenant le mix et les deux pistes séparées.
3. Cliquez sur **Transcrire** pour envoyer les pistes micro et appel séparément. Si la session a expiré ou si vous n’êtes pas connecté, l’app ouvre le formulaire et reprend après la connexion. Le texte indique la piste source et l’horodatage de chaque passage. Un M4A importé est traité comme une seule piste.
4. Dans l’onglet **Agent**, insère et ajuste l’extrait de transcription ou saisis une demande. Clique sur **Préparer la tâche**, réponds à la question éventuelle, puis relis l’action et sa destination avant de confirmer. Le lien de session s’affiche quand Devin ou H Computer Use accepte le lancement.

La connexion Google à Meetin-OS donne accès à l’agent. Le catalogue **Intégrations** indique si Trello et Devin sont configurés. Les clés de Devin et H Company restent sur le serveur. [Guide Next.js](../web/README.md)

Dans l’onglet Agent, **Recherche publique avec Linkup** permet d’envoyer volontairement une question publique et d’ouvrir les sources de la réponse. La session Google et `LINKUP_API_KEY` sur le serveur sont nécessaires ; le panneau indique si l’accès reste non confirmé. Il ne transmet pas automatiquement la transcription et ne lance aucune tâche.

Le raccordement Trello global décrit dans le prototype est en cours de remplacement par une connexion personnelle : voir le [diagnostic](../docs/connexion-trello.md). Ne pas le configurer comme accès partagé entre utilisateurs.

L’historique est conservé sur ce Mac dans `~/Library/Application Support/Meetin-OS` : `meetings.json` (titre, date, durée, chemin audio, transcription, notes) et un dossier audio par réunion dans `recordings/`. Il se remplit à l’arrêt de l’enregistrement et après la transcription. Pour reprendre un essai, rouvre la réunion depuis **Réunions**. Pour un fichier externe, utilise **Ouvrir un enregistrement** sur cette page et choisis un M4A.

**Transcription en direct** : connecte-toi avant de lancer l’enregistrement et active l’option dans **Paramètres**. Le texte s’écrit pendant l’appel, pendant que le serveur Meetin-OS transmet les pistes à Gladia et compte l’audio envoyé. Sans casque, une phrase de l’appel captée par le micro est retirée de la piste du micro si elle reprend au moins 70 % des mots de la piste de l’appel à 10 s près ; une reprise à l’identique peut donc être masquée, et l’audio reste complet. À l’arrêt, le texte du direct reste dans la réunion. **Transcrire** le remplace par la version différée et compte cet envoi dans le quota. Si le direct est coupé durablement ou si le quota s’épuise, l’enregistrement continue.

En direct comme en différé, les phrases du micro portent le nom complet du compte macOS, ou « Vous » s’il est vide ; celles de l’autre piste restent « Audio de l’appel ». Les réunions transcrites avant ce changement gardent l’étiquette « Micro ».

**Tâches proposées** : si le direct tourne et que l’agent est connecté, le texte définitif part chez Holo (H Company) toutes les 15 s quand il a changé. Les tâches détectées apparaissent en cartes dans l’onglet **Agent** et restent enregistrées dans la réunion, affichée « N à valider ». Rien ne part sans clic sur **Confirmer et lancer** ou sur l’action de sa notification. Un plan expire après 15 minutes : **Modifier** le reprend dans le formulaire pour en préparer un nouveau.

Chaque nouvelle tâche envoie une notification macOS avec son titre et sa destination, visibles aussi en partage d’écran. **Confirmer** lance le plan affiché. Si une correction l’a remplacé, rien ne part et la carte s’ouvre. **Ajouter du contexte et lancer** demande à Holo de réécrire la tâche et **la lance sans nouvelle relecture**, sauf si Holo pose une question. Le plan réellement lancé reste visible sur la carte. Pour voir les boutons en permanence, choisis le style **Alertes** dans Réglages Système → Notifications.

Pendant une réunion détectée ou un enregistrement, Meetin-OS ouvre à droite une fenêtre avec les onglets **Transcription** et **Agent**. Elle occupe toute la hauteur disponible et environ un tiers de la largeur de l’écran. Le bouton **Afficher la réunion** permet de la rouvrir. Le panneau se ferme à la fin. Après un enregistrement, la fiche s’ouvre dans la fenêtre principale. Tu peux y transcrire le fichier, relire le texte et préparer la tâche. Un fichier importé s’ouvre de la même façon.

La détection des appels est activée par défaut après connexion. Tu peux la désactiver dans **Paramètres → Détection des appels → Me prévenir quand je rejoins un appel**. Autorise Meetin-OS dans **Réglages Système → Confidentialité et sécurité → Accessibilité**, puis accepte les notifications macOS. Garde Meetin-OS ouvert. La détection prend en charge Google Meet dans Chrome, Zoom Workplace et l’app WhatsApp pour Mac, en français et en anglais. Laisse l’onglet Meet visible au moment de rejoindre. Clique sur **Enregistrer** dans la notification ou dans le panneau pour lancer la capture. Cliquer sur le corps de la notification ouvre le panneau. Pour laisser l’alerte affichée, choisis le style **Alertes** dans **Réglages Système → Notifications**.

[Capture audio Core Audio](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) · [API asynchrone Gladia](https://www.gladia.io/blog/gladia-async-api-for-meeting-transcription-integration-guide-and-best-practices)

Le test audio local utilise des pistes synthétiques et simule les réponses de Gladia. Depuis la racine du dépôt, lance :

```sh
mkdir -p mac/.build
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  mac/MeetingParticipants.swift mac/Capture.swift mac/HostedAccount.swift mac/Gladia.swift mac/LiveTranscription.swift mac/tests/GladiaSmoke.swift -o mac/.build/gladia-smoke
mac/.build/gladia-smoke
```

Le test de l’historique local s’exécute sans audio :

```sh
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  mac/MeetingParticipants.swift mac/AgentClient.swift mac/MeetingStore.swift mac/MeetinSite.swift mac/tests/MeetingStoreSmoke.swift -o mac/.build/store-smoke
mac/.build/store-smoke
```

La détection et les actions de notification se testent avec des réponses simulées :

```sh
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  mac/MeetingParticipants.swift mac/AgentClient.swift mac/MeetingStore.swift mac/TaskDetection.swift mac/TaskActions.swift mac/tests/TaskDetectionSmoke.swift -o mac/.build/detect-smoke
mac/.build/detect-smoke
```

Le direct et **Transcrire** reconnaissent uniquement le français et l’anglais pour l’instant.

Le test du direct utilise une connexion simulée :

```sh
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  mac/MeetingParticipants.swift mac/Capture.swift mac/HostedAccount.swift mac/Gladia.swift mac/LiveTranscription.swift mac/tests/LiveTranscriptionSmoke.swift -o mac/.build/live-smoke
mac/.build/live-smoke
```

## Régénérer l’installateur du site

Depuis la racine du dépôt, sur un Mac équipé de Xcode :

```sh
MEETIN_WEB_URL=https://ton-site-meetin.example ./mac/package.sh --beta web/public/downloads/Meetin-OS.pkg
```

Remplace `MEETIN_WEB_URL` par l’adresse du serveur configuré : l’app installée l’utilise dès son premier lancement. Pour distribuer une version notariée, configure `MEETIN_APP_SIGN_IDENTITY` et `MEETIN_INSTALLER_SIGN_IDENTITY` avec les identités Developer ID installées dans le trousseau. Configure `MEETIN_NOTARY_PROFILE` avec le nom d’un profil `notarytool`, puis exécute la même commande sans `--beta`. Mets à jour la mention sur la page en même temps que le paquet. [Distribution macOS avec Developer ID](https://developer.apple.com/macos/distribution/)
