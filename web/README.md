# Site Meetin-OS

Le site Next.js sert la landing à `/` et l’espace agent à `/agent`. Depuis ce dossier, lance `npm ci`, copie `.env.example` vers `.env.local`, puis lance `npm run dev`. La landing peut être consultée sans clés. Les routes d’intégration exigent le code de démonstration, généré avec `openssl rand -hex 32`.

- **Holo** utilise `HAI_API_KEY` et, facultativement, `HAI_MODEL` pour proposer une tâche à partir de l’extrait collé. Cette étape envoie l’extrait à H Company. La proposition reste modifiable avant l’envoi explicite à Devin.
- **Linkup** utilise `LINKUP_API_KEY` pour répondre à une question publique avec des liens vers les sources.
- **Devin** utilise `DEVIN_ORG_ID`, `DEVIN_API_KEY` et `DEVIN_REPO`. L’utilisateur relit et confirme la tâche et l’extrait avant transmission. Le dépôt configuré et les limites de travail figurent dans le prompt. Dans Cognition, limiter aussi les permissions Git du compte de service au dépôt prévu et protéger la branche principale. Le lien de session donne accès au suivi et à la PR si Devin en ouvre une.
- **Stripe** utilise une clé `sk_test_` ou `rk_test_`, un `STRIPE_PRICE_ID` récurrent créé dans le même environnement de test et `MEETIN_WEB_URL` comme adresse de retour. Le site ouvre Checkout en mode abonnement et le retour s’affiche dans l’espace agent. Le statut réel se vérifie dans le tableau de bord Stripe. L’abonnement ne débloque pas de droits dans cette version.

Les clés prestataires sont configurées côté serveur. Le code de démo est saisi dans l’espace agent et n’est pas conservé après rechargement. Pour la recette locale, `npm test` exécute les intégrations avec des réponses simulées et `npm run build` compile le site.

[Linkup Search](https://docs.linkup.so/pages/documentation/endpoints/search/reference) · [API Devin](https://docs.devin.ai/api-reference/getting-started/teams-quickstart) · [Stripe Checkout](https://docs.stripe.com/api/checkout/sessions/create)

Pour publier le site, le dossier racine Next.js est `web`. `brand-tokens.css` reprend les tokens officiels de `../brand/tokens.css` dans le périmètre du build web. En cas de changement de DA, mets les deux fichiers à jour ensemble.
