'use client';

import {useEffect} from 'react';

/**
 * Met en avant le système de l'appareil (Mac par défaut côté serveur).
 * Si l'appareil est sous Windows, la carte Windows devient la recommandée ;
 * sous Linux, Mac reste en avant puisque Linux n'est pas encore disponible.
 */
export default function PlatformPick() {
  useEffect(() => {
    const ua = `${navigator.userAgentData?.platform ?? ''} ${navigator.platform ?? ''} ${navigator.userAgent}`.toLowerCase();
    const os = ua.includes('win') ? 'windows' : null;
    if (!os) return;
    document.querySelectorAll('.platform').forEach((card) => {
      if (card.dataset.os === os) card.dataset.recommended = 'true';
      else delete card.dataset.recommended;
    });
  }, []);
  return null;
}
