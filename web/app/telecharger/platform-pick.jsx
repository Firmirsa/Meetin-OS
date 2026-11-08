'use client';

import {useEffect} from 'react';

/**
 * Met en avant le système de l'appareil (Mac par défaut côté serveur).
 * Si l'appareil est sous Windows ou Linux, la carte correspondante devient la recommandée.
 * Android annonce aussi « Linux » : on l'écarte pour garder Mac par défaut.
 */
export default function PlatformPick() {
  useEffect(() => {
    const ua = `${navigator.userAgentData?.platform ?? ''} ${navigator.platform ?? ''} ${navigator.userAgent}`.toLowerCase();
    const os = ua.includes('win') ? 'windows'
      : ua.includes('linux') && !ua.includes('android') ? 'linux'
      : null;
    if (!os) return;
    document.querySelectorAll('.platform').forEach((card) => {
      if (card.dataset.os === os) card.dataset.recommended = 'true';
      else delete card.dataset.recommended;
    });
  }, []);
  return null;
}
