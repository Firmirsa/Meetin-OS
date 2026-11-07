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
2. Dans l’onglet **Agent**, ouvre l’espace web et colle un extrait de la transcription. Holo peut proposer une tâche de code et sa citation source. La tâche reste modifiable avant confirmation.
3. Si une recherche publique aide à cadrer la tâche, lance-la avec Linkup et ouvre les sources renvoyées.
4. Relis la tâche et l’extrait avant de les envoyer à Devin. L’espace agent donne ensuite le lien de la session pour suivre le travail et examiner la PR éventuelle.
5. Le parcours d’abonnement de démonstration s’ouvre dans Stripe Checkout en mode test. Les droits d’accès et le suivi des abonnements restent à intégrer.

## Lancer le site Next.js

```bash
cd web
npm ci
cp .env.example .env.local
npm run dev
```

La landing est disponible sur [localhost:3000](http://localhost:3000/) et l’espace agent sur [localhost:3000/agent](http://localhost:3000/agent). Remplis le fichier local de configuration pour activer les intégrations. Dans l’app Mac, l’adresse du site se règle dans la roue dentée.

| Brique | Recette |
|---|---|
| **Mac** | Accès au micro et à l’audio du système, deux pistes et export vérifiés avec un son de test sur macOS 26.5.2. |
| **Gladia** | Un extrait mixé a été transcrit lors d’un essai antérieur. Le nouveau traitement séparé a été vérifié avec des réponses simulées et reste à rejouer sur un vrai appel. |
| **Holo, Linkup, Devin, Stripe** | Routes serveur et parcours de démo implémentés. Les appels prestataires restent à vérifier avec les clés de l’équipe. |

## Documentation

- [Suivi du projet](docs/suivi.md) · État des tests et prochaines actions.
- [Guide macOS](mac/README.md) · Installation, capture et transcription.
- [Guide Windows](windows/README.md) · Installation, capture et compilation.
- [Guide Next.js](web/README.md) · Configuration des clés serveur, tests et espace agent.
- [Plan d’exécution](docs/plan-hackathon.md) · Répartition et scénario.
- [Fiche du hackathon](docs/hackathon.md) · Règles, barème et ressources partenaires.
