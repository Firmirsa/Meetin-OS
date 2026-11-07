'use client';

import {useEffect} from 'react';

/**
 * Fait vivre l'aperçu de la landing : la pastille passe « À valider » -> « Fiche à jour »,
 * au rythme du surlignage animé en CSS (mtLoopSweep, 6 s, theme-nuit.css). N'importe rien
 * d'autre dans la page ; si le thème nuit n'est pas chargé, ça ne fait rien de visible.
 * Respecte prefers-reduced-motion : la pastille reste alors sur « À valider ».
 */
export default function HeroPreviewLoop({pending = 'À valider', done = 'Fiche à jour'}) {
  useEffect(() => {
    const pill = document.getElementById('etat-apercu');
    if (!pill || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return undefined;
    const flipAt = 1300 + 6000 * 0.3;
    const resetAt = 1300 + 6000;
    let timers = [];
    function loop() {
      timers.push(setTimeout(() => {
        pill.textContent = done;
        pill.classList.add('is-done');
      }, flipAt));
      timers.push(setTimeout(() => {
        pill.textContent = pending;
        pill.classList.remove('is-done');
      }, resetAt));
    }
    loop();
    const interval = setInterval(loop, 6000);
    return () => { clearInterval(interval); timers.forEach(clearTimeout); };
  }, [pending, done]);

  return null;
}
