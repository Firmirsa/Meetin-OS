# Meetin-OS pour Windows

Le carnet est compatible avec Windows 10 ou 11 (x64) et .NET Framework 4.8 ou ultérieur. Cette version de .NET est déjà incluse dans Windows 10 22H2 et Windows 11. [Prérequis Microsoft](https://learn.microsoft.com/fr-fr/dotnet/framework/install/on-windows-10)

1. Sur le site, clique sur **Installer sur Windows** et ouvre `Meetin-OS-Windows.exe`. L’assistant installe Meetin-OS pour ton compte, sans droits administrateur. Windows peut signaler cet installateur de test non signé.
2. Ouvre **Meetin-OS** depuis Démarrer. Pendant un appel, clique sur **Enregistrer** pour ouvrir le carnet de réunion, puis sur **Arrêter l’enregistrement** pour retrouver les pistes. La version Windows se déclenche manuellement.
3. Dans **Réglages**, saisis ta clé Gladia. **Transcrire avec Gladia** envoie les pistes disponibles et affiche les passages dans l’ordre. La clé reste en mémoire pendant la session. Tu peux aussi importer un WAV, MP3 ou M4A depuis le carnet.
4. Renseigne l’adresse du site dans **Réglages**. Depuis l’onglet **Agent**, copie un extrait de la transcription et ouvre l’espace web pour le relire et proposer une tâche.

L’appel doit utiliser le micro et la sortie audio définis par défaut dans Windows. Le son de la sortie peut inclure d’autres applications. Après un essai, **Voir les pistes** ouvre le dossier contenant `micro.wav` et `appel.wav` lorsqu’un signal a été reçu. Les enregistrements sont conservés dans `%LOCALAPPDATA%\Meetin-OS\Recordings`.

## Construire l’installateur

Depuis la racine du dépôt, avec le SDK .NET 10 et le compilateur NSIS (`makensis`) :

```sh
dotnet restore windows/Meetin-OS.csproj --locked-mode
dotnet build windows/Meetin-OS.csproj -c Release --no-restore -o windows/.build/payload
makensis windows/installer.nsi
```

Le dernier appel génère `web/public/downloads/Meetin-OS-Windows.exe`, le fichier que sert le site. Le build peut se faire sur Mac. Le workflow Windows vérifie sur un runner l’installation, le raccourci et l’ouverture du carnet.

Pour la recette audio, utilise un vrai PC Windows avec deux personnes en appel. Vérifie les deux WAV séparément, puis lance Gladia et compare l’ordre des passages. [Capture audio WASAPI](https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording) · [API Gladia](https://docs.gladia.io/api-reference/v2/pre-recorded/init)
