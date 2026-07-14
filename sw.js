/* Service Worker HSSE POINT — memungkinkan aplikasi diinstal (PWA) & dibuka offline.
   Strategi:
   - Navigasi (buka aplikasi): network-first, jatuh ke cache index.html saat offline.
   - Aset shell (ikon, manifest): cache-first agar cepat.
   CDN & Supabase sengaja tidak di-cache karena butuh koneksi/otentikasi. */
const CACHE = 'hssepoint-v1';
const SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './icon.svg',
  './icon-maskable.svg',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  // Hanya tangani permintaan same-origin; biarkan CDN/Supabase lewat apa adanya.
  if (url.origin !== self.location.origin) return;

  // Navigasi halaman → network-first, fallback ke index.html dari cache saat offline.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((cache) => cache.put('./index.html', copy));
          return res;
        })
        .catch(() => caches.match('./index.html', { ignoreSearch: true }))
    );
    return;
  }

  // Aset same-origin lain → cache-first, perbarui di latar belakang.
  event.respondWith(
    caches.match(req).then((cached) => {
      const network = fetch(req)
        .then((res) => {
          if (res && res.status === 200) {
            const copy = res.clone();
            caches.open(CACHE).then((cache) => cache.put(req, copy));
          }
          return res;
        })
        .catch(() => cached);
      return cached || network;
    })
  );
});
