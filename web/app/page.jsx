export default function Landing() {
return <>

  <header className="shell site-header">
    <a className="brand" href="./" aria-label="Meetin-OS, accueil">
      <img src="/meetinos.svg" alt="" width="32" height="32" />
      Meetin-OS
    </a>
    <nav aria-label="Navigation principale">
      <a href="#fonctionnement">Le parcours</a>
      <a href="/reunions">Réunions</a>
      <a href="/agent">Espace agent</a>
      <a className="nav-link" href="https://github.com/Firmirsa/Meetin-OS">GitHub <span aria-hidden="true">↗</span></a>
    </nav>
  </header>
  <main>
    <section className="shell hero" aria-labelledby="titre">
      <div className="hero-copy">
        <p className="eyebrow"><span></span> Prototype pour Mac et Windows</p>
        <h1 id="titre">De l’appel à la <em>tâche validée.</em></h1>
        <p className="intro">Prends tes notes pendant l’appel. Retrouve ensuite ce qui a été dit et garde le contexte des décisions.</p>
        <div className="install-actions">
          <a className="button" href="/downloads/Meetin-OS.pkg" download aria-describedby="install-mac">Installer sur Mac <span aria-hidden="true">↓</span></a>
          <a className="button" href="/downloads/Meetin-OS-Windows.exe" download aria-describedby="install-windows">Installer sur Windows <span aria-hidden="true">↓</span></a>
        </div>
        <p className="requirements" id="install-mac"><strong>macOS 15+</strong> · Ouvre le paquet pour ajouter Meetin-OS à Applications. La version de test n’est pas notariée. <a href="https://support.apple.com/fr-fr/102445">Aide Apple</a></p>
        <p className="requirements" id="install-windows"><strong>Windows 10 ou 11 (x64)</strong> · Ouvre l’installateur pour ajouter Meetin-OS au menu Démarrer. Windows peut signaler cette version de test non signée.</p>
      </div>
      <figure className="preview">
        <div className="window">
          <div className="window-bar">
            <div className="lights" aria-hidden="true"><i></i><i></i><i></i></div>
            <span>Carnet de réunion</span>
            <span className="window-badge">APERÇU</span>
          </div>
          <div className="window-body">
            <p className="meeting-label">RÉUNION PRODUIT</p>
            <p className="meeting-title">Point de lancement</p>
            <div className="note">
              <strong>Notes</strong>
              <p>Relire le guide avant le prochain point.</p>
            </div>
            <div className="segment">
              <span className="timestamp">00:18</span>
              <p>« Finalement, Karim s’en charge mardi. »</p>
            </div>
            <div className="task">
              <div>
                <p className="task-label">ENGAGEMENT PROPOSÉ</p>
                <strong>Relire le guide</strong>
                <p className="task-meta">Karim · Mardi</p>
              </div>
              <span className="task-state">À valider</span>
            </div>
          </div>
        </div>
        <figcaption>Exemple illustratif du parcours cible</figcaption>
      </figure>
    </section>
    <section className="workflow" id="fonctionnement" aria-labelledby="parcours">
      <div className="shell">
        <p className="eyebrow"><span></span> Le parcours</p>
        <h2 id="parcours">Garder le fil après l’appel.</h2>
        <ol className="steps">
          <li><span className="step-index">01</span><h3>Capturer</h3><p>Enregistre le micro et le son de l’appel. Note les points clés dans le même carnet.</p></li>
          <li><span className="step-index">02</span><h3>Relire</h3><p>Lance la transcription avec Gladia et retrouve les passages grâce à leurs repères temporels.</p></li>
          <li><span className="step-index">03 <span className="planned">À venir</span></span><h3>Valider</h3><p>Confirme l’engagement, son responsable et son échéance avant la mise à jour de la tâche.</p></li>
        </ol>
      </div>
    </section>
  </main>
  <footer className="shell site-footer">
    <span>Meetin-OS · Projet du hackathon H Company × 42AI</span>
    <a href="https://github.com/Firmirsa/Meetin-OS#readme">Documentation <span aria-hidden="true">↗</span></a>
  </footer>

</>;
}
