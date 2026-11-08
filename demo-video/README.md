# Vidéo démo

Matériel pour la fin de la vidéo démo : on demande à l’agent de nous faire gagner le hackathon (c’est de l’ironie).

## Site du hackathon (copie locale)

`site-hackathon/` est une copie statique de la [page publique de l’événement](https://builderbase.com/event/h-company-42ai-computer-use-agents-hackathon), avec une page **Participants** en plus.

- `index.html` et `event.css` : la page de l’événement, avec un lien « Participants » dans le menu.
- `participants.html` : une colonne de 40 équipes, avec une recherche et le choix du gagnant.
- `participants-data.js` : les équipes affichées. Elles sont toutes fictives, sauf MeetinOS (n° 1). Pour mettre nos têtes, déposer les photos dans `site-hackathon/` et remplir le champ `photo` de chaque membre de MeetinOS (par exemple `photo: 'samy.jpg'`).

## Scène « choisir le gagnant »

1. Sur la page Participants, cliquer sur la ligne MeetinOS : elle se surligne et une barre « 1st place · MeetinOS » apparaît en bas de l’écran.
2. Cliquer sur **Confirm winner** : flash blanc, puis un écran plein en bleu. Les lettres de « WINNER » tombent une à une, le nom de l’équipe arrive comme un tampon, nos têtes apparaissent, deux bandeaux défilent et des confettis partent des coins pendant que d’autres tombent en continu.
3. **Back to the teams** (visible après environ 2,5 s) referme l’écran. MeetinOS garde le badge « Winner » dans la liste.

Recharger la page remet tout à zéro pour une nouvelle prise. L’animation se joue même si l’option « réduire les animations » est activée sur l’ordinateur. Les confettis sont dans `confetti.js`.

Pour lancer le site en local :

```bash
node demo-video/serve.mjs demo-video/site-hackathon 4300
```

Puis ouvrir http://127.0.0.1:4300 dans le navigateur. Le serveur n’écoute que sur la machine locale.

Les boutons « Go to platform » mènent toujours au vrai BuilderBase. Comme sur le site d’origine, le menu disparaît sous 900 px de large.

## Clip de l’agent (11 s)

`agent-run/` produit le clip qui suit la demande vocale « fais-nous gagner le hackathon ». On y voit un enregistrement d’écran simulé : l’agent Meetin-OS ouvre le site, clique sur Participants, note les 40 équipes, hésite sur ClickOps, choisit MeetinOS et confirme la 1re place. La célébration passe ensuite en plein écran. Les textes de l’agent sont en anglais.

Deux versions, en 1920×1080, 60 i/s, avec un bruit de clic de souris à chaque clic de l’agent :

- `agent-run/out/agent-run-endcard.mp4` : 11,2 s, finit sur la carte Meetin-OS « *The jury still decides. For now. » (version retenue) ;
- `agent-run/out/agent-run-celebration.mp4` : 9,6 s, s’arrête sur la célébration.

La version retenue est versionnée dans `demo-video/agent-run-endcard.mp4`. Le dossier `out/` n’est pas suivi par Git.

Le clic est synthétisé par `sfx.mjs`. Pour utiliser un vrai son de clic, déposer un `click.wav` (PCM 16 bits) dans `agent-run/` et relancer le rendu.

Pour refaire les vidéos (Chrome installé, connexion Internet pour les polices) :

```bash
cd demo-video/agent-run
npm install
node record.mjs --draft
node record.mjs
```

`--draft` rend vite en 30 i/s et enregistre quelques images clés dans `out/` pour vérifier le cadrage. Sans option, le rendu final prend quelques minutes.

Comment ça marche :

- `index.html`, `director.css`, `director.js` : la mise en scène. Le site tourne dans une iframe, avec par-dessus le panneau de l’agent, le curseur, les cadres et les zooms. Tout dépend du temps `t`, et le minutage se règle dans l’objet `K` en haut de `director.js`.
- `time-shim.js` : une horloge virtuelle injectée dans chaque page pour filmer image par image, animations CSS et confettis compris.
- `record.mjs` : pilote Chrome avec `playwright-core`, capture chaque image, puis encode la vidéo et la piste des clics avec `ffmpeg-static`.
- `sfx.mjs` : fabrique la piste audio, avec un clic placé à l’instant exact de chaque clic de l’agent.

Pour regarder la mise en scène en temps réel : `node demo-video/serve.mjs . 4301`, puis ouvrir http://127.0.0.1:4301/demo-video/agent-run/index.html.
