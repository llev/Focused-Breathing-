# Roadmap to a publishable web app

Work through these phases in order. Tick items off as they're finished. Phase 2 can change the rest of the plan, so don't polish beyond it until its results are in.

## Decisions Lloyd needs to make

- [x] **Name:** Swellotic, with the line "Breathe. Listen. Focus."
- [x] **Name checks:** on 5 November 2026 Lloyd found no apps, trademarks or businesses called Swellotic. Testing the name with a few people is still worth doing.
- [ ] **Repo name:** rename `Focused-Breathing-` to match the app.
- [x] **Hosting:** Cloudflare Pages, decided 5 November 2026, moving from Netlify. It doesn't charge for bandwidth, which matters with about 200MB of classical music per listener who saves the whole set. Each file must be under 25MB. Its default caching revalidates every file, which suits `sw.js`. Keep relative paths so the app works from any host.
- [x] **Web address:** `swellotic.com`, bought 5 November 2026. Both apps download the classical pieces from it, so the host can change without breaking the iPhone app.
- [ ] **Licence:** none for now. Add MIT only if the code should be open for reuse.

## Phase 1: Make it installable

- [x] Add `manifest.webmanifest` with name, short name, `display: standalone`, start URL, scope, and theme and background colours.
- [x] Design an app icon: 192px, 512px, a maskable version and a 180px Apple touch icon. Lloyd to approve the design.
- [x] Add iOS meta tags for standalone use and the status bar style.
- [x] Bundle the fonts locally and remove the Google Fonts links. This supports offline use and stops visitor data going to Google.
- [x] Add a service worker that caches the app files for offline use.
- [x] Update the service worker safely so people don't get stuck on an old version.
- [ ] Deploy to Cloudflare Pages at `swellotic.com`. Lloyd connects the GitHub repo in the Cloudflare dashboard, with no build command and the repo root as the output folder.

**Done when:** the app installs on iPhone, Android and desktop Chrome, and opens and plays with no connection.

Progress: desktop Chrome reports the app as installable, and it opens and plays offline when served locally. iPhone and Android still need testing once it's deployed.

### Phase 1 decisions

- **Icon:** a sunset-palette sun over three waves, drawn in `icons/icon.svg`. The PNG sizes were rendered from it with headless Chrome. The maskable and Apple icons are full-bleed, and the others have rounded corners.
- **Fonts:** Figtree 400, 500 and 600 and Nunito 300, Latin subset only, from Fontsource. Both use the SIL Open Font License, and the licence files sit beside the fonts in `fonts/`. Apple devices still use their system fonts first.
- **Status bar:** `black-translucent`, so the scene runs under the iPhone status bar. The existing safe-area padding keeps the controls clear of it.
- **Offline:** the service worker serves every app file from a versioned cache, with no network request.
- **Updates:** every release must bump `VERSION` in `sw.js`, or people won't get the new files. A new version downloads in the background and waits. The app offers "Tap to update" only when nothing is playing, so a session is never cut off. A new version also takes over when the app is fully closed and reopened. The app looks for a new version when it returns to the front, at most every 30 minutes.
- **Launch screen:** the icon's sun rises behind the waves, the name settles letter by letter, and the tagline arrives one word at a time. It lasts about two and a half seconds, and a tap or key press skips it. With reduced motion turned on, it simply fades.
- **Host settings:** whichever host is chosen, `sw.js` should be served without long-term caching. Most hosts do this by default.

## Phase 2: Real device audio test

This is the biggest risk. WebKit bug reports describe Web Audio going silent in home-screen web apps after they've been in the background, including on iOS 26: <https://bugs.webkit.org/show_bug.cgi?id=291892>. Sound may also stop when the screen locks.

Lloyd should test the installed app on a real iPhone and Android phone and record the results here:

| Test | iPhone | Android |
| --- | --- | --- |
| Play for 10 minutes with the screen on | | |
| Lock the screen: does the sound continue? | Brown noise: yes | |
| Switch apps and return | "My music app": breaths stop when switching to Spotify | |
| Take a call or trigger Siri or Assistant, then return | | |
| Connect and disconnect Bluetooth headphones | | |
| "My music app" with Spotify playing: do both continue? | Hidden on iPhone | |
| Breath slider changes only the breaths | | |
| Ring/silent switch behaviour | | |
| Spoken words clips, once added | | |

Lloyd's first iPhone results, 5 November 2026: generated sounds keep playing in the background, and only "My music app" stops. That mode uses the mixing sound mode so Spotify can keep playing, and iOS only allows background playback for web apps in the non-mixing mode. A web app can't have both.

**Then decide:**

- If sound continues when locked, stay a pure PWA.
- If it doesn't, either accept "keep the screen on" and make that clear, or wrap the app with Capacitor for native background audio.

**Decided 2026-11-05:** Lloyd chose a native iPhone app. See "iOS app" below. The web app stays for desktop and Android.

## Phase 3: Reliable sound

- [x] Detect when the audio context is suspended or interrupted.
- [x] Restart sound automatically, in time with the breath, where the device allows it.
- [x] Show a clear "Tap to resume sound" prompt where it doesn't.
- [ ] Add Media Session controls and lock-screen details where supported.
- [x] Re-request the screen wake lock after returning to the app.

Lloyd reported that with "My music app", the breaths sometimes kept going but often stopped. The app never restarted sound after the phone paused it. The first three items above fix that, and pass simulated tests in desktop Chrome. They still need checking on a real iPhone and Android phone.

### Phase 3 decisions

- **Restarting:** when the phone pauses the sound, the app tries to restart it as soon as it's back on screen. If the sound hasn't restarted within 1.5 seconds, it shows "Sound paused. Tap to resume."
- **Staying in time:** the audio clock stops while sound is paused, so the breath carries on from where it stopped. Breath sounds are replanned and fade in over 0.8 seconds.
- **No bursts:** if the page falls behind, any breath sound or generated music step that should already have started is skipped. Missed breaths never play all at once.
- **Spoken words:** the phone's built-in voice is gone. The option is hidden until recorded clips exist, and anyone who had it chosen gets the singing bowl instead. The clips play on the audio clock, so they keep exact time and work offline. `tools/make-voice.mjs` makes them with Azure AI Speech, using Lloyd's key on his own computer. The app never contacts Azure.
- **Breath sounds span the breath:** struck sounds used to ring for a fixed time. Now each lasts the whole in-breath or out-breath. An in-breath swells towards its end, an out-breath settles away, and both are silent as the next breath begins. Lloyd to judge how they sound, especially Wooden marimba and Chime, which were short sounds before.
- **Keeping sound playing:** a web app can't stop the phone pausing it. On iPhone, "My music app" needs the polite sound mode so Spotify keeps playing, and iOS doesn't let web pages play that kind of sound in the background. A native wrapper could ask for background audio that mixes with other apps. That is Phase 2's decision, and it needs Lloyd's agreement.
- **Not covered yet:** WebKit bug 291892, where sound can go silent while the browser reports it as playing. The app can't detect that case, so Phase 2 testing should watch for it.
- [ ] Check long sessions of 90 minutes or more for memory growth, battery drain and timing drift.
- [ ] Lloyd to review every sound, especially Beach, the room effect and Soft keys.

## Phase 4: Product and first-run experience

- [ ] Add a short first-run screen that explains the idea, with presets such as "Calm desk", "Beach walk" and "My own music".
- [ ] Make it obvious that "My music app" works alongside Spotify and Apple Music.
- [x] Move session controls into a drawer opened from a session button under the breathing word. It has stop-after times, a custom length from 5 to 240 minutes, and an Interval switch. Its Swell time is 5 to 90 minutes and its Rest time is 1 to 30. On 5 November 2026 Lloyd asked for clearer controls. The drawer now has Timer and Interval tabs, and the open tab is the kind of session. Interval has Rounds: until I stop, or 2, 4 or 6 swells, ending after the last swell. The top right clock was removed, and the session button shows the time while playing. That's elapsed time, time left on a timer, or "Swell" or "Rest" with its time left. During a rest, a soft chime plays, sound fades out, the classical piece pauses, and the word reads "Rest". Another chime brings sound back for the next swell. The word "Pomodoro" is avoided because it's a trademark.
- [x] Show the Classical mix piece and its previous, next and repeat-one controls on the main screen, above the player bar. Saving for offline stays in the Music settings.
- [ ] Lloyd reported the main screen cut off before the bottom of his iPhone screen. Lloyd's screenshot from the installed app showed an empty band at the bottom the same height as the status bar, 62 points. It's a known iOS bug for home-screen apps that draw under the status bar: the page is laid out one status bar short. In the installed app on iPhone, Swellotic now uses the screen's full height, and the settings sheet, session drawer and launch screen reach the real bottom. Elsewhere it uses the visible height the device reports. Version 9 overshot: it gave the inner body the full height as well, so the controls fell below the screen by the status bar's height. Version 10 sizes only the page to the screen, and the body fills the space inside the status bar and home indicator padding. A Chrome simulation with the iPhone's 62 and 34 point safe areas now puts the player bar 16 points above the home indicator. Version 10 fixed the position, but left a flat band 34 points tall at the bottom. The player bar's shadow was cut off in a hard line where the body ended above the home indicator. In version 11, the status bar and home indicator space is padding inside the body, so the body reaches the bottom of the screen. The controls and background haven't moved. Lloyd to confirm on his iPhone once version 11 is deployed.
- [x] Opening the session drawer showed a white focus ring around Done on iPhone. Focus now moves to the drawer itself, and returns to the session button only for keyboard users.
- [x] Hide "My music app" on iPhone and iPad, where it stops whenever you switch apps. Anyone who had it chosen gets the Classical mix. It's still offered on Android, which hasn't been tested yet.
- [ ] Reduce the number of choices shown at first, if testing supports it.
- [ ] Allow keyboard control, such as Space to start and stop.

### Later: included music

Lloyd wants people to be able to press play and hear good music without needing their own files. He's choosing the music later. The likely route is TunePocket for lofi and jazz, and individually checked public domain recordings for classical. A shortlist of 20 calm public domain recordings from Musopen is in `docs/music-shortlist.md`, waiting for Lloyd to listen.

Before buying, get written answers from TunePocket on these points:

- Does the streaming licence cover an installable web app?
- Does the room effect count as modification?
- Who is responsible for performing rights?

The licence also requires reasonable safeguards against downloading or extracting files, so licensed audio can't simply sit in this public repo.

"Audio files" was removed on 5 November 2026 and replaced by the Classical mix, which plays the 20 recordings from the shortlist. Each piece shows its title, performer and Musopen credit, with previous, next and repeat-one controls, and the set repeats by default.

Decided for the Classical mix on 5 November 2026:

- **Publishing:** Lloyd agreed to commit the public domain MP3s, about 200MB, so any host serves them with the app.
- **Offline use:** pieces are kept on the device after 30 seconds of listening. "Save all for offline" keeps the whole set and asks the browser not to clear it. Turning it off frees the space. Without a connection, only kept pieces play, and next and previous skip to them. The service worker answers the partial requests phones make for audio from the kept copy.
- **Saving costs bandwidth:** a piece kept while listening is downloaded twice, once to play and once to keep. Saving the whole set downloads about 200MB.

Still to decide for the Classical mix:

- **Bandwidth:** about 2 hours 48 minutes of music per listener could use up a free hosting plan quickly. Cloudflare Pages doesn't charge for bandwidth.
- **Listening:** Lloyd should check every piece for sound quality and sudden loud passages.

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

## iOS app

A native SwiftUI app in `ios/`, started 2026-11-05. See `ios/README.md` for how to run it.

- [x] Port the breathing timeline, breath sounds, generated music, scenes, settings and launch screen.
- [x] Background audio, mixing with other apps for "My music app", and breaths audible on silent.
- [x] Restart sound after calls and Siri, with "Tap to resume" as a fallback. Stop when headphones disconnect.
- [x] Lock-screen play and stop controls.
- [x] Tests for the timeline and sound engine, and a GitHub Actions build on macOS.
- [ ] Lloyd to run it on his iPhone and fill in the iPhone column of the Phase 2 table using the iOS app.
- [ ] Lloyd to listen to every sound against the web version, especially the room effect, which uses Apple's reverb instead of the web app's.
- [x] Bundle identifier `com.swellotic.app`, from `swellotic.com`. It can't change once the app is on the App Store.
- [ ] Set up an Apple Developer account for TestFlight.
- [ ] App Store listing, privacy details and screenshots. Review all copy against the health claim rules.
- [ ] Later: show what's playing in Apple Music, Apple Watch, widgets and Focus mode.

### iOS decisions

- **Why native:** iOS doesn't let web pages keep sound playing in the background while mixing with other apps. A native app can, and can ignore the silent switch. Lloyd also wants the App Store and room to add Watch and widgets. Haptics aren't needed yet.
- **Native SwiftUI, not Capacitor:** Web Audio inside a wrapper can still go quiet in the background, so a wrapper might not fix the main problem. SwiftUI uses Apple's own audio engine. The cost is two codebases to keep in step.
- **One timeline:** the audio thread owns it and starts each breath sound on the exact sample. The visuals read where it is through a lock-free snapshot. When the phone pauses sound, the breath stops and carries on from where it was, as on the web.
- **Sound session:** "My music app" uses the playback category with mixing, so Spotify keeps playing. Other tracks use playback without mixing, so they take over from other apps. Both ignore the silent switch.
- **Balancing with a music app (2026-11-05):** Lloyd found the breaths quiet next to his music app. iOS doesn't let one app set another's volume, so "My music app" now gives breaths about 9.5 dB more headroom, with the limiter catching peaks, and adds "Lower my music app", on by default. That asks iOS to duck other apps steadily for the whole session. iOS sets how much, and the duck never follows the breath, which keeps clear of rhythmic modulation. The web app can't do either.
- **Headphones:** when headphones disconnect, Swellotic stops, as Apple recommends, so it never plays out loud by surprise.
- **Room effect:** a lowpass filter and Apple's medium hall reverb, instead of the web app's generated impulse. Lloyd to judge.
- **Audio files** are decoded into memory and cleared when the app closes, as on the web. They're never uploaded.
- **Minimum iOS 18,** for lock-free atomics in Swift. iOS 26 gets Liquid Glass controls. Earlier versions get a frosted material.
- **App Store category:** Productivity, not Health & Fitness, to keep clear of medical claims.
- **Not ported:** the service worker and update prompt, since the App Store handles updates. Spoken words stay hidden until the clips exist, as on the web.

## Phase 6: Find out if it helps

- [ ] Share it with a small group of people who do focused work.
- [ ] Ask whether they keep using it after a week, which settings they use, and whether a breathing cue helps or distracts them.
- [ ] Choose a privacy-friendly way to collect feedback. A simple form or conversations are enough at first.

Whether a breathing cue helps or distracts during focused work is still an open question. The answer decides whether the product is continuous pacing, occasional resets, or something more peripheral.

## Known limitations

- Separate headphone and speaker outputs aren't supported yet. Chrome's `setSinkId` may make this possible on desktop.
- Spoken words are hidden until recorded clips are made and checked.
- Soft keys is a rough generated sketch, not a finished recording.
- Classical mix pieces that haven't been kept on the device need a connection.
- Safari can clear saved music when the phone runs low on space, even after the app asks it not to.
- Using `ambient` audio on iPhone may mean the silent switch mutes the breaths.
- Spotify and Apple Music volumes can't be controlled from this app. On a phone, the side buttons change everything together.
- Direct Spotify integration is out: its developer terms have barred mixing Spotify content with other audio. Check the current terms before revisiting this.
