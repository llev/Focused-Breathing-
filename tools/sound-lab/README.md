# Sound lab

The scripts that made the learned sounds in `sounds/`. They're kept so the sounds can be remade or tuned. The source recordings aren't in this repo; download them from Freesound and check each licence first.

Needs Python 3 with `numpy`, `scipy` and `soundfile`, and `ffmpeg`. Run each script from a working folder that holds the recordings, converted to 44.1 kHz stereo WAV.

| Sound | Source recording | How it's made |
|---|---|---|
| Rain layers: `storm-glass.flac`, `storm-metal.flac`, `storm-outside.flac` | daveincamas, thunderstorm (Freesound 59028), saved as `storm.wav` | `taps.py storm.wav 125 205 taps.npz wash_gated.wav` finds about 3,600 taps in 80 seconds of rain, keeps each one's shape, and takes the taps out to leave the outside rain. `layers.py` then builds three 20-second loops: glass taps (centre below 6 kHz) and metal taps as single clicks shaped by measured spectra, and the outside rain by texture synthesis. |
| Thunder rolls: `thunder1.mp3` to `thunder6.mp3` | The same storm recording | `thunder.py storm.wav thunder` measures each thunder event's swell, fade and flicker above the rain, and rebuilds new rolls from noise with a random stretch, level and side. Encoded at 128 kbps, as they play once rather than loop. |
| Park: `park.flac` | klankbeeld, city park winter day (Freesound 818307), saved as `park.wav` | `texture.py park.wav 15 30 park_bed.wav` is sound texture synthesis after McDermott and Simoncelli (2011): new noise given the recording's band levels, flicker and band-to-band movement. |
| Thrush: `thrush.json` | Rich Wise, song thrush (Freesound 795708), saved as `thrush.wav` | `birds.py thrush.wav thrush.json 24` traces each note's pitch and loudness and groups them into phrases. The app sings them with a tone, in a new order each time. |
| Wind: `wind.flac` | None | `wind.py` makes a 60-second loop of noise following slow, irregular gusts. |

Everything is circular, so each file loops without a seam. The scripts write WAV; convert each loop to FLAC before adding it, which halves the size without changing a single sample:

```bash
ffmpeg -i park.wav -c:a flac -compression_level 12 park.flac
```

Thunder rolls stay MP3 at 128 kbps, as they play once rather than loop. Lossy formats like MP3 and AAC add a short silence at the start, which would make a loop gap.

## Credits

The source recordings are licensed for this use with attribution, except the thrush. Keep these credits on the Help page (`support.html`) whenever the sounds ship:

- daveincamas, thunderstorm (Freesound 59028): Rain on the window and Night storm
- klankbeeld, city park winter day (Freesound 818307): Winter park
- Rich Wise, song thrush (Freesound 795708): no attribution needed, thanked as a courtesy Files in `sounds/` are kept by the service worker under their names, so give a remade file a new name rather than replacing it.

Claude can't hear the results. Each change was checked by comparing band levels, spikiness and spectrograms with the recording, then judged by Lloyd by ear.
