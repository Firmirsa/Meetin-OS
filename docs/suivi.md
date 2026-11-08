# Suivi Meetin-OS

Dernier point : 8 novembre 2026. La [bêta 0.1.0](https://github.com/Firmirsa/Meetin-OS/releases/tag/v0.1.0-beta) contient les installateurs Mac et Windows. Le [plan d’exécution](plan-hackathon.md) reste la référence pour la répartition et la démo.

| Sujet | État | Prochaine action |
|---|---|---|
| Mac · Wael | Le 7 novembre, Meetin-OS 0.1.1 sur macOS 26.5.2 a enregistré deux pistes pendant un vrai appel d’environ 33 s. Gladia a renvoyé des passages horodatés sur les deux pistes. Le repère du micro est reconnu ; le repère distant attendu n’apparaît pas. | Rejouer un court appel en faisant parler d’abord la personne distante pour confirmer son repère. |
| Arrivée en réunion · Mac | Meetin-OS peut ouvrir la fenêtre de réunion à l’arrivée dans Zoom si la détection est activée. | Tester la détection sur un appel Zoom et ajouter une notification macOS à l’arrivée. |
| Accueil Mac · Lenny | Sur `main` depuis le 7 novembre. L’installateur Mac du site n’a pas été régénéré. Nouvelle fenêtre principale (barre latérale, Accueil, Réunions, Paramètres, Compte) et historique local dans Application Support. Le 7 novembre, essai réel sur macOS 27.2 : enregistrement deux pistes, arrêt, réunion dans l’historique, relance de l’app. Détection Zoom non testée : Zoom n’est pas installé sur ce Mac. | Vérifier la transcription Gladia et l’onglet Agent avec de vrais accès, puis tester la détection sur un appel Zoom. |
| Transcription en direct · Mac | Sur `main` depuis le 7 novembre. Le texte s’écrit pendant l’enregistrement via l’API live de Gladia, une session par piste, et la clé se garde dans le trousseau. Une panne durable envoie une notification et la réunion passe à « Incomplète ». Le 7 novembre, essai réel sur macOS 27.2 d’environ 40 s avec le vrai Gladia : texte affiché pendant l’enregistrement sur les deux pistes, réunion enregistrée « Transcrite » à l’arrêt. Défauts vus puis corrigés : voix en double quand le micro capte les haut-parleurs, parasites dans d’autres langues, panneau sous les notes. Second essai réel d’environ 30 s, voix de synthèse en français et en anglais par les haut-parleurs : panneau visible, aucune ligne en double ni en langue étrangère. Le message pour le démarrage expiré de l’audio système (`MACH_RCV_TIMED_OUT`) n’a pas été revu à l’écran. Notification de panne et reprise réseau testées seulement en simulé. | Refaire un vrai appel de 2 min avec une autre personne, couper le réseau 20 s et vérifier le coût sur la page tarifs. Vérifier ce que Gladia conserve de l’audio. |
| Détection de tâches · Mac et web | Sur `main` depuis le 7 novembre. Opération `agent-detect` et détecteur Mac (toutes les 15 s, seulement si le texte a changé). Cartes dans l’onglet Agent, enregistrées dans la réunion, avec validation explicite. Actif si le direct tourne et que l’agent est connecté. Notification par tâche : le contexte relance Holo et part sans nouvelle relecture, choix de Lenny. Le 7 novembre, essai réel avec Gladia et Holo sur un serveur local, voix de synthèse : tâche détectée en moins de 30 s, carte et compteur affichés, notification vue à l’écran par Lenny, tâche enregistrée dans la réunion. Le texte erroné de la transcription passe dans le titre de la tâche. Quatre textes inventés envoyés à Holo ont donné le résultat attendu. Clic réel sur Confirmer et lancer depuis une carte, sur le serveur local : session Devin créée, lien affiché, [PR de test](https://github.com/Firmirsa/Meetin-OS/pull/1) ouverte. Le nom de fichier mal transcrit (`doc.sc20.md`) est allé jusqu’à la PR, fusionnée par erreur dans `main` puis retiré. Boutons de la notification jamais cliqués, dont le contexte qui lance sans relecture. | Mesurer la qualité sur de vrais échanges et vérifier le coût. Essayer Confirmer et le contexte depuis la notification. Traiter les erreurs de transcription qui passent dans les tâches. |
| Windows · Wael | Installation, raccourci Démarrer et ouverture du carnet vérifiés sur [GitHub Actions](https://github.com/Firmirsa/Meetin-OS/actions/runs/42378395887). Gladia testé avec des réponses simulées. | Vérifier les pistes micro et appel sur un PC, puis transcrire. |
| Revue des tâches · Samy et Wael | Mac 0.1.2 : l’onglet Agent pose une question si le contexte manque et attend une confirmation explicite. Le 7 novembre, client Swift et serveur Next.js testés ensemble avec des réponses simulées pour Devin et H Computer Use. Le [contrat et ses données de test](contrat-front-agent.md) restent disponibles pour la carte de Samy. | Configurer les accès H et Devin et valider l’exécution depuis l’app Mac avant de passer à Google Calendar. |
| Recette H Computer Use · Trello | Le 7 novembre, après confirmation de Wael, HoloTab en mode supervisé a créé « Relire le guide » dans À faire sur le tableau Meetin-OS Démo, depuis Chrome connecté à Trello. Vérification dans Trello : une seule fiche dans la liste, puis ouverture de cette fiche. | Rejouer la création depuis l’app Mac avec un profil H Platform connecté au tableau de test. |
| Premiers pas · Mac et web | Mac 0.1.3 propose le carnet sans compte et un écran Intégrations. Le 7 novembre, test local avec réponses simulées du code refusé, de la préparation reprise après connexion et de la proposition Trello conservée jusqu’à la vérification des accès. Le site présente les outils facultatifs en français et en anglais. | Relier le profil H de démo au tableau Trello et rejouer le parcours avec les accès réels. |
| Site et démo · Lenny et équipe | Le site Next.js contient les téléchargements, les premiers pas et Stripe Checkout en mode test. L’installateur Mac 0.1.3 est dans le dépôt. | Vérifier la version servie par Vercel et répéter le parcours avec les comptes de test. |

Le 8 novembre, le site Vercel répondait et les routes `agent-access` et `agent-detect` ont rejeté le code local (HTTP 401). Le build Mac de recette pointe par défaut vers `https://meetin-os.vercel.app`. La détection et les notifications avec cet environnement restent à vérifier avec le code de démo hébergé.

## Mac 0.1.6 (7), 8 novembre 2026

État : **branche de livraison en préparation, paquet public local remplacé, production non publiée**. Base `816b3f0`, branche de livraison prévue `codex/release-readiness-0.1.6`. Wael a autorisé explicitement le commit, le push et le remplacement du paquet public. Le 8 novembre, il a restreint la publication au seul projet `meetin-os` ; `meetin-os-recette`, réservé aux essais YouTube de Lenny, ne doit pas être déployé. Aucune fusion dans `main` ni modification de l’ancienne release GitHub n’est autorisée. Le carnet et l’enregistrement restent accessibles sans compte. Les travaux H Computer Use / Trello de Lenny ne sont pas modifiés.

Paquet reconstruit le 8 novembre 2026, contrôlé à 15:56 CET : `mac/.build/Meetin-OS-0.1.6.pkg`, 3072033 octets, SHA-256 `dea50fb474bf1b73ee8a628e184cb49a23fe1cd3f171e3ce162761a6a1b63aa6`, MD5 `cdee25b459628a97f9cd64db3a07fd19`. Ces empreintes remplacent celles de la reconstruction précédente. Version extraite 0.1.6 (7), architectures `x86_64 arm64`, `codesign --verify --strict --all-architectures` réussi pour l’app. Dans **chaque** architecture : zéro occurrence de `localhost:3000`, une de `meetin-os.vercel.app`. Le paquet n’a pas de signature de distribution : `spctl --assess --type install --verbose` renvoie 3 et « no usable signature ».

Le fichier `web/public/downloads/Meetin-OS.pkg` a été remplacé localement, sans reconstruction, par le candidat testé : SHA-256 `dea50fb474bf1b73ee8a628e184cb49a23fe1cd3f171e3ce162761a6a1b63aa6`. Le paquet précédent avait le SHA-256 `dc68834f562f102b90ab9028c0f988d5c6462e488e625fc4411ef81a0debcbcf`. Aucune source Swift, Info.plist ou script de construction n’a été modifié depuis la construction testée, selon les horodatages contrôlés et le diff conservé.

### Audit des neuf correctifs

« Fait » indique le code relu et compilé, complété par les tests simulés pertinents, sans valoir recette réelle de l’interface ou du matériel.

| Correctif | À la reprise | État final et preuve |
|---|---|---|
| 1. Étapes Gatekeeper FR/EN | Fait | Fait : `web/lib/i18n.mjs:57` et `:116`, selon l’[aide Apple](https://support.apple.com/fr-fr/102445). |
| 2. Outil ou destination changés après contexte | Fait | Fait : `mac/MeetingFlow.swift:132`, retour avant `client.launch`, plan réécrit gardé sur la carte ; appels simulés vérifiés. |
| 3. Avertissement de changement micro | Fait | Fait : `mac/Capture.swift:98`, aucun redémarrage depuis l’observateur. |
| 4. Conservation après arrêt en erreur | Fait | Fait : `mac/Capture.swift:118`, `mac/MeetinOS.swift:386`, conversion CAF dans `mac/Gladia.swift:57`. Historique avec ou sans audio et notes remises à zéro au prochain démarrage (`mac/MeetingFlow.swift:223`) vérifiés en simulé. |
| 5. Blocage du changement de réunion et du nouvel enregistrement pendant un lancement | Fait | Fait : `mac/MeetingFlow.swift:11`, `mac/MeetinOS.swift:343` et boutons correspondants. Arrêter une capture reste possible. |
| 6. Expiration facultative des plans | Fait | Fait : `mac/AgentClient.swift:25`, affichage et compteurs ; anciens fichiers sans date décodés par les tests. Le serveur garde l’autorité sur le lancement. |
| 7. Arrêt du détecteur à la déconnexion | Fait | Fait : `mac/Integrations.swift:229`, arrêt puis suppression du détecteur. |
| 8. Création de session bornée | Partiel | Fait après correction : `mac/LiveTranscription.swift:263` et `:311`. Le test a reproduit l’ouverture d’un socket après fin de l’audio pendant la requête de création ; le contrôle après cette requête empêche maintenant cette ouverture. Trois tentatives maximales, refus de clé et annulation couverts en simulé. |
| 9. Direct sur une seule piste | Fait | Fait : `mac/LiveTranscriptPanel.swift:14` et état agrégé du direct ; quota d’une session simulé, texte conservé et transcription incomplète. |

Autres contrôles de régression : les réponses de fermeture immédiate, après échec de l’arrêt et après timeout sont vérifiées en simulé. Le délai est réduit à 0,1 s **dans le test uniquement**, contre 30 s dans l’app. Le filtre d’écho est identique à `HEAD`, `mac/build.sh` est inchangé et le démarrage expiré de l’audio système reste un abandon suivi d’un nouvel essai manuel, sans repli silencieux vers le micro. Les correctifs antérieurs de ⌘Q, de connexion en cours d’enregistrement, de conservation du texte lors d’une transcription échouée, du plan lancé et de fermeture des fichiers audio sont conservés.

### Compléments de préparation de livraison

| Correctif | État et preuve |
|---|---|
| GET du résultat Gladia repris sur erreur réseau, 5xx ou 429 | Fait : `mac/Gladia.swift:120`, deux nouvelles tentatives au maximum sur l’ensemble du suivi ; 401 et quota restent terminaux. Les tests vérifient un seul POST de transcription et un seul upload. |
| Textes neutres pour 429 et crédits Gladia insuffisants | Fait : `mac/Gladia.swift:18`, aucun code HTTP brut pour ces cas ; le même texte sert au direct. Un 429 ne présume pas sa cause, conformément aux [limites documentées par Gladia](https://docs.gladia.io/chapters/limits-and-specifications/concurrency). |
| Extrait de tâche dans la notification | Fait : `mac/TaskNotifications.swift:36`, aperçu de 240 caractères maximum avec titre et destination conservés. Affichage réel non testé. |
| Plan signé conservé après 502 ou erreur réseau | Fait : `mac/AgentWorkspace.swift:57`, même validation réutilisable ; retrait sur erreurs définitives 400/409/410/422. Tests de 502, réseau et 409 réussis. |
| État des notifications refusées | Fait : `mac/LiveAlerts.swift:11`, lecture de `getNotificationSettings`, état rafraîchi au retour au premier plan et après demande ; ligne dans le carnet et les Paramètres. Remontée du statut testée avec réponse simulée. |
| Accessibilité pour Zoom | Fait : `mac/ZoomMeetingDetector.swift:10`, demande au maximum une fois par session de l’app, déclenchée par l’activation du réglage. Aucun prompt dans la boucle de 2 s ; état affiché dans les Paramètres. Essai réel de permission non effectué. |
| Libellé de téléchargement et exclusions Git | Fait : `README.md:182`, `mac/README.md:7` indiquent « Télécharger pour Mac ». `.DS_Store` et `/graphify-out/` sont déjà dans `.gitignore` et restent ignorés. |

### Contrôles locaux et tests simulés

Commandes exécutées sous bash le 8 novembre 2026 : `MEETIN_APP_SIGN_IDENTITY= ./mac/build.sh`, les quatre compilations et exécutions de fumée du [guide Mac](../mac/README.md), puis `bash mac/tests/meeting-flow-smoke.sh`. Toutes réussies après correction du défaut reproduit ci-dessus. `git diff --check`, `node --check web/lib/i18n.mjs` et `bash -n mac/tests/meeting-flow-smoke.sh` réussis. Aucun accès au trousseau dans les tests : clés et notifications sont remplacées par des doubles de test, audio synthétique et historique temporaire.

Fins des sorties sur le code final :

```text
Mix, horodatage, pistes séparées, silence et refus de clé vérifiés avec Gladia simulé.
Polling Gladia : réseau, 5xx, 429 repris ; 401 et quota terminaux ; budget borné ; aucun POST répété.
MeetingStore : tests réussis
Détection de tâches : tests réussis
Transcription en direct : tests réussis
Session : destinations, verrouillage et conservation après arrêt en erreur vérifiés en simulé.
Validation : plan signé conservé sur 502 et coupure réseau, retiré sur 409.
Fermeture : réponse immédiate, arrêt en erreur et timeout vérifiés (délai réduit à 0,1 s dans le test).
```

Construction : `./mac/package.sh --beta mac/.build/Meetin-OS-0.1.6.pkg`, sortie 0. Extraction temporaire avec `pkgutil --expand-full`, version et architectures avec `lipo`, signature de l’app vérifiée, adresses comptées séparément dans chaque architecture. Le paquet reconstruit a été installé et essayé en réel par Wael, comme indiqué ci-dessous ; aucun nouveau build n’est effectué pour la publication. Le lancement de 8 s consigné auparavant concernait un paquet antérieur.

### Recette réelle du candidat

Le 8 novembre 2026, Wael a communiqué les résultats réels suivants pour le candidat de SHA-256 `dea50fb474bf1b73ee8a628e184cb49a23fe1cd3f171e3ce162761a6a1b63aa6`. Résultats déclarés par Wael, distincts des tests simulés ci-dessus.

| Étape à réaliser par Wael | Réponse / résultat réel |
|---|---|
| a. Installer le paquet avec « Ouvrir quand même ». | PASS, essai réel déclaré par Wael le 8 novembre 2026. |
| b. Enregistrer 30 s avec l’audio de l’appel et vérifier le texte en direct. | PASS, essai réel déclaré par Wael le 8 novembre 2026. |
| c. Cliquer sur Arrêter et retrouver la réunion dans Réunions. | PASS, essai réel déclaré par Wael le 8 novembre 2026. |
| d. Enregistrer à nouveau, écrire une note, quitter avec ⌘Q, relancer et retrouver la réunion et la note. | PASS, essai réel déclaré par Wael le 8 novembre 2026. |
| e. Connecter l’agent pendant l’enregistrement et vérifier qu’une carte apparaît. | NON TESTÉ, confirmé par Wael le 8 novembre 2026. |
| f. Confirmer une carte Devin sur le dépôt de test uniquement. | NON TESTÉ, confirmé par Wael le 8 novembre 2026. |

Restent également non vérifiés en réel : changement de périphérique audio, affichage et clics des notifications, octroi des permissions et détection Zoom, rendu des nouveaux états et code d’accès de démo hébergé. Les rôles des sites et leur configuration ont été communiqués par Wael après vérification en lecture seule par l’équipe firmirsa, voir ci-dessous. Le compte `fraawdrinn` accessible depuis le navigateur agents de Wael ne voit pas ces projets ; aucune administration Vercel n’est effectuée depuis ce compte.

### Publication autorisée, contrôles avant commit et déploiement

Périmètre approuvé et précisé par Wael le 8 novembre 2026 : copier le candidat testé vers `web/public/downloads/Meetin-OS.pkg`, créer la branche `codex/release-readiness-0.1.6`, committer uniquement les 34 fichiers ci-dessous et pousser cette branche sur `origin`. Aucune fusion dans `main`, aucun changement de la release GitHub `v0.1.0-beta`. Le paquet local de `mac/.build/` reste ignoré ; aucun enregistrement, clé, dossier Graphify, stash ni fichier `.DS_Store` n’est inclus.

Configuration Vercel rapportée par Wael, vérification de l’équipe firmirsa en lecture seule :

- `meetin-os` est relié à `Firmirsa/Meetin-OS`, branche de production `main`, déploiement automatique à chaque push sur `main`.
- Production actuelle à conserver pour rollback : `dpl_uaU4uenwDdeJ3AH34V91h5w1zche`, source `816b3f0`.
- `meetin-os-recette` n’est pas relié à Git, reçoit des déploiements manuels et héberge les essais YouTube de Lenny. **Aucune publication sur ce projet.**
- Les deux sites servaient encore le paquet ancien de SHA-256 `dc68834f562f102b90ab9028c0f988d5c6462e488e625fc4411ef81a0debcbcf` lors de ce contrôle rapporté.

Risque identifié : publier une branche sans changer la branche de production ferait rétablir l’ancien paquet au prochain push sur `main`. Correctif de configuration retenu par Wael : après le push, **Lenny** passe `meetin-os → Settings → Git → Production Branch` de `main` à `codex/release-readiness-0.1.6`, puis redéploie cette branche. Tant que ce réglage reste actif, les pushes sur `main` ne vont plus en production. Remettre `main` seulement après une fusion ultérieure, qui n’est pas autorisée par cette livraison.

Rollback prévu : remettre en production `dpl_uaU4uenwDdeJ3AH34V91h5w1zche` et rétablir la branche de production sur `main`. Aucun changement de branche Vercel ni redéploiement n’a encore été confirmé à cet agent.

Liste exhaustive proposée (34 fichiers, dont le paquet public à remplacer seulement après accord) :

```text
.gitignore
README.md
docs/suivi.md
mac/AgentClient.swift
mac/AgentWorkspace.swift
mac/Capture.swift
mac/Gladia.swift
mac/HomeView.swift
mac/Info.plist
mac/Integrations.swift
mac/LiveAlerts.swift
mac/LiveTranscriptPanel.swift
mac/LiveTranscription.swift
mac/MainWindow.swift
mac/MeetinOS.swift
mac/MeetinSite.swift
mac/MeetingFlow.swift
mac/MeetingStore.swift
mac/MeetingsView.swift
mac/ProposalCards.swift
mac/README.md
mac/SettingsPages.swift
mac/Sidebar.swift
mac/TaskDetection.swift
mac/TaskNotifications.swift
mac/ZoomMeetingDetector.swift
mac/tests/GladiaSmoke.swift
mac/tests/LiveTranscriptionSmoke.swift
mac/tests/MeetingFlowSmoke.swift
mac/tests/MeetingStoreSmoke.swift
mac/tests/TaskDetectionSmoke.swift
mac/tests/meeting-flow-smoke.sh
web/lib/i18n.mjs
web/public/downloads/Meetin-OS.pkg
```

Après le redéploiement par Lenny : vérifier sur **`meetin-os.vercel.app` uniquement** que l’ETag du téléchargement correspond au MD5 local `cdee25b459628a97f9cd64db3a07fd19`, puis consigner commit, environnement, heure et résultat. Si l’ETag n’est pas un MD5, télécharger le fichier et comparer son SHA-256 au candidat testé. Vérifier également `/telecharger` en français et en anglais. Ces vérifications publiques et la consignation du commit et de l’ID de production restent à faire après confirmation du redéploiement. La release GitHub `v0.1.0-beta` reste inchangée ; la marquer remplacée demanderait une autorisation distincte.

## Livraison Windows 0.1.1, 8 novembre 2026

Paquet issu du run Windows 42471110020, source e53e98b101d55fe5f43ea8187ef2fdbe9f6d858e. ZIP fourni par Wael, SHA-256 identique au digest de l’artefact GitHub : 3d65c79398adb4aabfaa4baeaf6fdd9a92168ca4246e5d9e50aa585e02c4cf93. Installateur : 234602 octets, version embarquée 0.1.1, SHA-256 6b30d7264731f47f9cef9bd67ef234a2b0c1dda0b0db9f7477bdfcb37d5d872c. Installation, lancement et désinstallation validés sur runner ; capture réelle sur PC non testée. Version de test non signée, sans parité des fonctionnalités Mac. Publication demandée explicitement par Wael. Bouton FR/EN vers le fichier versionné, ancien chemin conservé avec le même paquet et manifeste public pour traçabilité. Aucun changement Mac, Linux ni serveur. Contrôle du site public à réaliser après déploiement.
