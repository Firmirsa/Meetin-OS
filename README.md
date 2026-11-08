# Meetin-OS

**De l’appel à la tâche validée.**

Meetin-OS est un carnet de réunion pour Mac et Windows. Il enregistre le micro et l’audio système pendant l’appel, permet de prendre des notes et affiche une transcription horodatée. Sur Mac, la transcription s’écrit en direct et Meetin-OS repère les engagements pris pendant l’appel : chaque tâche arrive en carte avec l’extrait qui la justifie, et ne part chez l’agent qu’après validation humaine.

Développé par **Wael, Lenny et Samy** pour le **H Company × 42AI Computer Use Agents Hackathon**, les 7 et 8 novembre 2026 à Paris.

**Équipe** · Wael, app Mac et intégration technique · Lenny, branding · Samy, front-end.

## Lancer le prototype Mac

**Prérequis** · macOS 15 ou ultérieur et une clé API Gladia pour la transcription.

Depuis le site, clique sur **Installer sur Mac**, ouvre `Meetin-OS.pkg` et confirme. L’assistant macOS ajoute Meetin-OS à **Applications**. La version du site est un paquet de test sans notarisation Apple.

Pour compiler depuis les sources, utilise Xcode :

```bash
git clone https://github.com/Firmirsa/Meetin-OS.git
cd Meetin-OS
./mac/build.sh
open mac/.build/Meetin-OS.app
```

Le script compile et signe l’application localement. À la première capture, macOS peut demander l’accès au micro et à l’audio du système. Les **Réglages** de Meetin-OS ouvrent directement les panneaux concernés.

1. Clique sur **Enregistrer**, puis prends tes notes dans le carnet pendant l’appel.
2. Clique sur **Arrêter**, puis sur **Écouter** pour vérifier l’enregistrement. **Voir les pistes** permet d’inspecter séparément le micro et le son du Mac.
3. Clique sur **Transcrire**. Si une clé Gladia est nécessaire, l’app te la demande à ce moment. Elle affiche ensuite les passages horodatés et permet de copier le texte.

Avec une clé Gladia et l’option activée dans **Paramètres**, le texte s’écrit aussi en direct pendant l’appel. Les réunions sont gardées dans l’historique local (**Réunions**).

Le [guide macOS](mac/README.md) détaille les permissions, les fichiers audio, la transcription en direct et la configuration de Gladia.

## Lancer le prototype Windows

Sur Windows 10 ou 11 (x64), clique sur **Installer sur Windows** depuis le site, puis ouvre `Meetin-OS-Windows.exe`. L’assistant installe le carnet pour ton compte et crée le raccourci **Meetin-OS** dans Démarrer. La version de test n’est pas signée, et Windows peut afficher une alerte avant l’installation.

**La version Windows 0.1.1 est un prototype plus simple que l’app Mac.** Elle enregistre le micro et le son de l’appel, puis transcrit avec Gladia. Elle n’a pas encore l’onglet **Agent** ni les tâches proposées, ni la transcription en direct ou l’historique des réunions, et garde l’apparence standard de Windows. La clé Gladia reste en mémoire pendant la session seulement. L’installation est vérifiée sur un runner GitHub Actions ; la capture réelle sur un PC reste à tester. Pour le parcours complet, utilise l’app Mac.

Le [guide Windows](windows/README.md) décrit la capture des deux pistes et le test à faire sur un appel.

## De la réunion à la tâche

**Pendant l’appel, sur Mac.** Quand la transcription en direct tourne et que l’agent est connecté, le texte part chez Holo (H Company) toutes les 15 secondes s’il a changé. Les tâches détectées arrivent en cartes dans l’onglet **Agent**, avec la citation exacte qui les justifie, et une notification macOS s’affiche. Si quelqu’un se corrige (« finalement, Karim le fait mardi »), la carte est mise à jour au lieu d’être dupliquée. Rien ne part sans un clic sur **Confirmer et lancer**.

**Après l’appel, ou pour une demande précise :**

1. Enregistre la réunion dans le carnet Mac et lance **Transcrire**. Pour une capture native, Gladia traite les pistes micro et audio de l’appel séparément et l’app remet les passages dans l’ordre.
2. Dans l’onglet **Agent** de l’app Mac, sélectionne un extrait de la transcription ou saisis une demande. Clique sur **Préparer la tâche**. Holo propose une action ou pose une question s’il lui manque un détail.
3. Relis la tâche, sa destination et le contexte, puis clique sur **Confirmer et lancer**. Devin traite le travail de code et ouvre une pull request à relire ; H Computer Use agit dans le tableau de test configuré (une seule création ou modification de fiche). L’app affiche le lien de suivi de la session.

Une validation reste valable 15 minutes. Passé ce délai, ou si la tâche a changé, il faut la préparer à nouveau.

Le site sert à télécharger l’app et à l’installer. Sa page **Premiers pas** inclut le parcours d’abonnement de démonstration via Stripe Checkout en mode test.

## Lancer le site Next.js

```bash
cd web
npm ci
cp .env.example .env.local
npm run dev
```

Le téléchargement est disponible sur [localhost:3000/telecharger](http://localhost:3000/telecharger) et les premiers pas sur [localhost:3000/onboarding](http://localhost:3000/onboarding). Le carnet et l’enregistrement sont accessibles sans compte. Pour utiliser l’agent sur Mac, configure les intégrations côté serveur puis saisis le code de l’équipe dans **Intégrations → Connecter l’agent**.

## Où en est le projet

État au 8 novembre 2026. Le détail de chaque test est dans le [suivi](docs/suivi.md).

| Brique | Recette |
|---|---|
| **Mac** | Essai réel le 7 novembre : enregistrement deux pistes pendant un vrai appel, arrêt, réunion dans l’historique, relance de l’app. |
| **Gladia** | Sur un vrai appel, passages horodatés sur les deux pistes. Transcription en direct testée en réel sur macOS 27.2 : texte affiché pendant l’enregistrement, sans ligne en double. Le repère de la voix distante reste à confirmer. |
| **Détection de tâches** | Essai réel avec Gladia et Holo sur un serveur local : tâche détectée en moins de 30 s, carte, compteur et notification affichés. Les boutons de la notification n’ont pas encore été cliqués en réel. |
| **Devin** | Essai réel : un clic sur **Confirmer et lancer** depuis une carte a créé une session Devin et ouvert une pull request de test. |
| **H Computer Use** | Essai réel dans HoloTab, en mode supervisé : création d’une fiche dans le tableau Trello de démo, vérifiée dans Trello. Le même lancement depuis l’app Mac reste à rejouer avec le profil H relié au tableau. |
| **Windows** | Installation, raccourci et ouverture du carnet vérifiés sur un runner GitHub Actions. Gladia testé avec des réponses simulées ; capture réelle sur un PC non testée. |
| **Stripe** | Parcours d’abonnement de démonstration sur la page **Premiers pas**, en mode test. |

## En relecture

Ces pull requests ne sont pas encore fusionnées dans `main`. Celles marquées « Mac » contiennent du Swift préparé sur un PC Windows : elles doivent être compilées et testées sur un Mac avant la fusion.

| PR | Changement |
|---|---|
| [#4](https://github.com/Firmirsa/Meetin-OS/pull/4) | Clip de fin de la vidéo démo et copie locale du site du hackathon (`demo-video/`). |
| [#5](https://github.com/Firmirsa/Meetin-OS/pull/5) | Mac et Windows : le nom de l’utilisateur remplace « Micro » dans la transcription. |
| [#6](https://github.com/Firmirsa/Meetin-OS/pull/6) | Mac : renommer et supprimer une réunion, avec confirmation et passage par la Corbeille. |
| [#7](https://github.com/Firmirsa/Meetin-OS/pull/7) | Site : Linux présenté comme plateforme disponible. |
| [#8](https://github.com/Firmirsa/Meetin-OS/pull/8) | Mac : barre d’enregistrement animée qui suit la voix, avec **Arrêter** (la pause n’a pas encore d’action). |

## Documentation

- [Suivi du projet](docs/suivi.md) · État des tests et prochaines actions.
- [Guide macOS](mac/README.md) · Installation, capture et transcription.
- [Guide Windows](windows/README.md) · Installation, capture et compilation.
- [Guide Next.js](web/README.md) · Installation, premiers pas et configuration des intégrations serveur.
- [Plan d’exécution](docs/plan-hackathon.md) · Répartition et scénario.
- [Fiche du hackathon](docs/hackathon.md) · Règles, barème et ressources partenaires.
