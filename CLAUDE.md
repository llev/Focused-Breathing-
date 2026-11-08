# Swellotic

Tagline: Breathe. Listen. Focus.

A breathing guide with music or ambient sound, and separate volumes for each. It began with Lloyd's own way of working: Breathing Zone in headphones with transparency on, and music through his computer speakers. The breath feels close and the music sits in the room. This app brings that feeling to one pair of headphones, for places such as trains and offices.

The goal is to find out whether this helps other people focus.

The work left is in `docs/ROADMAP.md`. Follow its phases in order, tick items off as they're finished, and record new decisions there.

## How the app works

- It's plain HTML, CSS and JavaScript, with no framework or build step. Keep it that way unless Lloyd agrees to change it.
- `app.js` has one timeline of breathing phases. Sound and visuals both read from it, so they stay in step. Don't give the visuals a separate timer.
- Sound is scheduled ahead on the Web Audio clock because browsers slow down timers in background tabs.
- `audioSession.type` is `ambient` for "My music app" so other apps can keep playing, and `playback` otherwise.
- Background sound is generated in code, except the Classical mix, the planned spoken words clips and the learned sounds in `sounds/`.
- The learned sounds are new audio made by Claude from measurements of Freesound recordings Lloyd chose: rain, thunderstorm and park, plus generated wind and thrush note shapes. They download when a mood is first played and the service worker keeps them in its `swellotic-sounds` store. Lloyd checked the source licences on 8 November 2026: they need attribution, except the thrush. Keep the credits on the Help page (`support.html`) whenever these sounds ship. Loops are FLAC, which is lossless, so they loop without a seam; thunder rolls are MP3.
- The web app decodes each loop once into 16-bit samples at its own rate and plays it in `sound-worklet.js`, an AudioWorklet, as the iPhone app does. Don't decode learned sounds into ordinary AudioBuffers: that took Night storm to about 120MB. Thunder rolls stream from their files through one audio player. The current mood's files are fetched and decoded as the app opens, behind the launch screen. Safari needs part-file answers to stream audio, so `sw.js` and `functions/sounds/` give them. The scripts that made them are in `tools/sound-lab/`. The iPhone app ships copies in `ios/Swellotic/Resources/Sounds/`, so change both together.
- The Sounds section offers moods, then Noise, then Gentle music. Every sound except My music app has an Adjust sound sheet: Distance and Tone, with Fine tune (its Mix layers and Low, Middle and High) hidden until tapped. Settings are kept per sound in `S.adjust`, storing only what differs from how the sound was designed.
- The Classical mix streams public domain MP3s from `audio/classical/`. They're listed in `classical.json` and downloaded by `tools/fetch-classical.mjs`. Lloyd agreed on 5 November 2026 to commit these public domain recordings. The ban on committing third-party audio still covers everything else. Never decode a whole piece into memory, because they're up to 15 minutes long.
- The spoken words clips are made once with `tools/make-voice.mjs`. Don't commit them until Lloyd has confirmed the voice service's terms allow it.
- Breath sounds last the whole breath and fall silent as the next one begins.
- `sw.js` caches every app file for offline use. Bump its `VERSION` whenever any app file changes, and add new files to its `FILES` list. Never make an update reload the page while sound is playing.
- Keep every request on the app's own site. Fonts are bundled in `fonts/`.

## iOS app

- `ios/` holds a native SwiftUI version. Lloyd chose native over a web wrapper on 2026-11-05 for background audio. See `ios/README.md`.
- Keep features in step with the web app unless there's a reason to differ, and record differences in `docs/ROADMAP.md`.
- `ios/Swellotic/Core/` must stay plain Swift with no UIKit, SwiftUI or AVFoundation, so `swift test` can check it.
- Nothing on the audio thread may allocate memory or take a lock. The render code reads settings through atomics.
- Claude can't build iOS apps here. Push and check the iOS GitHub Actions run, which runs the tests and builds for the Simulator.
- `sw.js` covers the web app only. iOS changes don't need a `VERSION` bump.
- The iOS app downloads the Classical mix from `https://swellotic.com/`. When `classical.json` changes, copy it to `ios/Swellotic/Resources/classical.json` too, so a fresh install starts with the same list.

## Rules

### Health and focus claims

- Don't say the app reduces anxiety, lowers blood pressure, treats ADHD or has any other medical effect, in the app or in marketing copy. Medical claims could bring it under UK medical device rules.
- Don't say it's proven to improve focus. We have no evidence for this app.
- Keep the light-headedness note.

### Audio and intellectual property

- Don't add fast rhythmic amplitude modulation to the music. Brain.fm holds US patents in this area. Keep breath and music as separate layers.
- Don't describe the app as a Breathing Zone or Brain.fm alternative in a way that suggests a connection.
- Never commit third-party audio. This repo is public, and even licensed tracks mustn't be downloadable from it. "Royalty-free" doesn't automatically cover an app where the music is the product.

### Privacy

- No accounts, analytics or trackers without Lloyd's agreement.
- Lloyd agreed on 5 November 2026 to anonymous counts in the web app with PostHog's EU servers. Only `app opened`, `session started` and `session ended` are sent, with the choices behind a session. They go to `/ingest` on Swellotic's own site, and `functions/ingest.js` passes them on without the IP address. Nothing is stored on the device, there are no IDs that last beyond a page load, no person profiles, no recordings and no automatic click tracking. Adding an event, or anything that identifies people over time, needs Lloyd's agreement and a privacy notice update.
- People's audio files stay on their device and are never uploaded.
- Saved Classical mix pieces stay in the browser's own storage on the device.

### Design

- The single dark look and frosted glass controls are deliberate. It should feel like a premium, friendly iPhone app.
- The player bar stays on screen with play, Breath, Sounds and Settings.
- Sections stay collapsible and show their current setting when closed.
- Design for phones first, with touch targets of at least 44px.
- Keep `prefers-reduced-motion` support: visuals become a gentle colour fade.
- Avoid clutter. The app should stay out of the way during work.

### Copy

- Don't use the word "Pomodoro" in the app or marketing. It's a registered trademark. The session option is called "Interval", and its two times are "Swell" and "Rest".
- Use UK English and plain, friendly language.
- Name things by what people recognise, such as "Breath" and "Sounds", not technical terms. Lloyd renamed Music to Sounds on 8 November 2026, as it covers rain and noise as well as music.

## Testing

- Run locally with `python3 -m http.server 8000`.
- There's no automated test suite yet. Phase 5 of the roadmap adds one.
- Passing in a desktop browser doesn't prove the app works on a phone. Audio features need testing on a real iPhone and a real Android phone.
- Claude can't hear the output, so ask Lloyd to judge how anything sounds.
