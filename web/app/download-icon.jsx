/** Icône « télécharger » (flèche vers un plateau), suit la couleur du texte. */
export default function DownloadIcon({size = 18}) {
  return <svg className="download-icon" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
    strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
    <path d="M12 3.5v11" /><path d="m7 10 5 5 5-5" /><path d="M4.5 16.5v2a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-2" />
  </svg>;
}
