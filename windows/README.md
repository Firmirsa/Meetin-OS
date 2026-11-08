# Meetin-OS pour Windows

Le carnet est compatible avec Windows 10 ou 11 (x64) et .NET Framework 4.8 ou ultérieur. Cette version de .NET est déjà incluse dans Windows 10 22H2 et Windows 11. [Prérequis Microsoft](https://learn.microsoft.com/fr-fr/dotnet/framework/install/on-windows-10)

1. Sur le site, clique sur **Installer sur Windows** et ouvre `Meetin-OS-Windows.exe`. L’assistant installe Meetin-OS pour ton compte, sans droits administrateur. Windows peut signaler cet installateur de test non signé.
2. Ouvre **Meetin-OS** depuis Démarrer. Pendant un appel, clique sur **Enregistrer** pour ouvrir le carnet de réunion, puis sur **Arrêter l’enregistrement** pour retrouver les pistes. La version Windows se déclenche manuellement.
3. Dans **Réglages**, saisis ta clé Gladia. **Transcrire avec Gladia** envoie les pistes disponibles et affiche les passages dans l’ordre. La clé reste en mémoire pendant la session. Tu peux aussi importer un WAV, MP3 ou M4A depuis le carnet.

La préparation et la validation de tâches sont disponibles dans l’app Mac 0.1.2. L’ancienne adresse web de l’agent redirige vers la page d’onboarding.

Windows ne demande pas l’accès au micro pour une app de bureau. Si **Autoriser l’accès au microphone sur cet appareil** ou **Autoriser les applications de bureau à accéder à votre microphone** est désactivé dans Paramètres > Confidentialité > Microphone, le carnet enregistre seulement `appel.wav`, le signale et propose d’ouvrir ces paramètres. L’appel doit utiliser le micro et la sortie audio définis par défaut dans Windows. Le son de la sortie peut inclure d’autres applications. Après un essai, **Voir les pistes** ouvre le dossier contenant `micro.wav` et `appel.wav` lorsqu’un signal a été reçu. Les enregistrements sont conservés dans `%LOCALAPPDATA%\Meetin-OS\Recordings`.

## Construire l’installateur

Depuis la racine du dépôt, avec le SDK .NET 10 et le compilateur NSIS (`makensis`) :

```sh
dotnet restore windows/Meetin-OS.csproj --locked-mode
dotnet build windows/Meetin-OS.csproj -c Release --no-restore -o windows/.build/payload
makensis windows/installer.nsi
```

Le dernier appel génère `web/public/downloads/Meetin-OS-Windows.exe`, le fichier que sert le site. Le build peut se faire sur Mac ou sur Windows : le projet fixe le runtime `win-x64`, donc `packages.lock.json` est le même sur les deux systèmes, et les chemins du script NSIS utilisent `\`, accepté par `makensis` partout. Sur Windows, [NSIS](https://nsis.sourceforge.io/Download) existe aussi en archive ZIP à dézipper sans droits administrateur. La version se change à deux endroits : `Meetin-OS.csproj` et `APP_VERSION` dans `installer.nsi`. Le workflow Windows vérifie sur un runner l’installation, le raccourci et l’ouverture du carnet.

## État des tests

- Test simulé : `dotnet run --project windows/tests/GladiaSmoke.csproj` vérifie avec un faux serveur Gladia l’envoi des deux pistes, l’ordre des passages et le rejet d’une mauvaise clé. Aucun appel réseau réel.
- Essai réel (8 novembre 2026, Windows 10 22H2, écran à 125 %) : installation de `Meetin-OS-Windows.exe` 0.1.1, ouverture du carnet, enregistrement avec une voix de synthèse dans les haut-parleurs. Avec le micro refusé par Windows, l’ancienne version s’arrêtait sur « Accès refusé (E_ACCESSDENIED) » sans rien enregistrer ; la version corrigée garde `appel.wav` et indique le réglage à activer. Micro autorisé : `micro.wav` et `appel.wav` sont écrits.
- Non vérifié en réel : la transcription Gladia depuis le carnet Windows (nécessite une clé saisie dans Réglages) et l’avertissement SmartScreen en installation interactive.

Pour la recette audio, utilise un vrai PC Windows avec deux personnes en appel. Vérifie les deux WAV séparément, puis lance Gladia et compare l’ordre des passages. [Capture audio WASAPI](https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording) · [API Gladia](https://docs.gladia.io/api-reference/v2/pre-recorded/init)
