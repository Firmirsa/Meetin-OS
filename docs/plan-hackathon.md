# Meetin-OS · Plan d’exécution

Meetin-OS transforme les engagements pris en réunion en tâches que l’équipe peut relire, valider et retrouver dans son outil de travail.

Consulter la [fiche du hackathon](hackathon.md) pour les règles, le barème et les ressources partenaires.

| Responsable | Livrable | Outils |
|---|---|---|
| Wael | App Mac et intégration de bout en bout. Valider la capture sur un vrai appel, vérifier Gladia, puis relier la transcription, la revue et l’exécution. | SwiftUI, ScreenCaptureKit et Gladia. |
| Lenny | Branding de Meetin-OS. Définir l’identité visuelle et fournir les éléments de marque pour l’interface et la démo. | Logo, palette, typographie et éléments de présentation. |
| Samy | Front-end de revue. Afficher la tâche proposée et son extrait source, permettre de corriger le responsable et l’échéance, puis afficher le résultat après validation. | Next.js et TypeScript selon le plan du projet. |

## Priorités de Wael

1. **Valider la chaîne Mac → Gladia sur un vrai appel.** Faire parler deux personnes à tour de rôle, écouter les deux voix dans le mix et vérifier les passages horodatés dans la transcription.
2. **Donner à Samy un exemple de données et le contrat d’intégration.** La proposition contient le titre, le responsable, l’échéance et l’extrait horodaté. Le front envoie les champs validés avec un identifiant de validation, puis affiche l’état de l’exécution, le lien de la fiche et les valeurs relues. Samy peut démarrer avec des données de test.
3. **Prendre en charge l’intégration H sur un seul outil cible.** Choisir un tableau de test accessible, modifier une fiche existante et relire son état. Si plusieurs fiches correspondent, demander laquelle utiliser. Vérifier qu’une nouvelle tentative ne crée pas de doublon.
4. **Répartir les intégrations restantes et préparer la recette commune.** Confirmer qui prend Linkup et la PR Stripe en mode test, éventuellement préparée avec Devin. Répéter le scénario complet avec Samy et les éléments de marque fournis par Lenny.

## Premier jalon

1. Importer un audio où l’engagement change en cours de réunion. « Léa s’en charge… finalement, Karim le fait mardi. »
2. Afficher la proposition pour Karim avec l’extrait qui la justifie, puis la valider.
3. Montrer H mettre à jour la fiche existante, la rouvrir et afficher les valeurs vérifiées.
4. Rejouer la même validation et vérifier qu’elle renvoie la même fiche sans doublon.

Intégrer Linkup et la PR Stripe après avoir fait passer ce parcours de bout en bout. L’outil cible reste à choisir selon l’espace de test auquel l’équipe a déjà accès.

## Intégrations et soumission

Pour Meetin-OS, les quatre intégrations dans le produit sont H Company, Gladia, Linkup et Stripe. Devin est envisagé pour la PR de l’abonnement. La manière dont l’usage de Devin pendant le développement est comptabilisé reste à confirmer avec les organisateurs.

**Objectif interne : soumettre dimanche 8 novembre à 13 h, heure de Paris.** La date limite officielle est à 14 h.

## À faire

- [ ] **Wael · Notification d’arrivée en réunion.** Détecter l’entrée dans un appel sur un premier outil, puis proposer « Enregistrer » ou « Ignorer », dans l’esprit de Wispr Flow ou Otter. La notification demande une action explicite avant de démarrer la capture.
- [ ] Attribuer Linkup et Stripe / Devin.
