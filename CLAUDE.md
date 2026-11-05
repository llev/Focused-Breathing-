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
- All background sound is generated in code, so it needs no audio files.

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
- People's audio files stay on their device and are never uploaded.

### Design

- The single dark look and frosted glass controls are deliberate. It should feel like a premium, friendly iPhone app.
- The player bar stays on screen with play, Breath, Music and Settings.
- Sections stay collapsible and show their current setting when closed.
- Design for phones first, with touch targets of at least 44px.
- Keep `prefers-reduced-motion` support: visuals become a gentle colour fade.
- Avoid clutter. The app should stay out of the way during work.

### Copy

- Use UK English and plain, friendly language.
- Name things by what people recognise, such as "Breath" and "Music", not technical terms.

## Testing

- Run locally with `python3 -m http.server 8000`.
- There's no automated test suite yet. Phase 5 of the roadmap adds one.
- Passing in a desktop browser doesn't prove the app works on a phone. Audio features need testing on a real iPhone and a real Android phone.
- Claude can't hear the output, so ask Lloyd to judge how anything sounds.
