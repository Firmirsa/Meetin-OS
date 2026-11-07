# Meetin-OS

**De l’appel à la tâche validée.**

Meetin-OS est un carnet de réunion pour Mac. Il enregistre le micro et l’audio système pendant l’appel, permet de prendre des notes et affiche ensuite une transcription horodatée. Le projet vise à relier chaque engagement à l’extrait qui le justifie, puis à mettre à jour la fiche correspondante après validation humaine.

Développé par **Wael, Lenny et Samy** pour le **H Company × 42AI Computer Use Agents Hackathon**, les 7 et 8 novembre 2026 à Paris.

## Lancer le prototype Mac

**Prérequis** · macOS 15 ou ultérieur, Xcode et une clé API Gladia pour la transcription.

```bash
git clone https://github.com/Firmirsa/Meetin-OS.git
cd Meetin-OS
./mac/build.sh
open mac/.build/Meetin-OS.app
```

Le script compile et signe l’application localement. À la première capture, macOS demande l’accès au micro et à l’enregistrement de l’écran et de l’audio système.

1. Clique sur **Enregistrer**, puis prends tes notes dans le carnet pendant l’appel.
2. Clique sur **Arrêter**, puis sur **Écouter** pour vérifier l’enregistrement. **Voir les pistes** permet d’inspecter séparément le micro et le son du Mac.
3. Saisis ta clé Gladia dans **Réglages de transcription**, puis clique sur **Transcrire**. L’app affiche les passages horodatés et permet de copier le texte.

Le [guide macOS](mac/README.md) détaille les permissions, les fichiers audio et la configuration de Gladia.

## État du projet

| Brique | Rôle | État |
|---|---|---|
| **App Mac** · SwiftUI et ScreenCaptureKit | Carnet, capture sur deux pistes et écoute du mix. | Prototype dans le dépôt. Interface vérifiée sur Mac et mix vérifié avec des signaux de test. |
| **Gladia** | Transcription du fichier audio, avec horodatage et séparation des voix. | Intégration dans le prototype, vérifiée avec une réponse simulée. Recette sur un vrai appel à faire. |
| **Revue des engagements** · Holo | Proposer une tâche et montrer l’extrait source avant validation. | Prévu. |
| **H Company Agents API** | Retrouver la fiche existante, appliquer la décision et vérifier le résultat dans l’interface cible. | Prévu. |
| **Linkup, Stripe et Devin** | Joindre une source publique, tester un abonnement et préparer la PR correspondante. | Prévus dans le plan du hackathon. |

Le scénario de démo part d’une décision qui change en cours d’appel. « Léa s’en charge… finalement, Karim le fait mardi. » Après validation, l’agent doit modifier la fiche existante, la rouvrir et montrer les valeurs enregistrées.

## Documentation

- [Guide macOS](mac/README.md) · Installation et recette de capture.
- [Plan d’exécution](docs/plan-hackathon.md) · Répartition, scénario et tâches à faire.
- [Fiche du hackathon](docs/hackathon.md) · Règles, barème, programme et ressources partenaires.
