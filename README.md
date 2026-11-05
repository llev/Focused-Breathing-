# Swellotic

**Breathe. Listen. Focus.**

A breathing guide with music or ambient sound, and a separate volume for each. It's designed to run quietly in the background while you work, including on one pair of headphones on a train or in an office.

> **Status:** working prototype. It isn't an installable app yet. See [docs/ROADMAP.md](docs/ROADMAP.md) for the work left before launch.

## What it does

- **Breathing pace:** 2 to 12 breaths a minute, with even or longer out-breaths, and an option to slow down gradually
- **Breath sounds:** singing bowl, gong, spoken words, soft piano, wooden marimba, soft hum, chime, ocean or silent
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

## Project files

| File | Purpose |
| --- | --- |
| `index.html` | Page structure |
| `styles.css` | All styling |
| `app.js` | Audio, breathing timeline, visuals and controls |
| `CLAUDE.md` | Project rules and context for Claude Code |
| `docs/ROADMAP.md` | Work needed to make this a publishable web app |

## Finishing it with Claude Code

Clone the repo, open the folder in Claude Code, and ask:

> Read docs/ROADMAP.md and start on the first unfinished phase.

## Health note

Swellotic is a general wellbeing and focus tool. It isn't a medical device and doesn't diagnose, treat or prevent any condition. If you feel light-headed, stop and breathe normally.

## Licence

No open-source licence has been chosen, so all rights are reserved for now. The code is public to read, but this doesn't give anyone permission to reuse it.
