/* Swellotic service worker: keeps the app working with no connection.

   Releasing a change: bump VERSION. Browsers only notice a new version when
   this file changes, so editing app.js or styles.css alone won't reach people
   who have already opened the app. Add any new file to FILES as well.

   Updates: the new version downloads in the background and waits. The page
   offers "Tap to update" when nothing is playing, and the new version also
   takes over by itself the next time the app is fully closed and reopened.
   It never swaps files in the middle of a session. */
const VERSION = '4';
const CACHE = 'swellotic-' + VERSION;
const FILES = [
  './',
  'index.html',
  'styles.css',
  'app.js',
  'manifest.webmanifest',
  'icons/icon.svg',
  'icons/icon-192.png',
  'icons/icon-512.png',
  'icons/icon-maskable-512.png',
  'icons/apple-touch-icon.png',
  'fonts/figtree-latin-400-normal.woff2',
  'fonts/figtree-latin-500-normal.woff2',
  'fonts/figtree-latin-600-normal.woff2',
  'fonts/nunito-latin-300-normal.woff2'
];

self.addEventListener('install', event => {
  /* cache: 'reload' skips the browser's HTTP cache, so a new version never stores old copies of the files. */
  event.waitUntil(caches.open(CACHE).then(cache =>
    cache.addAll(FILES.map(f => new Request(f, { cache: 'reload' })))));
});

self.addEventListener('activate', event => {
  event.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k.startsWith('swellotic-') && k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('message', event => {
  if (event.data === 'update') self.skipWaiting();
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  if (req.mode === 'navigate') {
    /* Any page address inside the app, including ones with ?query strings, opens the cached app. */
    event.respondWith(caches.open(CACHE)
      .then(cache => cache.match('index.html'))
      .then(hit => hit || fetch(req)));
    return;
  }
  event.respondWith(caches.open(CACHE)
    .then(cache => cache.match(req, { ignoreSearch: true }))
    .then(hit => hit || fetch(req)));
});
