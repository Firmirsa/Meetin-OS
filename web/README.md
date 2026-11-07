# Site Meetin-OS

Le site Next.js sert les téléchargements à `/` et les premiers pas à `/onboarding`. L’app Mac utilise les routes serveur `/api/agent-prepare` et `/api/agent-execute`. Depuis ce dossier, lance `npm ci`, copie `.env.example` vers `.env.local`, puis lance `npm run dev`. Génère `MEETIN_DEMO_TOKEN` avec `openssl rand -hex 32` pour protéger les routes d’intégration.

- **Holo** utilise `HAI_API_KEY` et, facultativement, `HAI_MODEL` pour préparer une tâche depuis une demande ou un extrait. Il pose une question si le résultat ou la cible est ambigu. La préparation n’ouvre aucune session d’exécution.
- **Linkup** utilise `LINKUP_API_KEY` pour répondre à une question publique avec des liens vers les sources. Cette route serveur reste disponible pour un futur branchement dans l’app.
- **Devin** traite les tâches de code sans interface tierce. Configure `DEVIN_ORG_ID`, `DEVIN_API_KEY` (clé d’un utilisateur de service v3) et `DEVIN_REPO`. Restreins les accès Git du compte de service à ce dépôt. Le lien de session permet de suivre le travail et de retrouver la PR éventuelle.
- **H Computer Use** crée ou modifie une fiche dans le tableau de test HTTPS défini par `HAI_COMPUTER_USE_URL`. L’API utilise `HAI_API_KEY`. Si le tableau exige une connexion, configure `HAI_BROWSER_PROFILE_ID` avec un profil H dédié à ce tableau et limité au compte de test. Le lien mène à la session H pour voir les actions et le résultat relu.
- **Stripe** utilise une clé `sk_test_` ou `rk_test_`, un `STRIPE_PRICE_ID` récurrent créé dans le même environnement de test et `MEETIN_WEB_URL` comme adresse de retour. Le site ouvre Checkout en mode abonnement et le retour s’affiche dans les premiers pas. Le statut réel se vérifie dans le tableau de bord Stripe. L’abonnement ne débloque pas de droits dans cette version.

Les clés prestataires restent côté serveur. Saisis le code de démo dans les réglages de l’app Mac, et sur la page **Premiers pas** pour essayer Stripe Checkout. Pour la recette locale, `npm test` exécute les intégrations avec des réponses simulées et `npm run build` compile le site.

Le bouton **Confirmer et lancer** dans l’app approuve la proposition affichée, sa destination et le contexte associé pour quinze minutes. Modifier la demande exige une nouvelle préparation. H déduplique la création de session avec l’identifiant de validation. Pour Devin, la protection contre les doubles clics fonctionne dans l’app et sur une même instance serveur. Si le lancement est incertain, vérifie la session dans le service avant de préparer une nouvelle validation.

[H Computer Use](https://github.com/hcompai/hai-agents-ts) · [API Devin](https://docs.devin.ai/api-reference/getting-started/teams-quickstart) · [Linkup Search](https://docs.linkup.so/pages/documentation/endpoints/search/reference) · [Stripe Checkout](https://docs.stripe.com/api/checkout/sessions/create)

Pour publier le site, le dossier racine Next.js est `web`. `brand-tokens.css` reprend les tokens officiels de `../brand/tokens.css` dans le périmètre du build web. En cas de changement de DA, mets les deux fichiers à jour ensemble.
