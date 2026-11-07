# Suivi Meetin-OS

Dernier point : 7 novembre 2026. La [bêta 0.1.0](https://github.com/Firmirsa/Meetin-OS/releases/tag/v0.1.0-beta) contient les installateurs Mac et Windows. Le [plan d’exécution](plan-hackathon.md) reste la référence pour la répartition et la démo.

| Sujet | État | Prochaine action |
|---|---|---|
| Mac · Wael | Le 7 novembre, Meetin-OS 0.1.1 sur macOS 26.5.2 a enregistré deux pistes pendant un vrai appel d’environ 33 s. Gladia a renvoyé des passages horodatés sur les deux pistes. Le repère du micro est reconnu ; le repère distant attendu n’apparaît pas. | Rejouer un court appel en faisant parler d’abord la personne distante pour confirmer son repère. |
| Arrivée en réunion · Mac | Meetin-OS peut ouvrir la fenêtre de réunion à l’arrivée dans Zoom si la détection est activée. | Tester la détection sur un appel Zoom et ajouter une notification macOS à l’arrivée. |
| Windows · Wael | Installation, raccourci Démarrer et ouverture du carnet vérifiés sur [GitHub Actions](https://github.com/Firmirsa/Meetin-OS/actions/runs/42378395887). Gladia testé avec des réponses simulées. | Vérifier les pistes micro et appel sur un PC, puis transcrire. |
| Revue des tâches · Samy et Wael | Front fait sur la branche `samy/revue-front`, avec un agent **simulé** (test simulé, pas d’essai réel) : page Réunion du site (`/reunions`, vérifiée dans le navigateur), onglet Engagements Windows (compilé et testé hors écran), écran après-réunion Mac (écrit, **pas encore compilé**). | Compiler le Mac avec `./mac/build.sh`, puis relier la validation à une action H sur un outil de test et vérifier le résultat. |
| Site et démo · Lenny et équipe | Téléchargements vérifiés en local. Routes Holo, Linkup, Devin et Stripe en place. | Vérifier le site déployé et répéter le parcours avec les comptes de test. |
