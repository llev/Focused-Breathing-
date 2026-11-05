// Downloads the "Classical mix" recordings listed in classical.json from Wikimedia Commons, as MP3s that play on every device.
// All are public domain recordings made for Musopen. Files already downloaded are skipped.
//
// Usage, from the project folder:
//   node tools/fetch-classical.mjs
//
// The MP3s are saved in audio/classical/, which git ignores. Whether to publish them is Lloyd's decision under the
// third-party audio rule in CLAUDE.md. The app's host needs a copy of the folder either way.
import fs from 'node:fs';

const root = new URL('../', import.meta.url);
const tracks = JSON.parse(fs.readFileSync(new URL('classical.json', root), 'utf8'));
const UA = { 'User-Agent': 'SwelloticMusicFetch/0.1 (one-off download of public domain recordings)' };
const wait = ms => new Promise(r => setTimeout(r, ms));

async function get(url, tries = 5) {
  for (let i = 1; ; i++) {
    const res = await fetch(url, { headers: UA });
    if (res.ok) return res;
    if (i === tries || (res.status !== 429 && res.status < 500)) throw new Error(`${res.status} for ${url}`);
    await wait(5000 * i);
  }
}

fs.mkdirSync(new URL('audio/classical/', root), { recursive: true });
for (const t of tracks) {
  const out = new URL(t.file, root);
  if (fs.existsSync(out)) { console.log(`Already have ${t.file}`); continue; }
  const api = 'https://commons.wikimedia.org/w/api.php?' + new URLSearchParams({
    action: 'query', prop: 'videoinfo|imageinfo', titles: t.source, viprop: 'derivatives',
    iiprop: 'extmetadata', iiextmetadatafilter: 'LicenseShortName', format: 'json', formatversion: '2'
  });
  const page = (await (await get(api)).json()).query.pages[0];
  const licence = page.imageinfo?.[0]?.extmetadata?.LicenseShortName?.value || '';
  if (!/public domain|cc0|pdm/i.test(licence)) { console.error(`Skipped ${t.source}: licence is now "${licence}".`); continue; }
  const mp3 = (page.videoinfo?.[0]?.derivatives || []).find(d => d.type === 'audio/mpeg');
  if (!mp3) { console.error(`Skipped ${t.source}: Commons has no MP3 version.`); continue; }
  fs.writeFileSync(out, Buffer.from(await (await get(mp3.src)).arrayBuffer()));
  console.log(`Saved ${t.file} (${licence})`);
  await wait(1000);
}
