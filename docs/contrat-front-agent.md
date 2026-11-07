# Contrat entre le front et l’agent

Ce contrat permet à Samy de développer la revue d’une tâche avec des données de test. Le [jeu de données](fixtures/revue-tache.json) contient une proposition, la validation et les réponses d’exécution possibles. Les URL et les personnes de la fixture sont fictives. Les noms de champs ci-dessous sont la convention proposée par Wael pour l’adaptateur `lib/contract.ts`.

```ts
type Extrait = {
  text: string;
  startMs: number;
  endMs: number;
};

type Proposition = {
  proposalId: string;
  title: string;
  assignee: string | null;
  dueDate: string | null;
  excerpt: Extrait;
};

type Validation = {
  validationId: string;
  proposalId: string;
  title: string;
  assignee: string;
  dueDate: string | null;
};

type Execution =
  | { validationId: string; status: "pending" }
  | {
      validationId: string;
      status: "verified";
      taskUrl: string;
      observed: { title: string; assignee: string; dueDate: string | null };
    }
  | {
      validationId: string;
      status: "needs_clarification" | "failed";
      message: string;
    };
```

1. **Identité de la proposition.** Le producteur attribue un `proposalId` stable. L’extrait source est associé à cet identifiant. Le front l’affiche en lecture seule et ne le renvoie pas à la validation.
2. **Champs modifiables.** Le front peut modifier le titre, le responsable et l’échéance. Le titre et le responsable sont requis à la validation. Un responsable inconnu arrive sous la forme `null` et doit être renseigné. Une échéance inconnue ou absente reste `null`.
3. **Temps.** L’échéance est une date civile `YYYY-MM-DD`, sans heure ni conversion de fuseau. Les bornes de l’extrait sont des millisecondes depuis le début de l’audio. Le front les convertit en minutes et secondes à l’affichage.
4. **Validation.** Le front crée un UUID au premier clic sur **Valider**, désactive le bouton pendant l’envoi et réutilise le même `validationId` pour une relance du même contenu. Une validation modifiée reçoit un nouvel UUID. Côté agent, une validation répétée doit retourner le même résultat sans créer de doublon.
5. **Résultat.** `pending` signifie que l’exécution est en cours. `verified` signifie que l’agent a rouvert la fiche et relu les champs affichés. Si la cible est ambiguë, le front affiche `needs_clarification` avec le message et attend une décision. `failed` affiche le motif de l’échec.
6. **Branchement.** Pour l’instant, branche les vues sur la fixture via `lib/contract.ts`. L’onglet Agent de l’app Mac prépare une tâche et attend sa confirmation avant d’ouvrir une session Devin ou H Computer Use. Le retour structuré de ce contrat reste à relier à l’interface de revue.

Pour la démo, affiche d’abord la proposition pour Karim, change éventuellement l’échéance, valide et affiche le lien de la fiche avec les valeurs relues. Utilise la variante ambiguë pour vérifier que l’interface explique le blocage.

## Détection pendant l’appel

`POST /api/agent-detect` reçoit `{ transcript, known }` : au plus 5 000 caractères de texte définitif, et au plus 10 tâches déjà trouvées (`ref`, `title`, `task` limité à 400 caractères). La réponse est `{ tasks }`, au plus 3 entrées. Chacune est un plan signé, comme `agent-prepare`, avec `replaces` : la `ref` corrigée, ou `null` pour une nouvelle tâche.

La détection n’exécute rien : seul `agent-execute`, avec `confirmed: true`, lance une tâche. Une entrée dont la citation n’est pas exacte, ou dont l’outil n’est pas configuré, est ignorée. Sans destination configurée, Holo n’est pas appelé.
