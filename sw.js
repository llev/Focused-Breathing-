/* Swellotic service worker: keeps the app working with no connection.

   Releasing a change: bump VERSION. Browsers only notice a new version when
   this file changes, so editing app.js or styles.css alone won't reach people
   who have already opened the app. Add any new file to FILES as well.

   Updates: the new version downloads in the background and waits. The page
   offers "Tap to update" when nothing is playing, and the new version also
   takes over by itself the next time the app is fully closed and reopened.
   It never swaps files in the middle of a session. */
const VERSION = '31';
const CACHE = 'swellotic-' + VERSION;
/* Classical recordings kept for offline use. This store is not versioned, so app updates don't throw saved music away. */
const MUSIC = 'swellotic-music';
/* Learned sounds (rain, storm, wind, park), kept the first time each mood plays. Not versioned either, so updates keep them;
   when a file changes, give it a new name. */
const SOUNDS = 'swellotic-sounds';
const FILES = [
  './',
  'index.html',
  'styles.css',
  'app.js',
  'sound-worklet.js',
  'manifest.webmanifest',
  'classical.json',
  'privacy.html',
  'support.html',
  'pages.css',
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
  /* cache: 'reload' skips the browser's HTTP cache, so a new version never stores old copies of the files.
     Some hosts redirect, for example Cloudflare sends index.html to / and privacy.html to /privacy. Browsers refuse a
     stored redirect when opening a page, so each file is stored as the page it ends up at. */
  event.waitUntil(caches.open(CACHE).then(cache => Promise.all(FILES.map(async f => {
    const res = await fetch(new Request(f, { cache: 'reload' }));
    if (!res.ok) throw new Error(`${f} failed to download`);
    const clean = res.redirected ? new Response(await res.blob(), { status: 200, headers: res.headers }) : res;
    await cache.put(f, clean);
  }))));
});

self.addEventListener('activate', event => {
  event.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k.startsWith('swellotic-') && k !== CACHE && k !== MUSIC && k !== SOUNDS).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('message', event => {
  if (event.data === 'update') self.skipWaiting();
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  if (new URL(req.url).pathname.includes('/audio/classical/')) { event.respondWith(music(req)); return; }
  if (new URL(req.url).pathname.includes('/sounds/')) { event.respondWith(sound(req)); return; }
  if (req.mode === 'navigate') {
    /* The Privacy and Help pages open as themselves, with or without ".html", because Cloudflare drops it.
       Any other page address inside the app, including ones with ?query strings, opens the cached app. */
    const path = new URL(req.url).pathname;
    event.respondWith(caches.open(CACHE)
      .then(async cache => await cache.match(req, { ignoreSearch: true })
        || (!/\.html$|\/$/.test(path) && await cache.match(path + '.html'))
        || await cache.match('./'))
      .then(hit => hit || fetch(req)));
    return;
  }
  event.respondWith(caches.open(CACHE)
    .then(cache => cache.match(req, { ignoreSearch: true }))
    .then(hit => hit || fetch(req)));
});

/* Saved pieces are served from the music store. Phones ask for audio a part at a time, so answer those partial requests
   from the saved copy. Pieces that aren't saved come from the network as normal. */
async function music(req) {
  const hit = await (await caches.open(MUSIC)).match(req.url);
  if (!hit) return fetch(req);
  return part(hit, req);
}

/* Answers a request for part of a kept file, as phones make for audio, or the whole file if no part was asked for. */
async function part(hit, req) {
  const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.get('range') || '');
  if (!range) return hit;
  const blob = await hit.blob(), size = blob.size;
  let start = range[1] === '' ? size - Number(range[2]) : Number(range[1]);
  let end = range[1] === '' || range[2] === '' ? size - 1 : Math.min(Number(range[2]), size - 1);
  start = Math.max(0, start);
  if (start >= size || start > end) return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${size}` } });
  return new Response(blob.slice(start, end + 1), {
    status: 206,
    headers: {
      'Content-Type': hit.headers.get('Content-Type') || 'audio/mpeg',
      'Content-Range': `bytes ${start}-${end}/${size}`,
      'Content-Length': String(end - start + 1),
      'Accept-Ranges': 'bytes'
    }
  });
}

/* Learned sounds: served from the store once kept, otherwise downloaded whole and kept for next time. Thunder streams
   through an audio player, which asks for parts, so those are answered from the whole file. */
async function sound(req) {
  const store = await caches.open(SOUNDS);
  let hit = await store.match(req.url, { ignoreSearch: true });
  if (!hit) {
    const res = await fetch(req.url);
    if (!res.ok || res.status !== 200) return res;
    await store.put(req.url, res.clone()).catch(() => {});
    hit = res;
  }
  return part(hit, req);
}
