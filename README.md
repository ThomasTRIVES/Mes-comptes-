# Mes Comptes

Suivi de budget personnel : une seule page (`index.html`), données synchronisées dans Supabase (table `mc_docs`, une ligne par mois + réglages, protégée par RLS : chaque compte ne voit que ses lignes).

- `index.html` : l'application (HTML + CSS + JS, sans build).
- `supabase-setup.sql` : création de la table, des règles d'accès et du temps réel.
- `manifest.webmanifest`, `icon-*.png` : icône et installation sur l'écran d'accueil.

Publiée avec GitHub Pages (branche `main`, dossier racine). Les relevés PDF sont lus dans le navigateur (PDF.js) ; aucune donnée bancaire n'est dans ce dépôt.
