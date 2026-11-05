// Passes Swellotic's anonymous counts on to PostHog's EU servers. Runs on Cloudflare Pages at /ingest.
//
// Privacy: the visitor's IP address is never forwarded, so PostHog only sees Cloudflare. Only the country Cloudflare
// already knows is passed on. Events can't create person profiles, and only the three named events, with plain
// values, get through. The page never stores anything on the device: see count() in app.js.
//
// The key below can only send events, not read them, so it's safe in this public repo.
const KEY = 'phc_pK4YB7HnEXJT8RcStTvttpXwyBLJaMwiWTuZBPYF3Zes';
const EVENTS = new Set(['app opened', 'session started', 'session ended']);

export async function onRequestPost({ request, waitUntil }) {
  let data;
  try {
    const text = await request.text();
    if (text.length > 4000) throw new Error('too long');
    data = JSON.parse(text);
  } catch (e) {
    return new Response(null, { status: 400 });
  }
  if (!data || !EVENTS.has(data.event) || typeof data.visit !== 'string') return new Response(null, { status: 400 });

  // Keep only short plain values with simple names, so nothing else can be smuggled through.
  const properties = {};
  for (const [k, v] of Object.entries(data.props || {})) {
    if (!/^[a-z_]{1,30}$/.test(k)) continue;
    if (typeof v === 'number' || typeof v === 'boolean' || (typeof v === 'string' && v.length <= 40)) properties[k] = v;
  }
  Object.assign(properties, {
    country: request.cf?.country || null,
    $process_person_profile: false,
    $geoip_disable: true,
    $lib: 'swellotic-web'
  });

  waitUntil(fetch('https://eu.i.posthog.com/i/v0/e/', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ api_key: KEY, event: data.event, distinct_id: 'visit-' + data.visit.slice(0, 16), properties })
  }).catch(() => {}));
  return new Response(null, { status: 204 });
}
