# Roadmap to a publishable web app

Work through these phases in order. Tick items off as they're finished. Phase 2 can change the rest of the plan, so don't polish beyond it until its results are in.

## Decisions Lloyd needs to make

- [ ] **Name:** the app is called Breathing Room, but the repo is `Focused-Breathing-`. Pick one and check it in app stores and the UK IPO trademark search.
- [ ] **Repo name:** remove the trailing hyphen if the repo keeps this name.
- [ ] **Hosting:** Cloudflare Pages, Netlify or GitHub Pages. All can serve a PWA over HTTPS. Use relative paths so the app works from any of them.
- [ ] **Web address:** a custom domain makes it easier to move hosts later without breaking people's installed apps.
- [ ] **Licence:** none for now. Add MIT only if the code should be open for reuse.

## Phase 1: Make it installable

- [ ] Add `manifest.webmanifest` with name, short name, `display: standalone`, start URL, scope, and theme and background colours.
- [ ] Design an app icon: 192px, 512px, a maskable version and a 180px Apple touch icon.
- [ ] Add iOS meta tags for standalone use and the status bar style.
- [ ] Bundle the fonts locally and remove the Google Fonts links. This supports offline use and stops visitor data going to Google.
- [ ] Add a service worker that caches the app files for offline use.
- [ ] Update the service worker safely so people don't get stuck on an old version.
- [ ] Deploy to the chosen host over HTTPS.

**Done when:** the app installs on iPhone, Android and desktop Chrome, and opens and plays with no connection.

## Phase 2: Real device audio test

This is the biggest risk. WebKit bug reports describe Web Audio going silent in home-screen web apps after they've been in the background, including on iOS 26: <https://bugs.webkit.org/show_bug.cgi?id=291892>. Sound may also stop when the screen locks.

Lloyd should test the installed app on a real iPhone and Android phone and record the results here:

| Test | iPhone | Android |
| --- | --- | --- |
| Play for 10 minutes with the screen on | | |
| Lock the screen: does the sound continue? | | |
| Switch apps and return | | |
| Take a call or trigger Siri or Assistant, then return | | |
| Connect and disconnect Bluetooth headphones | | |
| "My music app" with Spotify playing: do both continue? | | |
| Breath slider changes only the breaths | | |
| Ring/silent switch behaviour | | |
| Spoken words voice and timing | | |

**Then decide:**

- If sound continues when locked, stay a pure PWA.
- If it doesn't, either accept "keep the screen on" and make that clear, or wrap the app with Capacitor for native background audio.

Don't start a native wrapper without Lloyd's agreement.

## Phase 3: Reliable sound

- [ ] Detect when the audio context is suspended or interrupted.
- [ ] Restart sound automatically, in time with the breath, where the device allows it.
- [ ] Show a clear "Tap to resume sound" prompt where it doesn't.
- [ ] Add Media Session controls and lock-screen details where supported.
- [ ] Re-request the screen wake lock after returning to the app.
- [ ] Check long sessions of 90 minutes or more for memory growth, battery drain and timing drift.
- [ ] Lloyd to review every sound, especially Beach, the room effect and Soft keys.

## Phase 4: Product and first-run experience

- [ ] Add a short first-run screen that explains the idea, with presets such as "Calm desk", "Beach walk" and "My own music".
- [ ] Make it obvious that "My music app" works alongside Spotify and Apple Music.
- [ ] Reduce the number of choices shown at first, if testing supports it.
- [ ] Allow keyboard control, such as Space to start and stop.

### Later: included music

Lloyd wants people to be able to press play and hear good music without needing their own files. He's choosing the music later. The likely route is TunePocket for lofi and jazz, and individually checked public domain recordings for classical.

Before buying, get written answers from TunePocket on these points:

- Does the streaming licence cover an installable web app?
- Does the room effect count as modification?
- Who is responsible for performing rights?

The licence also requires reasonable safeguards against downloading or extracting files, so licensed audio can't simply sit in this public repo.

"Add audio files" is a minor feature because few people keep music files. Only save them on the device if it proves worthwhile.

## Phase 5: Launch checks

- [ ] Add automated browser tests for start and stop, every sound and visual, the sliders, and saved settings.
- [ ] Run a full accessibility audit, including screen readers, keyboard use and text contrast over the moving scenes.
- [ ] Check performance on an older phone, especially Lava lamp.
- [ ] Add a privacy notice covering local settings and what the host logs.
- [ ] Add an About page with the health note, and credit any third-party fonts.
- [ ] Check licences for bundled fonts.
- [ ] Review all copy against the health claim rules in `CLAUDE.md`.
- [ ] Add social sharing images and metadata.

**Before charging money:** get the name and health wording checked properly by a professional.

## Phase 6: Find out if it helps

- [ ] Share it with a small group of people who do focused work.
- [ ] Ask whether they keep using it after a week, which settings they use, and whether a breathing cue helps or distracts them.
- [ ] Choose a privacy-friendly way to collect feedback. A simple form or conversations are enough at first.

Whether a breathing cue helps or distracts during focused work is still an open question. The answer decides whether the product is continuous pacing, occasional resets, or something more peripheral.

## Known limitations

- Separate headphone and speaker outputs aren't supported yet. Chrome's `setSinkId` may make this possible on desktop.
- Spoken words use the device's built-in voice, so quality varies. Recorded voice clips would be more consistent and would work the same offline.
- Soft keys is a rough generated sketch, not a finished recording.
- Files added with "Audio files" are lost when the page reloads.
- Using `ambient` audio on iPhone may mean the silent switch mutes the breaths.
- Spotify and Apple Music volumes can't be controlled from this app. On a phone, the side buttons change everything together.
- Direct Spotify integration is out: its developer terms have barred mixing Spotify content with other audio. Check the current terms before revisiting this.
