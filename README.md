# Meetin-OS

**De l’appel à la tâche validée.**

Meetin-OS est un carnet de réunion pour Mac et Windows. Il enregistre le micro et l’audio système pendant l’appel, permet de prendre des notes et affiche ensuite une transcription horodatée. Le projet vise à relier chaque engagement à l’extrait qui le justifie, puis à mettre à jour la fiche correspondante après validation humaine.

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
3. Saisis ta clé Gladia dans **Réglages**, puis clique sur **Transcrire**. L’app affiche les passages horodatés et permet de copier le texte.

Le [guide macOS](mac/README.md) détaille les permissions, les fichiers audio et la configuration de Gladia.

## Lancer le prototype Windows

Sur Windows 10 ou 11 (x64), clique sur **Installer sur Windows** depuis le site, puis ouvre `Meetin-OS-Windows.exe`. L’assistant installe le carnet pour ton compte et crée le raccourci **Meetin-OS** dans Démarrer. La version de test n’est pas signée.

Le [guide Windows](windows/README.md) décrit la capture des deux pistes et le test à faire sur un appel.

## De la réunion à la tâche

1. Enregistre la réunion dans le carnet Mac et lance **Transcrire**. Pour une capture native, Gladia traite les pistes micro et audio de l’appel séparément et l’app remet les passages dans l’ordre.
2. Dans l’onglet **Agent** de l’app Mac, sélectionne un extrait de la transcription ou saisis une demande. Clique sur **Préparer la tâche**. Holo propose une action ou pose une question s’il lui manque un détail.
3. Relis la tâche, sa destination et le contexte, puis clique sur **Confirmer et lancer**. Devin traite le travail de code ; H Computer Use agit dans le tableau de test configuré. L’app affiche le lien de suivi de la session.

Le site sert à télécharger l’app et à l’installer. Sa page **Premiers pas** inclut le parcours d’abonnement de démonstration via Stripe Checkout en mode test.

## Lancer le site Next.js

```bash
cd web
npm ci
cp .env.example .env.local
npm run dev
```

Le téléchargement est disponible sur [localhost:3000](http://localhost:3000/) et les premiers pas sur [localhost:3000/onboarding](http://localhost:3000/onboarding). Pour tester l’agent Mac, configure les intégrations côté serveur, puis saisis l’adresse du site et le code d’accès de l’équipe dans les réglages de l’app.

| Brique | Recette |
|---|---|
| **Mac** | Accès au micro et à l’audio du système, deux pistes et export vérifiés avec un son de test sur macOS 26.5.2. |
| **Gladia** | Sur un vrai appel le 7 novembre, Gladia a renvoyé des passages horodatés sur les deux pistes. Le repère du micro est reconnu ; celui de la voix distante reste à confirmer. |
| **Agent Mac** | Préparation, clarification, confirmation et réponse des routes de session testées avec des prestataires simulés. La recette réelle de Devin et H Computer Use reste à faire avec les accès de l’équipe. |

## Documentation

- [Suivi du projet](docs/suivi.md) · État des tests et prochaines actions.
- [Guide macOS](mac/README.md) · Installation, capture et transcription.
- [Guide Windows](windows/README.md) · Installation, capture et compilation.
- [Guide Next.js](web/README.md) · Installation, premiers pas et configuration des intégrations serveur.
- [Plan d’exécution](docs/plan-hackathon.md) · Répartition et scénario.
- [Fiche du hackathon](docs/hackathon.md) · Règles, barème et ressources partenaires.
