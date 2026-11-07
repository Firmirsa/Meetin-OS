# Sons d'enregistrement

- `rec-start` : deux notes montantes (mi5, la5). Environ 0,7 s.
- `rec-stop` : trois notes descendantes (la5, mi5, mi4). Environ 0,95 s, plus grave et plus long : on entend que c'est fini.
- `.caf` pour l'app Mac (ajouter au projet Xcode, cible incluse), `.wav` pour la vidéo et le web.

## Pour Wael

- **Début** : jouer `rec-start`, attendre environ 0,5 s, puis lancer la capture audio. Sinon le son entre dans la transcription.
- **Fin** : arrêter la capture, puis jouer `rec-stop`.
- Aucun autre son pendant un appel (ni carte, ni étape de l'agent).
- Réglage « Sons d'enregistrement » dans les réglages, activé par défaut.

```swift
import AVFoundation

enum MTSound {
    private static var player: AVAudioPlayer?
    static func play(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.6
        player?.play()
    }
}
// MTSound.play("rec-start") ... MTSound.play("rec-stop")
```

Snippet non compilé : à tester dans Xcode.
