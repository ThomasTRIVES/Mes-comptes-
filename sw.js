/* Mes Comptes + Mes Papiers : fonctionnement sans connexion.
   - pages et fichiers du site : réseau d'abord (les mises à jour arrivent dès qu'il y a internet), copie en cache sinon ;
   - bibliothèques et polices (adresses versionnées) : cache d'abord ;
   - Supabase (tes données) : jamais mis en cache ici (les applis gardent leur propre copie). */
const CACHE = "mc-offline-v1";
const CORE = ["./", "./index.html", "./manifest.webmanifest", "./icon-192.png", "./icon-180.png",
  "./papiers/", "./papiers/index.html", "./papiers/manifest.webmanifest", "./papiers/icon-192.png", "./papiers/icon-180.png"];
const LIBS = ["https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js",
  "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js",
  "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js",
  "https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,500;12..96,700&family=Figtree:wght@400;500;600;700&display=swap"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => Promise.all(CORE.concat(LIBS).map(u => c.add(u).catch(() => {})))).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", e => {
  const r = e.request, u = new URL(r.url);
  if (r.method !== "GET" || /supabase\.co$/.test(u.hostname)) return;
  const sameSite = u.origin === self.location.origin;
  if (sameSite) {
    // réseau d'abord, cache en secours (et pour une page, la page de l'appli)
    e.respondWith(fetch(r).then(res => { if (res.ok) { const cp = res.clone(); caches.open(CACHE).then(c => c.put(r, cp)); } return res; })
      .catch(() => caches.match(r, { ignoreSearch: true }).then(m => m || (r.mode === "navigate"
        ? caches.match(u.pathname.includes("/papiers") ? "./papiers/index.html" : "./index.html") : Response.error()))));
    return;
  }
  if (/(jsdelivr\.net|cdnjs\.cloudflare\.com|fonts\.googleapis\.com|fonts\.gstatic\.com)$/.test(u.hostname)) {
    e.respondWith(caches.match(r).then(m => m || fetch(r).then(res => { if (res.ok || res.type === "opaque") { const cp = res.clone(); caches.open(CACHE).then(c => c.put(r, cp)); } return res; })));
  }
});
