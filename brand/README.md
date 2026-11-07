# Meetin-OS · Marque

Direction : crème, encre, **un seul accent citron vert**. Titres en serif éditorial, interface en sans. Calme et éditorial (esprit Wispr Flow), avec une touche **carnet** (esprit Granola) : ce que tu écris est en encre, ce que l'IA ajoute est en encre secondaire, l'accord se marque au surligneur.

## Palette

| Rôle | Clair | Sombre |
|---|---|---|
| Canvas | `#FAF8F1` | `#0F1613` |
| Surface | `#EDE9DA` | `#18211D` |
| Encre | `#14201C` | `#F3F1E6` |
| Encre secondaire | `#5E675F` | `#A3ADA5` |
| Accent (fond) | `#CFE86B` | `#CFE86B` |
| Teinte douce | `#EEF3C7` | `#CFE86B` à 14 % |
| Texte sur accent | `#14201C` | `#14201C` |
| Texte d'accent | `#5C6B0F` | `#CFE86B` |
| Enregistrement | `#C8341C` | `#FF6A4D` |
| Teinte enregistrement | `#FBEAE6` | `#FF6A4D` à 16 % |

## Règles

1. **Le citron vert est un fond.** Bouton, pastille, surlignage. Jamais un texte ni une icône sur clair (1,28:1). Pour un lien ou une icône d'accent sur clair : `#5C6B0F` (5,5:1).
2. **Un seul bouton citron vert par écran** : « Valider ». Les autres actions sont en contour. Dans la barre d'enregistrement, « Arrêter » est crème plein. La notification « tu es en appel » est une fenêtre à part : son « Enregistrer » est citron vert.
3. **Rouge réservé à l'enregistrement** (point, pastille REC, erreur d'étape).
4. **Pas d'ombres.** Profondeur = couches de crème et traits fins.
5. **Rayons** : champs 8, boutons 12, cartes 16, pastilles arrondies.
6. **Typo** : EB Garamond (titres), Figtree (interface), mono pour les horodatages. Pas de troisième police.
7. **Voix** : phrases courtes, sentence case, verbes d'action.
8. **Surligneur** : forme volontairement irrégulière (rayons inégaux), comme un coup de feutre. C'est notre « imperfection humaine ».

Contrastes (WCAG) : encre/canvas 15,8 · encre/citron 12,3 · secondaire/canvas 5,5 · secondaire/teinte 5,1 · olive/teinte 5,1 · rec/teinte claire 4,5 · rec sombre/teinte 4,6 · citron/canvas sombre 13,5 · crème/barre REC 15,8 · point rouge/barre REC 5,9.

## Fichiers

- `tokens.css` · variables clair/sombre + classes de base. Pour Samy.
- `components/components.css` · carte de revue, suivi de l'agent (avant → après), barre REC, notification. Dépend de `tokens.css`.
- `components/preview.html` · page de démo à ouvrir dans un navigateur. `?theme=dark`, `?state=done`.
- `MeetinTheme.swift` · couleurs dynamiques, polices, boutons, carte. Pour Wael.
- `MeetinComponents.swift` · `MTReviewCard`, `MTAgentTimeline`, `MTRecordingBar`, `MTMeetingToast`, `MTHighlight`, `MTPill`. Syntaxe vérifiée, **non compilé** (pas de Swift côté marque) : tester dans Xcode (`#Preview` inclus).
- `logo/app-icon.svg` / `app-icon-1024.png` · logo : tuile encre, guillemets crème qui convergent, point citron vert. Le nom s'écrit en texte, jamais en logo.

## Idée de marque

Deux voix, un point. Le citron vert est le surligneur : il marque le moment où l'accord se fait. Une seule pastille par visuel.

Zone de protection : un tiers de la largeur du symbole. Taille minimale : 16 px. En une couleur, remplacer le point citron vert par de l'encre.
