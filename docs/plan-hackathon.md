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

## Cadre du concours

Le H Company × 42AI Computer Use Agents Hackathon se déroule les **7 et 8 novembre 2026**, en présentiel à **La Maison by Motier Ventures, Paris**. L’adresse exacte est communiquée aux participants acceptés. Les inscriptions sont individuelles, sur acceptation, et les équipes comptent **1 à 4 personnes**.

Le défi consiste à construire un agent qui accomplit une tâche concrète en interagissant avec une vraie interface web ou de bureau. La démo doit montrer le problème, les actions de l’agent et le résultat. Le briefing exige **au moins 4 des 5 technologies partenaires** : H Company, Gladia, Cognition / Devin, Linkup et Stripe.

Pour Meetin-OS, les quatre intégrations dans le produit sont H Company, Gladia, Linkup et Stripe. Devin intervient sur la PR de l’abonnement. La manière dont l’usage de Devin pendant le développement est comptabilisé reste à confirmer avec les organisateurs.

[Page officielle de l’événement](https://luma.com/hz9db5u9) · [Slides du kickoff, règles et barème en diapositive 14](https://docs.google.com/presentation/d/1SvCa0VS63fshnv28H5FcIJm65j5dhxrABZf0yzkAOms/preview)

## Barème du jury

| Critère | Poids |
|---|---:|
| Usage du computer use | 25 % |
| Exécution technique et fiabilité | 25 % |
| Utilité et impact | 20 % |
| Originalité et innovation | 15 % |
| UX et contrôle utilisateur | 10 % |
| Clarté de la démo et réponses aux questions | 5 % |

## Horaires et rendu

Horaires de Paris (CET). Le programme peut être ajusté par les organisateurs.

| Samedi 7 novembre | Dimanche 8 novembre |
|---|---|
| 09 h 00 · Accueil | 08 h 00 · Réouverture du lieu |
| 09 h 45 · Kickoff | 09 h 00 · Petit déjeuner |
| 10 h 30 · Début du développement | 12 h 30 · Déjeuner |
| 12 h 30 · Déjeuner | **14 h 00 · Date limite de soumission** |
| 16 h 00 · Pause | 14 h 30 · Premier tour du jury |
| 19 h 00 · Dîner | 15 h 45 · Début des pitchs finaux |
| 21 h 00 · Dernière entrée | 17 h 15 · Délibération |
| | 17 h 45 · Annonce des gagnants |
| | 18 h 00 · Networking |
| | 20 h 30 · Fermeture |

**Objectif interne : soumettre à 13 h le dimanche.** Utiliser [BuilderBase](https://builderbase.com/event/h-company-42ai-computer-use-agents-hackathon) pour retrouver les consignes de soumission. Les livrables exacts, la durée du pitch et l’acceptation d’une capture de secours restent à vérifier dans les consignes de l’événement.

## Prix et avantages

- **Podium** : 5 000 €, 3 000 € et 2 000 € par équipe. Chaque membre du podium reçoit également un mois de Morning Nomade.
- **Prix partenaires** : 1 000 € pour le meilleur usage de Devin et 1 000 € pour le meilleur usage de Gladia selon l’annonce publique. Le kickoff mentionne également 3 000 $ de crédits de transcription pour Gladia. Le cumul de ces deux annonces reste à confirmer.
- **Prix sociaux** : 500 € pour le meilleur post LinkedIn et 500 € pour le meilleur post X. La page officielle annonce 13 000 € en prix cash au total.
- **Pour les participants** : crédits API, accès à des outils partenaires, mentorat et support sur place. Morning annonce une réduction de 50 % sur les deux premiers mois de Morning Nomade, avec inscription communiquée sur place.

[Annonce officielle des prix et avantages](https://luma.com/hz9db5u9) · [Slides du kickoff, diapositive 16 pour Gladia](https://docs.google.com/presentation/d/1SvCa0VS63fshnv28H5FcIJm65j5dhxrABZf0yzkAOms/preview)

## Accès et crédits partenaires

Les montants sont ceux des offres annoncées. Vérifier les soldes après activation. Les codes sont accessibles depuis les ressources participants et les clés API restent dans les variables d’environnement.

| Partenaire | Offre annoncée | Activation et ressources |
|---|---|---|
| H Company | 100 € de crédits Agents API | Récupérer le code dans BuilderBase, puis ouvrir [Billing](https://platform.hcompany.ai/settings/billing) → **Inference credits** → **Redeem a code**. [Documentation Agents API](https://hub.hcompany.ai/agents-api/overview) · [Exemples officiels](https://github.com/hcompai/agents-api-demos) |
| Gladia | 1 000 crédits API | Récupérer le coupon dans le PDF Gladia du hackathon, puis l’appliquer dans [Gladia Billing](https://app.gladia.io/billing). |
| Linkup | 45 $ de crédits API | 20 $ à l’inscription d’un nouveau compte et 25 $ via le coupon du PDF Linkup dans le [compte Linkup](https://app.linkup.so/home). |
| Cognition / Devin | 200 $ de crédit promotionnel | Faire le check-in Luma, puis se connecter sur la [page Devin du hackathon](https://trydevin.ai/computer-use-agents-hackathon) avec l’adresse d’inscription. Appliquer le code individuel au checkout Teams ou Max et vérifier le montant final. |
| Stripe | 250 $ de crédits de participation | Réclamer l’offre via la [page Stripe du hackathon](https://stripe.com/startup-benefits/computer-use-agents-hackathon). Les crédits sont ajoutés après l’événement. Utiliser Stripe en mode test pour le MVP. |

[PDF et codes dans le portail participant BuilderBase](https://builderbase.com/track-dashboard/h-company-42ai-computer-use-agents-hackathon/resources)
