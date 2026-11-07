# Meetin-OS · Plan d’exécution du hackathon

Meetin-OS transforme les engagements pris en réunion en tâches que l’équipe peut relire, valider et retrouver dans son outil de travail.

| Responsable | Livrable | Outils |
|---|---|---|
| Wael | Importer un audio court, extraire les engagements et afficher l’extrait source. L’utilisateur peut corriger le responsable ou l’échéance avant validation. | Gladia pour la transcription horodatée, Holo pour structurer les engagements, Next.js et TypeScript pour l’écran de revue. |
| Lenny | Retrouver la fiche existante dans un tableau de test, appliquer la mise à jour validée, puis rouvrir la fiche et renvoyer les valeurs relues. | H Company Agents API pour piloter le navigateur. Linkup pour joindre une source publique utile lorsqu’une tâche le demande. |
| Devin, piloté par Wael | Préparer une PR séparée pour l’abonnement de test et l’activation de l’accès dans l’app. Wael vérifie le parcours et intègre la PR. | Cognition / Devin et Stripe Checkout en mode test. |

## Contrat entre les deux lots

Wael transmet l’identifiant de la validation, le titre de la tâche, son responsable, son échéance et l’extrait horodaté. Lenny renvoie l’état de l’exécution, le lien de la fiche et les valeurs relues. Si plusieurs fiches correspondent, l’agent demande laquelle utiliser. Lenny peut démarrer avec une tâche saisie à la main pendant que Wael branche Gladia.

## Premier jalon

1. Importer un audio où l’engagement change en cours de réunion. « Léa s’en charge… finalement, Karim le fait mardi. »
2. Afficher la proposition pour Karim avec l’extrait qui la justifie, puis la valider.
3. Montrer H mettre à jour la fiche existante, la rouvrir et afficher les valeurs vérifiées.
4. Rejouer la même validation et vérifier qu’elle renvoie la même fiche sans doublon.

Intégrer Linkup et la PR Stripe après avoir fait passer ce parcours de bout en bout. L’outil cible reste à choisir selon l’espace de test auquel l’équipe a déjà accès.
