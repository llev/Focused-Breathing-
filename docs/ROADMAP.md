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
- [x] Deploy to Cloudflare Pages: live at `focused-breathing.pages.dev` on 5 November 2026, with no build command and the repo root as the output folder.
- [x] Add `swellotic.com` as the Pages project's custom domain: live on 5 November 2026, with `www.swellotic.com` too.
- [x] Cloudflare added its Web Analytics script from `static.cloudflareinsights.com` to swellotic.com, and rewrote email addresses with a script of its own. It couldn't be found in the dashboard, so `_headers` sends `Cache-Control: no-transform`, which tells Cloudflare not to alter the pages.
- **Cloudflare quirks (5 November 2026):** Pages drops `.html` from addresses with a redirect, so `sw.js` stores each file as the page it ends up at and opens `/privacy` as `privacy.html`. Pages also ignores range requests for static files, which Safari needs to play audio, so `functions/audio/[[path]].js` answers them for the Classical mix. Each music request then counts towards the free plan's 100,000 function requests a day.

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

### Sound moods and adjustments (test branch, 8 November 2026)

On the `claude/sound-moods` branch for Lloyd to test before merging. Background and listening tests are in Lloyd's Notion research page.

- **Moods are the choices:** Rain on the window, Night storm, Fireside, Woodland stream, Calm shore, Winter park and Wind on the hill. Noise (Brown, Pink and the new Green) and Gentle music (Ambient, Soft keys, Classical mix, My music app) keep plain names, because people look for "brown noise" by name.
- **Only two rain moods:** Lloyd dropped Under the porch, Drizzle and Storm rolling in, since adjusting Rain on the window or Night storm gets there. First light and Winter park became one mood, with First light's sound and the Winter park name.
- **Music is now Sounds:** the section, the player bar slider and "Put sounds in the room". "Gentle music" and "My music app" keep the word.
- **Adjust sound:** a row under the chips that summarises changes, such as "Further away, more thunder". The sheet shows Distance (Near to Far) and Tone (Warm to Bright). Fine tune stays hidden until tapped and holds the sound's Mix layers, if it has any, and Frequencies: Low, Middle and High. Every slider is horizontal, as vertical faders had labels too small to read. Reset returns the sound to how it was designed. Settings are kept per sound.
- **Learned sounds:** the two rain moods are three layers learned from a storm recording: glass taps, metal taps and outside rain. Real taps are single clicks under half a millisecond, which is why earlier noise-burst rain sounded artificial. Night storm adds thunder rolls rebuilt from the same recording and generated wind. Winter park is a texture-synthesised park with a song thrush sung live from traced note shapes. Wind on the hill is generated. About 14MB in `sounds/`, downloaded the first time each mood plays and kept by the service worker. The loops are FLAC, which is lossless so they still loop without a seam, at about half the size of the original WAV files (8 November 2026). The thunder rolls stay MP3, as they play once.
- [x] **Licences checked by Lloyd (8 November 2026):** every Freesound source allows this use with attribution, except the Rich Wise song thrush (795708), which needs none. The Help page credits daveincamas (59028) and klankbeeld (818307), and thanks Rich Wise. Keep those credits whenever these sounds ship. InspectorJ's rain on windows (346642) was used while listening but isn't in any file, so it isn't credited; credit it if a future sound uses it.
- [ ] Lloyd to listen to every mood on headphones and a phone speaker, and judge the levels against brown noise. They were matched by measurement.
- **Rain on the window is much warmer (8 November 2026):** Lloyd found the two rain moods sounded the same until the thunder came in. Rain on the window now starts with Tone at −75 (first −60, then a little warmer at Lloyd's request), against −15 for Night storm.
- [ ] Lloyd to test on a real iPhone: check that Night storm starts quickly on mobile data, and that every mood plays in the web app in Safari as well as in the iPhone app.
- **Less memory on the web (8 November 2026):** decoding the learned sounds the usual way made Night storm hold about 120MB, mostly thunder. Now each loop is decoded once into 16-bit samples at the rate it was made at and played by `sound-worklet.js`, an AudioWorklet, the same design as the iPhone app's SoundBank. Thunder rolls stream from their files through one audio player, so they're never held decoded. Night storm now holds about 16MB.
- **Ready by play (8 November 2026):** the current mood's files are fetched and decoded as the app opens, behind the launch screen, so pressing play is instant. Only the current mood is fetched, to spare mobile data. The launch screen isn't made longer; anything not ready fades in when it arrives. The iPhone app already decodes the current mood as it opens.
- [ ] Lloyd to test the web app on an Android phone and in Safari: worklet sound, thunder rolls, and offline after a first play.
- [ ] Not tried yet: taps made live from a 1MB bank instead of looped files. It halves the download and never repeats, but uses more battery.
- [x] Port moods, Sounds and Adjust sound to the iPhone app (8 November 2026, same branch). Lloyd to run it from Xcode and test.

### Analytics

Decided 5 November 2026: anonymous counts in the web app, with PostHog's EU servers.

- **What's sent:** `app opened` (whether it's installed, and iPhone or iPad, Android or computer), `session started` (the music, breath sound, pace, pattern, session type and its times, scene and colours) and `session ended` (finished, stopped or closed, and minutes played).
- **Privacy:** no cookies or anything else stored on the device, and a random number per page load in place of an ID. The page sends to `/ingest` on Swellotic's own site. `functions/ingest.js`, a Cloudflare Pages Function, forwards only those three events with plain values, adds the country, and never passes on the IP address. Events can't create person profiles. That should mean no consent banner is needed under UK rules, but it isn't legal advice.
- **No PostHog script:** the app sends its own small messages, so nothing loads from another site and the "own site" rule holds.
- **Only on the live site:** `swellotic.com` and `.pages.dev` addresses send counts. Local testing doesn't.
- **What it can't show:** whether people come back after a week. That needs an ID kept on the device and consent, so Phase 6 asks testers directly instead.
- **iPhone app:** no analytics. App Store Connect gives downloads and usage from people who opt in.
- [ ] Lloyd: in PostHog's project settings, turn off session replay and autocapture, and turn on "Discard client IP data" as a second safeguard.
- [x] Mention the counts in the privacy notice in Phase 5.

## Phase 5: Launch checks

- [ ] Add automated browser tests for start and stop, every sound and visual, the sliders, and saved settings.
- [ ] Run a full accessibility audit, including screen readers, keyboard use and text contrast over the moving scenes.
- [ ] Check performance on an older phone, especially Lava lamp.
- [x] Add a privacy notice covering local settings, what the host logs and the anonymous counts: `privacy.html`, linked from Settings in both apps. It names Lloyd Evans as the maker, at his request on 6 November 2026.
- [x] Add an About page with the health note, and credit any third-party fonts: `support.html`, called Help, which also credits Musopen and the performers. It doubles as the App Store support page.
- [ ] Lloyd: set up Cloudflare Email Routing so `hello@swellotic.com`, the contact address on both pages, forwards to his own email.
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
- [x] Catch up with the web app: the session drawer with Timer and Interval, "Swell" and "Rest" with the chime, and the Classical mix with its strip above the player bar and "Save all for offline". "Audio files" was removed, as on the web.
- [ ] Lloyd to test the Classical mix on his iPhone once swellotic.com is live, including offline, skipping, repeat-one and a rest mid-piece.
- [ ] Lloyd to run it on his iPhone and fill in the iPhone column of the Phase 2 table using the iOS app.
- [ ] Lloyd to listen to every sound against the web version, especially the room effect, which uses Apple's reverb instead of the web app's.
- [x] Bundle identifier `com.swellotic.app`, from `swellotic.com`. It can't change once the app is on the App Store.
- [ ] Set up an Apple Developer account for TestFlight.
- [ ] App Store listing, privacy details and screenshots. Review all copy against the health claim rules. Privacy policy URL: `https://swellotic.com/privacy.html`. Support URL: `https://swellotic.com/support.html`. Privacy label: Data Not Collected, since the iPhone app sends no counts.
- [ ] Once App Store Connect gives the app its ID, add Apple's Smart App Banner to `index.html`, where a comment marks the spot, so iPhone visitors are offered the app.
- [x] iPad and Mac layout: Settings as a side panel, Session as a popover by its button. Both stay sheets on iPhone.
- [ ] Lloyd to check the iPad layout on his iPad, including turning it and Split View.
- [ ] Later: show what's playing in Apple Music, Apple Watch, widgets and Focus mode.

### iOS decisions

- **Why native:** iOS doesn't let web pages keep sound playing in the background while mixing with other apps. A native app can, and can ignore the silent switch. Lloyd also wants the App Store and room to add Watch and widgets. Haptics aren't needed yet.
- **Native SwiftUI, not Capacitor:** Web Audio inside a wrapper can still go quiet in the background, so a wrapper might not fix the main problem. SwiftUI uses Apple's own audio engine. The cost is two codebases to keep in step.
- **One timeline:** the audio thread owns it and starts each breath sound on the exact sample. The visuals read where it is through a lock-free snapshot. When the phone pauses sound, the breath stops and carries on from where it was, as on the web.
- **Sound session:** "My music app" uses the playback category with mixing, so Spotify keeps playing. Other tracks use playback without mixing, so they take over from other apps. Both ignore the silent switch.
- **Balancing with a music app (2026-11-05):** Lloyd found the breaths quiet next to his music app. iOS doesn't let one app set another's volume, so "My music app" now gives breaths about 9.5 dB more headroom, with the limiter catching peaks, and adds "Lower my music app", on by default. That asks iOS to duck other apps steadily for the whole session. iOS sets how much, and the duck never follows the breath, which keeps clear of rhythmic modulation. The web app can't do either.
- **Keep "Lower my music app" on by default (6 November 2026):** Lloyd tried it off and the breaths weren't audible enough. iOS lowers other apps by a fixed, large amount that apps can't adjust, but the side buttons still turn the music up high, so the person keeps control of the music and the breath stays audible. Don't make it gentler or turn it off by default.
- **Headphones:** when headphones disconnect, Swellotic pauses, as Apple recommends, so it never plays out loud by surprise. Changed 6 November 2026 from stopping, which lost Lloyd's place in an Interval session. The breath, session clock, swell or rest and classical piece all pause together and carry on from the same moment with "Tap to resume" or the lock screen's play. Nothing restarts it automatically.
- **Room effect:** a lowpass filter and Apple's medium hall reverb, instead of the web app's generated impulse. Lloyd to judge.
- **Classical mix:** pieces download from `swellotic.com` the first time they play and are kept on the phone, so the phone only ever contacts Swellotic's own site. The next piece downloads while the current one plays. "Save all for offline" downloads the whole set, and turning it off frees the space. Kept pieces are left out of iCloud backups. Pieces stream from the file a few seconds at a time, so they never sit in memory. The app reads the latest `classical.json` from the site, and starts from a copy built into the app.
- **Rests:** the sound engine fades the breath and generated music on its own clock, so rests stay exact with the screen locked. A classical piece fades and pauses during a rest, and carries on from the same place for the next swell.
- **Minimum iOS 18,** for lock-free atomics in Swift. iOS 26 gets Liquid Glass controls. Earlier versions get a frosted material.
- **App Store category:** Productivity, not Health & Fitness, to keep clear of medical claims.
- **Not ported:** the service worker and update prompt, since the App Store handles updates. Spoken words stay hidden until the clips exist, as on the web.
- **Sound moods on iPhone (8 November 2026, `claude/sound-moods` branch):** the same moods, groups, Sounds rename and Adjust sound as the web app. Adjust sound is a page pushed from the Sounds section. The sound files ship inside the app in `Resources/Sounds/`, so every mood works offline from the first launch; they're copies of `sounds/`, so change both together. Each file is decoded once in the background when its mood is first chosen, into 16-bit memory the audio thread reads without locks (`Core/SoundBank.swift`), about 36MB if every mood is played. Distance, Tone, Low, Middle and High use Apple's EQ and a small room reverb after the music mixer, so they also apply to the Classical mix. Mix layers and the thrush are in the core engine (`Core/LearnedSounds.swift`). Old Rain and Wind settings move to Rain on the window and Wind on the hill.

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
- **iPad and Mac panels (8 November 2026):** half-height sheets floated mid-screen on iPad, cut off their content and covered the player bar. Settings is now a side panel (SwiftUI's inspector), so the scene and player bar stay in view while changing things, as in the web app on wide screens. Session is a popover from its button. On iPhone, and in narrow Split View, both become sheets from the bottom. The same layout carries over to a Mac build.
