# Swellotic for iPhone

A native SwiftUI version of Swellotic. It has the same breathing timeline, breath sounds, generated music, scenes and launch screen as the web app. It also does what a web app can't on iPhone:

- **Keeps playing when the screen locks** or you switch apps, using iOS background audio.
- **Plays alongside Spotify or Apple Music.** With "My music app", Swellotic mixes with them instead of stopping them, and can turn them down while it plays.
- **Ignores the silent switch**, so the breaths stay audible.
- **Lock-screen controls** for play and stop when Swellotic is playing its own music.
- **Remembers settings** on the phone. Nothing leaves the device.

## Run it on your iPhone

You need a Mac with Xcode 26 or later and an iPhone on iOS 18 or later.

1. Open `ios/Swellotic.xcodeproj` in Xcode.
2. Select the **Swellotic** target, then **Signing & Capabilities**. Choose your team. A free Apple ID works for your own phone.
3. If Xcode shows a red error about the **Bundle Identifier**, change `app.swellotic.ios` in that box to something only you would use, such as `com.yourname.swellotic`. It's the app's unique ID, which Apple uses to tell apps apart. People never see it.
4. Connect your iPhone, choose it as the run destination and press **Run**. The first time, approve the developer on the phone under **Settings > General > VPN & Device Management**, and turn on **Developer Mode** if asked.

With a free Apple ID the app stops opening after 7 days, so run it from Xcode again. A paid Apple Developer account ($99 a year) removes that limit and lets you share it with testers through TestFlight.

## What to test on the phone

Claude can't hear the app, so these need a person and a real iPhone. Record results in the Phase 2 table in `docs/ROADMAP.md`.

- Play for 10 minutes, then lock the screen. Does the sound carry on?
- "My music app" with Spotify playing: do both keep going, locked and unlocked?
- Take a call or use Siri, then return. Does the sound come back, or does "Tap to resume" appear?
- Unplug or disconnect headphones. Swellotic should stop rather than play out loud.
- Flip the silent switch. The breaths should still play.
- How every breath sound and background sound compares with the web version.

## How it's built

| Folder | Purpose |
| --- | --- |
| `Swellotic/Core/` | The sound engine and breathing timeline. Plain Swift with no Apple-only frameworks, so it can be tested on its own |
| `Swellotic/Audio/` | Connects the engine to iOS: audio session, background audio, interruptions, headphones, lock screen, audio files |
| `Swellotic/App/` | Settings, names people see and the model that connects screen and sound |
| `Swellotic/Views/` | The screen, player bar, settings sheet, scenes and launch screen |
| `Tests/SwellCoreTests/` | Tests for the timeline and sound engine |
| `Package.swift` | Lets `swift test` run the core tests without a simulator |

The rules in the main `CLAUDE.md` apply here too. In particular, there's one timeline: the audio thread owns it and plays each breath sound on the exact sample, and the visuals read where it is through a lock-free snapshot. Don't give the visuals their own timer.

New files added inside `Swellotic/` join the app automatically, because the Xcode project uses a synchronised folder.

## Checks

```bash
cd ios && swift test
```

GitHub Actions runs the tests and builds the app for the Simulator whenever anything in `ios/` changes. See `.github/workflows/ios.yml`.
