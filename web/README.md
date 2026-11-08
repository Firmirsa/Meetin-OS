# Site Meetin-OS

Le site Next.js sert les téléchargements à `/telecharger` et les premiers pas à `/onboarding`. L’app Mac utilise `/api/agent-access` pour vérifier sa session Google et lire l’état de la configuration, puis `/api/agent-prepare` et `/api/agent-execute` pour préparer et lancer une tâche. Depuis ce dossier, lance `npm ci`, copie `.env.example` vers `.env.local`, puis lance `npm run dev`. Génère `MEETIN_DEMO_TOKEN` avec `openssl rand -hex 32` pour protéger la route Linkup historique.

## Comptes, transcription et abonnement Mac

### Supabase

1. Ouvre le [SQL Editor du projet de Lenny](https://supabase.com/dashboard/project/lqqkgyvwilltwgkxlirb/sql/new). Vérifie le projet et exécute `select to_regclass('vault.decrypted_secrets'), to_regclass('meetin_private.quota_plans');`. La vue Vault doit exister et la table des quotas doit être absente pour une première application. Si la table existe déjà, vérifie l’état en base avant de relancer le SQL.
2. Pour une première application, colle la [migration des comptes et quotas](../supabase/migrations/20261107190000_meetin_accounts_and_quota.sql) dans une nouvelle requête, entre `begin;` et `commit;`, et exécute le tout. Vérifie avec `select code, monthly_ms / 60000 as minutes from meetin_private.quota_plans order by code;` : `free` doit afficher 15 et `premium` 300. Cette requête ne lit aucun secret.
3. Configure un client OAuth Google de type **Application Web**. Dans Google Cloud, ajoute l’URL de retour `https://lqqkgyvwilltwgkxlirb.supabase.co/auth/v1/callback`. Dans Supabase **Authentication → Providers**, active Google avec le client ID et le secret, puis désactive la connexion par e-mail et les autres fournisseurs pour ce projet. Dans **Authentication → URL Configuration**, ajoute l’URL de retour exacte `meetinos-oauth://callback`. Si Google est en mode test, ajoute l’adresse du testeur dans Google Cloud. [Configurer Google avec Supabase](https://supabase.com/docs/guides/auth/social-sign-in/auth-google)
4. Dans [Supabase Vault](https://supabase.com/docs/guides/database/vault), vérifie l’entrée `gladia_api_key`. Les entrées `hai_api_key` et `devin_api_key` servent à l’agent. Les variables serveur `GLADIA_API_KEY`, `HAI_API_KEY` et `DEVIN_API_KEY` restent possibles et priment sur le Vault.

### Vercel

Pour la recette de Mac 0.1.5, déploie la branche `codex/google-onboarding`, avec `web` comme dossier racine. Choisis une URL HTTPS stable et affecte les variables à ce déploiement, puis redéploie. Le Mac et Stripe doivent pouvoir joindre l’API à cette adresse sans passer par l’écran de connexion Vercel. Si la Preview est protégée, utilise une [exception limitée à son domaine de test](https://vercel.com/changelog/protect-production-deployments-for-free-on-every-plan) ou un projet de test dédié.

| Variable serveur | Valeur pour la recette |
|---|---|
| `SUPABASE_URL` | `https://lqqkgyvwilltwgkxlirb.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | Clé publique du projet Supabase |
| `SUPABASE_SECRET_KEY` | Clé secrète du projet, ou ancienne clé `service_role` |
| `MEETIN_WEB_URL` | `https://<domaine-de-test>` |
| `MEETIN_GLADIA_LIVE_URL` | `wss://<domaine-de-test>/api/gladia-live`, même domaine que le site |
| `STRIPE_SECRET_KEY` | Clé Stripe de test, requise pour tester Premium |
| `STRIPE_PRICE_ID` | ID `price_…` du tarif récurrent de test |
| `STRIPE_WEBHOOK_SECRET` | Secret `whsec_…` de la destination Stripe de test |

Utilise [Fluid Compute pour le WebSocket](https://vercel.com/kb/guide/real-time-chat-websockets). Garde les clés dans les variables serveur du déploiement, sans préfixe `NEXT_PUBLIC_`. Pour une recette locale, le direct se lance avec `npm run live:local` dans un second terminal et `ws://localhost:3001/api/gladia-live`.

### Stripe en mode test

Crée un produit **Premium** avec un tarif récurrent dans le même environnement de test que la clé Stripe. Dans **Workbench → Webhooks**, ajoute `https://<domaine-de-test>/api/stripe-webhook` pour `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `customer.subscription.paused` et `customer.subscription.resumed`. Copie son secret de signature dans la variable serveur. Active le portail client Stripe si tu veux tester **Gérer l’abonnement**. [Webhooks Stripe Billing](https://docs.stripe.com/billing/subscriptions/webhooks)

### Vérifier le parcours sur Mac

1. Compile Mac 0.1.5 avec `MEETIN_WEB_URL` pointant vers le domaine de test. L’écran d’accueil propose **Se connecter avec Google**. Après le retour de Google dans l’app, vérifie le plan Gratuit et ses 15 min dans **Compte**. Stripe peut être configuré après ce premier contrôle.
2. Lance un vrai appel court avec l’accord des deux participants. Avec des écouteurs, faites parler les deux personnes à tour de rôle. Dans la fenêtre de réunion, vérifie une phrase en direct sous **Micro** et une sous **Audio de l’appel**. Arrête, vérifie que le texte est dans la réunion et actualise le solde dans **Compte**.
3. Depuis **Compte**, lance **Passer à Premium** avec un [moyen de paiement Stripe de test](https://docs.stripe.com/testing). Vérifie la réponse `2xx` dans les livraisons Stripe, puis actualise **Compte**. Le plan doit afficher Premium et le plafond de 300 min, en conservant le débit du premier appel.

**Gratuit : 15 min audio par mois. Premium : 300 min.** Le compteur repart le premier du mois à 00 h UTC. Le serveur mesure l’audio envoyé : une minute de micro et une minute de son de l’appel comptent pour deux minutes. Le direct et la transcription après l’appel partagent le quota. Les volumes se règlent en base dans `meetin_private.quota_plans`. En cas de quota épuisé, le carnet et la capture locale restent accessibles.

Le site sert à installer l’app et à ouvrir **Compte** ou **Intégrations**. La première connexion Google se fait depuis l’accueil Mac. **Compte** affiche le solde et ouvre Stripe Checkout.

## Intégrations de l’agent

- **Holo** utilise la clé H et, facultativement, `HAI_MODEL` pour préparer une tâche depuis une demande ou un extrait. Il pose une question si le résultat ou la cible est ambigu. La préparation n’ouvre aucune session d’exécution.
- **Linkup** utilise `LINKUP_API_KEY` pour répondre à une question publique avec des liens vers les sources. Cette route serveur reste disponible pour un futur branchement dans l’app.
- **Devin** traite les tâches de code sans interface tierce. Configure `DEVIN_ORG_ID`, la clé d’un utilisateur de service v3 et `DEVIN_REPO`. Restreins les accès Git du compte de service à ce dépôt. Le lien de session permet de suivre le travail et de retrouver la PR éventuelle.
- **H Computer Use** crée ou modifie une fiche dans le tableau de test HTTPS défini par `HAI_COMPUTER_USE_URL`. Pour Trello, `HAI_BROWSER_PROFILE_ID` doit désigner un profil H dédié, connecté au compte de test. Sans ce profil, la proposition reste disponible dans l’app et le serveur attend la configuration avant de lancer H. Après configuration, utilise **Vérifier les accès** dans **Intégrations**. L’app affiche **En cours** et appelle `/api/agent-trello-status` avec le reçu signé du lancement. Elle affiche le lien direct quand H a terminé et confirmé la relecture de la fiche sur le tableau approuvé. [Profils navigateur H](https://hub.hcompany.ai/agents-api/browser/profiles) · [Résultat d’une session H](https://hub.hcompany.ai/agents-api/sessions/retrieve)

Sur Mac, la connexion Google donne accès à la transcription et à l’agent. Pour la recette locale, `npm test` exécute les intégrations avec des réponses simulées et `npm run build` compile le site.

Le bouton **Confirmer et lancer** dans l’app approuve la proposition affichée, sa destination et le contexte associé pour quinze minutes. Modifier la demande exige une nouvelle préparation. H déduplique la création de session avec l’identifiant de validation. Pour Devin, la protection contre les doubles clics fonctionne dans l’app et sur une même instance serveur. Si le lancement est incertain, vérifie la session dans le service avant de préparer une nouvelle validation.

[H Computer Use](https://github.com/hcompai/hai-agents-ts) · [API Devin](https://docs.devin.ai/api-reference/getting-started/teams-quickstart) · [Linkup Search](https://docs.linkup.so/pages/documentation/endpoints/search/reference) · [Stripe Checkout](https://docs.stripe.com/api/checkout/sessions/create)

Pour publier le site, le dossier racine Next.js est `web`. `brand-tokens.css` reprend les tokens officiels de `../brand/tokens.css` dans le périmètre du build web. En cas de changement de DA, mets les deux fichiers à jour ensemble.
