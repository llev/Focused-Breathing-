# Swellotic

**Breathe. Listen. Focus.**

A breathing guide with music or ambient sound, and a separate volume for each. It's designed to run quietly in the background while you work, including on one pair of headphones on a train or in an office.

> **Status:** working prototype. It can be installed and works offline, but it isn't hosted anywhere yet. See [docs/ROADMAP.md](docs/ROADMAP.md) for the work left before launch.

## What it does

- **Breathing pace:** 2 to 12 breaths a minute, with even or longer out-breaths, and an option to slow down gradually
- **Breath sounds:** singing bowl, gong, soft piano, wooden marimba, soft hum, chime, ocean or silent, each lasting the whole breath. Spoken words return once recorded clips are added.
- **Background sound:** brown noise, pink noise, rain, beach, stream, wind, fireplace, ambient chords or soft keys, all generated in the browser
- **Your own audio:** add audio files, or play Spotify, Apple Music or another app alongside it
- **Separate volumes:** breath and music each have their own slider
- **Music in the room:** keeps the breath close and makes the music sound further away in headphones
- **Visuals:** lava lamp, bloom, rings, aurora or tide, in six colour palettes

## Run it locally

There's no build step or dependency to install. You need a local web server because the app is made of separate files.

```bash
python3 -m http.server 8000
```

Then open <http://localhost:8000>. Sound starts after you press play.

The service worker caches the app, so after a change you may see the old version. Reload twice, or tick "Update on reload" in Chrome DevTools under Application, then Service workers.

## Releasing a change

Bump `VERSION` in `sw.js` with every release. Without that, people who have already opened the app keep the old files. If you add a file, add it to the `FILES` list in `sw.js` too.

## iPhone app

A native iPhone version is in [`ios/`](ios/README.md). It keeps playing when the screen locks and plays alongside Spotify or Apple Music. Open `ios/Swellotic.xcodeproj` in Xcode to run it.

## Project files

| File | Purpose |
| --- | --- |
| `index.html` | Page structure |
| `styles.css` | All styling |
| `app.js` | Audio, breathing timeline, visuals and controls |
| `sw.js` | Service worker for offline use and updates |
| `manifest.webmanifest` | App name, colours and icons for installing |
| `icons/` | App icons, drawn in `icon.svg` |
| `fonts/` | Bundled fonts and their licences |
| `tools/make-voice.mjs` | Makes the spoken words clips with Azure AI Speech. Run once, not part of the app |
| `ios/` | Native iPhone app in SwiftUI. See `ios/README.md` |
| `CLAUDE.md` | Project rules and context for Claude Code |
| `docs/ROADMAP.md` | Work needed to make this a publishable web app |

## Finishing it with Claude Code

Clone the repo, open the folder in Claude Code, and ask:

> Read docs/ROADMAP.md and start on the first unfinished phase.

## Health note

Swellotic is a general wellbeing and focus tool. It isn't a medical device and doesn't diagnose, treat or prevent any condition. If you feel light-headed, stop and breathe normally.

## Licence

No open-source licence has been chosen, so all rights are reserved for now. The code is public to read, but this doesn't give anyone permission to reuse it.
