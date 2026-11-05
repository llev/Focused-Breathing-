// Makes the "Spoken words" clips with Azure AI Speech, so the app can play a good voice offline.
// It runs once on your computer. The app never contacts Azure, and the key is never saved in the repo.
//
// Usage, from the project folder:
//   AZURE_SPEECH_KEY=... AZURE_SPEECH_REGION=uksouth node tools/make-voice.mjs [voice name]
//
// The default voice is en-GB-SoniaNeural. Others to try include en-GB-LibbyNeural and en-GB-RyanNeural.
// Listen to the clips in audio/voice/ before using them. Then list them in VOICE_CLIPS in app.js and in FILES in sw.js.
// Check Microsoft's terms allow these clips to be published before committing them, because this repo is public.
import fs from 'node:fs';

const key = process.env.AZURE_SPEECH_KEY, region = process.env.AZURE_SPEECH_REGION;
if (!key || !region) {
  console.error('Set AZURE_SPEECH_KEY and AZURE_SPEECH_REGION first. Both are on the Azure portal page for your Speech resource.');
  process.exit(1);
}
const voice = process.argv[2] || 'en-GB-SoniaNeural';
if (!/^[a-z]{2}-[A-Z]{2}-\w+$/.test(voice)) { console.error(`"${voice}" doesn't look like an Azure voice name.`); process.exit(1); }

// Slow, low and soft, to suit a breathing guide.
const LINES = { 'breathe-in': 'Breathe in', 'breathe-out': 'Breathe out' };
const out = new URL('../audio/voice/', import.meta.url);
fs.mkdirSync(out, { recursive: true });

for (const [file, words] of Object.entries(LINES)) {
  const ssml = `<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-GB">` +
    `<voice name="${voice}"><prosody rate="-25%" pitch="-4%">${words}</prosody></voice></speak>`;
  const res = await fetch(`https://${region}.tts.speech.microsoft.com/cognitiveservices/v1`, {
    method: 'POST',
    headers: {
      'Ocp-Apim-Subscription-Key': key,
      'Content-Type': 'application/ssml+xml',
      'X-Microsoft-OutputFormat': 'audio-48khz-192kbitrate-mono-mp3',
      'User-Agent': 'swellotic-voice-tool'
    },
    body: ssml
  });
  if (!res.ok) { console.error(`Azure said ${res.status} ${res.statusText} for "${words}". Check the key, region and voice name.`); process.exit(1); }
  const path = new URL(`${file}.mp3`, out);
  fs.writeFileSync(path, Buffer.from(await res.arrayBuffer()));
  console.log(`Saved ${path.pathname}`);
}
