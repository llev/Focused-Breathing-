(() => {
  const $ = id => document.getElementById(id);
  const S = { bpm: 6, ratio: 'even', cue: 'bowl', breathVol: 35, musicVol: 55, room: true, ease: false, track: 'brown', limit: 0, visual: 'lava', palette: 'sunset', open: null, words: true, countdown: false, piece: 0, repeatOne: false, saveAll: false, customMin: 40, mode: 'timer', swellMin: 25, restMin: 5, rounds: 4 };
  try { Object.assign(S, JSON.parse(localStorage.getItem('breathing-room') || '{}')); } catch (e) {}
  /* "Audio files" was replaced by the classical mix. */
  if (S.track === 'own') S.track = 'classical';
  /* Rain and Wind became moods. */
  if (S.track === 'rain') S.track = 'window';
  if (S.track === 'wind') S.track = 'hill';
  /* First light's sound became Winter park. */
  if (S.track === 'dawn') S.track = 'park';
  if (S.adjust && S.adjust.dawn) { S.adjust.park = S.adjust.dawn; delete S.adjust.dawn; }
  /* Fine tune went from eight bands to three. */
  if (S.adjust) Object.values(S.adjust).forEach(a => { if (a && a.bands && a.bands.length !== 3) delete a.bands; });
  if (!S.adjust || typeof S.adjust !== 'object') S.adjust = {};
  /* The interval switch became a tab. */
  if (S.intervals) S.mode = 'interval';
  delete S.intervals;
  const save = () => { try { localStorage.setItem('breathing-room', JSON.stringify(S)); } catch (e) {} };

  /* Anonymous counts, passed on to PostHog by functions/ingest.js on Swellotic's own site. Nothing is stored on the device
     and no one is identified: each page load gets a random number that's never saved, and the server drops the IP address.
     Only the live site sends them, so local testing never does. */
  const visit = Math.random().toString(36).slice(2, 14);
  const counting = /(^|\.)swellotic\.com$|\.pages\.dev$/.test(location.hostname);
  function count(event, props) {
    if (!counting) return;
    const body = JSON.stringify({ event, visit, props: props || {} });
    try { if (navigator.sendBeacon && navigator.sendBeacon('ingest', body)) return; } catch (e) {}
    fetch('ingest', { method: 'POST', body, keepalive: true }).catch(() => {});
  }
  /* The choices behind a session, so we can see which sounds and session types people use. */
  const choices = () => ({
    music: S.track, breath_sound: S.cue, breaths_per_minute: +S.bpm, pattern: S.ratio, slow_down: !!S.ease, room: !!S.room,
    session: S.mode, timer_minutes: S.mode === 'timer' ? limitMin() : null,
    swell_minutes: S.mode === 'interval' ? +S.swellMin : null, rest_minutes: S.mode === 'interval' ? +S.restMin : null,
    rounds: S.mode === 'interval' ? +S.rounds : null, scene: S.visual, colours: S.palette
  });

  const RATIOS = { even: ['Even', .5], long: ['Longer out', .4], longest: ['Much longer out', 1 / 3] };
  const CUES = { bowl: 'Singing bowl', gong: 'Gong', words: 'Spoken words', piano: 'Soft piano', wood: 'Wooden marimba', tone: 'Soft hum', chime: 'Chime', breath: 'Ocean', none: 'Silent' };
  /* Each sound's note says what you'll hear, then whether it works offline. Keep these in step with Settings.swift. */
  const MADE = ' Made on your device, so it works offline.';
  const DOWNLOADS = ' It downloads the first time you play it, then works offline.';
  const SHAPED = ' Shaped from a real recording.' + DOWNLOADS;
  const MOODS = {
    window: ['Rain on the window', 'Rain against glass, a few taps on metal, and heavier rain outside.' + SHAPED],
    storm: ['Night storm', 'Heavy rain with thunder rolling through, and a little wind.' + SHAPED],
    fire: ['Fireside', 'A low, steady fire with gentle crackles.' + MADE],
    stream: ['Woodland stream', 'Water running over stones, steady and soft.' + MADE],
    beach: ['Calm shore', 'Slow, soft waves rolling in and drawing back.' + MADE],
    park: ['Winter park', 'A quiet park on a cold day, with a song thrush singing nearby.' + SHAPED],
    hill: ['Wind on the hill', 'Slow, uneven gusts of wind across open ground.' + DOWNLOADS]
  };
  const NOISES = {
    brown: ['Brown noise', 'A deep, soft rumble, with most of its weight in the low sounds.' + MADE],
    pink: ['Pink noise', 'A steady, even hiss, softer than white noise.' + MADE],
    green: ['Green noise', 'A gentle hiss centred on the middle sounds.' + MADE]
  };
  const MUSICS = {
    ambient: ['Ambient', 'Slow, warm chords that drift gently from one to the next.' + MADE],
    keys: ['Soft keys', 'Quiet, unhurried piano notes over a low note every few seconds.' + MADE],
    classical: ['Classical mix', 'Calm public domain recordings made for Musopen, shared on Wikimedia Commons. The set repeats when it reaches the end, and pieces you listen to are saved for offline use.'],
    none: ['My music app', 'Play music in Spotify, Apple Music or any other app, then press play here. The Breath slider changes only the breaths, and your music app controls the music. On a phone, the side buttons change both, so use the Breath slider to balance them.']
  };
  const TRACKS = { ...MOODS, ...NOISES, ...MUSICS };
  if (!TRACKS[S.track]) S.track = 'brown';

  /* Adjust sound: every sound but My music app has Distance and Tone. Fine tune holds its layers, if it has any, and three
     frequency bands: a low shelf, a broad middle and a high shelf. */
  const BANDS = [['lowshelf', 200, 0], ['peaking', 1000, .7], ['highshelf', 4000, 0]];
  const BAND_NAMES = ['Low', 'Middle', 'High'];
  const RAIN = [['glass', 'Rain on glass'], ['metal', 'Taps on metal'], ['outside', 'Rain outside']];
  const LAYERS = {
    window: RAIN, storm: [...RAIN, ['thunder', 'Thunder'], ['wind', 'Wind']],
    fire: [['body', 'Fire'], ['crackle', 'Crackles']],
    park: [['park', 'Park'], ['birds', 'Birdsong']]
  };
  /* How each mood starts. Layers run from 0 to 100, where 50 is the designed level. */
  const DESIGNED = {
    window: { tone: -75 },  /* much warmer than Night storm, so the two rain moods sound different before any thunder */
    storm: { distance: 20, tone: -15, layers: { wind: 30 } },
    park: { distance: 15, layers: { park: 38, birds: 62 } },
    hill: { distance: 25 },
    beach: { distance: 30, tone: -10 },
    fire: { distance: 10, tone: -20 }
  };
  const designed = k => ({ distance: 0, tone: 0, bands: BANDS.map(() => 0), layers: {}, ...(DESIGNED[k] || {}) });
  const adj = k => { const d = designed(k), a = S.adjust[k] || {}; return { ...d, ...a, bands: a.bands || d.bands, layers: { ...d.layers, ...(a.layers || {}) } }; };
  const layerValue = (a, key) => a.layers[key] ?? 50;
  const adjustable = k => k !== 'none';
  const LIMITS = { 0: 'No limit', 25: '25 min', 50: '50 min', 90: '90 min', custom: 'Custom' };
  const limitMin = () => S.limit === 'custom' ? S.customMin : +S.limit;
  const ROUNDS = { 0: 'Until I stop', 2: '2 rounds', 4: '4 rounds', 6: '6 rounds' };
  /* How long the whole session lasts in seconds, or 0 for no end. Interval sessions end after the last swell. */
  const sessionLength = () => S.mode === 'interval'
    ? (+S.rounds ? (S.rounds * S.swellMin + (S.rounds - 1) * S.restMin) * 60 : 0)
    : limitMin() * 60;
  const VISUALS = { lava: 'Lava lamp', bloom: 'Bloom', rings: 'Rings', aurora: 'Aurora', tide: 'Tide' };
  const PALETTES = {
    sunset: { name: 'Sunset', tint: '#ffb27a', ground: ['#2a1238', '#5a1f3f'], colors: ['#ff7a59', '#ffb347', '#e8487e'] },
    sea: { name: 'Sea', tint: '#7fe3d3', ground: ['#0d2b3a', '#123f4f'], colors: ['#3fb6b2', '#2f8fd0', '#8fe0c8'] },
    ember: { name: 'Ember', tint: '#ff9a5c', ground: ['#2b0a12', '#4a0f1c'], colors: ['#ff4d2e', '#ff9a1f', '#d61f6b'] },
    meadow: { name: 'Meadow', tint: '#b7e36a', ground: ['#0f2a1e', '#1c3f2a'], colors: ['#6fcf6a', '#d6d44c', '#2fae8a'] },
    heather: { name: 'Heather', tint: '#d2a6ff', ground: ['#1f1638', '#3b1f55'], colors: ['#b377e8', '#f08fc8', '#6d8cf0'] },
    night: { name: 'Night', tint: '#a9b8ff', ground: ['#07080f', '#0e1020'], colors: ['#2b3a6b', '#3c2f63', '#1f4a5c'] }
  };

  const chips = (host, name, items, key, onChange) => {
    Object.entries(items).forEach(([value, item]) => {
      const label = document.createElement('label');
      const input = Object.assign(document.createElement('input'), { type: 'radio', name, value, checked: String(S[key]) === value, id: name + '-' + value });
      const span = document.createElement('span');
      span.textContent = Array.isArray(item) ? item[0] : item;
      input.addEventListener('change', () => { S[key] = value; save(); onChange(); });
      label.append(input, span); host.append(label);
    });
  };

  /* Audio */
  const midi = n => 440 * Math.pow(2, (n - 69) / 12);
  const gainCurve = v => (v / 100) ** 2;
  let ctx = null, A = null, running = false, sessionStart = 0, voice = null, wake = null;
  let cueNodes = [];

  function loopBuffer(seconds, channels, make) {
    const rate = ctx.sampleRate, n = Math.floor(seconds * rate), fade = Math.floor(rate * .5);
    const buf = ctx.createBuffer(channels, n, rate);
    for (let c = 0; c < channels; c++) {
      const raw = make(n + fade), out = buf.getChannelData(c);
      for (let i = 0; i < n; i++) out[i] = raw[i];
      for (let i = 0; i < fade; i++) out[i] = raw[i] * Math.sqrt(i / fade) + raw[n + i] * Math.sqrt(1 - i / fade);
    }
    return buf;
  }
  const white = n => { const a = new Float32Array(n); for (let i = 0; i < n; i++) a[i] = Math.random() * 2 - 1; return a; };
  const pink = n => {
    const a = new Float32Array(n); let b0 = 0, b1 = 0, b2 = 0;
    for (let i = 0; i < n; i++) {
      const w = Math.random() * 2 - 1;
      b0 = .99765 * b0 + w * .099046; b1 = .963 * b1 + w * .2965164; b2 = .57 * b2 + w * 1.0526913;
      a[i] = (b0 + b1 + b2 + w * .1848) * .11;
    }
    return a;
  };
  const brown = n => { const a = new Float32Array(n); let l = 0; for (let i = 0; i < n; i++) { l = (l + .02 * (Math.random() * 2 - 1)) / 1.02; a[i] = l * 3.5; } return a; };

  function impulse() {
    const rate = ctx.sampleRate, n = Math.floor(rate * 1.7), buf = ctx.createBuffer(2, n, rate);
    for (let c = 0; c < 2; c++) {
      const d = buf.getChannelData(c);
      for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / n, 3.2);
    }
    return buf;
  }

  /* Ambient lets an iPhone keep another app's music playing alongside the breaths. */
  function setSession() {
    try { if (navigator.audioSession) navigator.audioSession.type = S.track === 'none' ? 'ambient' : 'playback'; } catch (e) {}
  }

  function ensureAudio() {
    if (ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    ctx = new AC({ latencyHint: 'playback' });
    setSession();
    const master = ctx.createGain(), limit = ctx.createDynamicsCompressor();
    master.gain.value = 0; master.connect(limit); limit.connect(ctx.destination);
    const breathBus = ctx.createGain(), musicLevel = ctx.createGain(), musicBus = ctx.createGain();
    const dry = ctx.createGain(), wet = ctx.createGain(), far = ctx.createBiquadFilter(), hall = ctx.createConvolver();
    far.type = 'lowpass'; far.frequency.value = 2200; hall.buffer = impulse();
    breathBus.connect(master); musicLevel.connect(master);
    musicBus.connect(dry); dry.connect(far); far.connect(musicLevel);
    musicBus.connect(hall); hall.connect(wet); wet.connect(musicLevel);
    const alert = ctx.createGain(); alert.connect(limit);
    /* Distance sends each sound to its own echo, separate from Put sounds in the room. */
    const distant = ctx.createConvolver(); distant.buffer = impulse(); distant.connect(musicLevel);
    A = { master, breathBus, musicLevel, musicBus, dry, wet, far, alert, distant,
      cueNoise: loopBuffer(6, 1, white), brownBuf: null, whiteBuf: null };
    /* The worklet that plays the learned sounds. Loops decoded before the first tap are handed over as soon as it's ready. */
    A.ready = ctx.audioWorklet
      ? ctx.audioWorklet.addModule('sound-worklet.js').then(() => {
        A.bank = new AudioWorkletNode(ctx, 'swellotic-bank', { numberOfInputs: 0, numberOfOutputs: 1 }); sendClips(); })
      : Promise.reject(new Error('This browser can\'t play the learned sounds.'));
    A.ready.catch(() => {});
    newCueBus();
    applyLevels();
    loadClips();
    ctx.onstatechange = () => {
      if (!running || held) return;
      if (ctx.state === 'running') soundBack();
      else { paused = true; if (owner) player.pause(); tryResume(); }
    };
  }

  /* Phones pause web audio when another app takes over, the screen locks or the app leaves the screen.
     Restart it when Swellotic is back on screen, and ask for a tap where the phone won't allow that. */
  let paused = false;
  async function tryResume() {
    if (!running || held || !ctx || ctx.state === 'running' || document.hidden) return;
    try { await Promise.race([ctx.resume(), new Promise(r => setTimeout(r, 1500))]); } catch (e) {}
    if (!running || held) return;
    if (ctx.state === 'running') soundBack(); else showResume(true);
  }

  /* Pausing a session keeps its place. The audio clock stops, so the breath, the session clock, any swell or rest and the
     sounds all wait together and carry on from the same moment. */
  let held = false;
  function hold() {
    if (!running || held) return;
    held = true; paused = true; showResume(false);
    const t = ctx.currentTime;
    A.master.gain.cancelScheduledValues(t); A.master.gain.setTargetAtTime(0, t, .05);
    setTimeout(() => {
      if (!held) return;
      if (owner) player.pause();
      if (rollPlayer.dataset.rolling) rollPlayer.pause();
      ctx.suspend();
    }, 250);
    if (wake) { wake.release().catch(() => {}); wake = null; }
    setGo(); $('status').textContent = 'Paused.';
  }
  async function unhold() {
    if (!held) return;
    held = false; paused = true; setGo();
    try { await ctx.resume(); } catch (e) {}
    if (!running || held) return;
    if (ctx.state !== 'running') { showResume(true); return; }
    if (rollPlayer.dataset.rolling) rollPlayer.play().catch(() => {});
    $('status').textContent = segment === 'rest' ? 'Time for a break. The next swell starts by itself.' : '';
    soundBack();
  }
  function soundBack() {
    if (!paused) return;
    paused = false; showResume(false);
    /* The audio clock stops while paused, so the breath carries on from where it was. Replan the breath sounds and fade in gently. */
    const t = ctx.currentTime;
    A.master.gain.cancelScheduledValues(t); A.master.gain.setValueAtTime(0, t); A.master.gain.linearRampToValueAtTime(segment === 'rest' ? 0 : 1, t + .8);
    switchCue();
    if (owner && segment !== 'rest') player.play().catch(() => {});
    lockScreen();
  }
  function showResume(show) { $('resume').hidden = !show; showEnd(); }
  function showEnd() { $('end').hidden = !(running && (held || !$('resume').hidden)); }

  function newCueBus() { A.cueBus = ctx.createGain(); A.cueBus.connect(A.breathBus); }

  function applyLevels() {
    if (!A) return;
    const t = ctx.currentTime;
    A.breathBus.gain.setTargetAtTime(gainCurve(S.breathVol) * .9, t, .05);
    A.musicLevel.gain.setTargetAtTime(gainCurve(S.musicVol), t, .05);
    A.dry.gain.setTargetAtTime(S.room ? .45 : 1, t, .15);
    A.wet.gain.setTargetAtTime(S.room ? .75 : 0, t, .15);
    A.far.frequency.setTargetAtTime(S.room ? 2200 : 18000, t, .15);
  }

  const envIn = x => Math.sin(Math.PI * Math.pow(x, 1.4));
  const envOut = x => Math.sin(Math.PI * Math.pow(x, .7));
  const curve = fn => { const c = new Float32Array(48); for (let i = 0; i < 48; i++) c[i] = fn(i / 47); return c; };

  function playCue(type, start, end) {
    const dur = end - start - .002, rising = type === 'in';
    /* A breath that should already have started is skipped, so missed breaths never play all at once. */
    if (S.cue === 'none' || start < ctx.currentTime - .05) return;
    if (S.cue === 'words') return clip(type, start);
    /* Struck sounds use A on the in-breath and D on the out-breath, which sit with the generated music. */
    const note = rising ? 69 : 62;
    if (S.cue === 'chime') return bell(midi(note + 12), [[1, 1, 1]], start, dur, rising, .02, .3);
    if (S.cue === 'piano') return bell(midi(note), [[1, 1, 1], [2, .16, .7], [3, .05, .5]], start, dur, rising, .015, .3);
    if (S.cue === 'wood') return bell(midi(note + 12), [[1, 1, 1], [3.9, .12, .3]], start, dur, rising, .006, .34);
    if (S.cue === 'bowl') return bell(midi(note), [[1, .7, 1], [1.004, .7, 1], [2.71, .16, .6]], start, dur, rising, .35, .2);
    if (S.cue === 'gong') return bell(midi(note - 24), [[1, 1, 1], [1.48, .5, .8], [2.02, .34, .65], [2.76, .16, .5], [3.41, .08, .35]], start, dur, rising, .05, .3);
    const env = ctx.createGain(); env.gain.value = 0; env.connect(A.cueBus);
    const shape = rising ? envIn : envOut;
    env.gain.setValueCurveAtTime(curve(x => shape(x) * (S.cue === 'tone' ? .3 : .4)), start, dur);
    let src;
    if (S.cue === 'tone') {
      src = ctx.createOscillator(); src.type = 'sine';
      const [a, b] = rising ? [midi(50), midi(55)] : [midi(55), midi(50)];
      src.frequency.setValueCurveAtTime(curve(x => a + (b - a) * x), start, dur);
      src.connect(env);
    } else {
      src = ctx.createBufferSource(); src.buffer = A.cueNoise; src.loop = true;
      const f = ctx.createBiquadFilter(); f.type = 'bandpass'; f.Q.value = .7;
      const [a, b] = rising ? [220, 620] : [520, 180];
      f.frequency.setValueCurveAtTime(curve(x => a + (b - a) * x), start, dur);
      src.connect(f); f.connect(env);
    }
    src.start(start, Math.random() * 3); src.stop(end + .02);
    cueNodes.push(src);
  }

  /* Struck sounds last the whole breath. After the strike, an in-breath swells towards its end and an out-breath settles away,
     both reaching silence as the next breath begins. Higher partials fade sooner, like a real struck note.
     Levels are lower than a single strike because a held sound carries more. */
  const swell = x => (.35 + .65 * Math.sin(Math.PI / 2 * x) ** 2) * Math.min(1, (1 - x) / .12);
  const settle = x => (1 - x) ** 1.6;
  function bell(freq, partials, at, dur, rising, attack, level) {
    const body = Math.max(.05, dur - attack - .002), shape = rising ? swell : settle;
    partials.forEach(([ratio, amp, fade]) => {
      const o = ctx.createOscillator(), g = ctx.createGain(), peak = level * amp * .75;
      const c = curve(x => peak * shape(x) ** (1 / fade));
      o.frequency.value = freq * ratio; o.connect(g); g.connect(A.cueBus);
      g.gain.setValueAtTime(0, at); g.gain.linearRampToValueAtTime(c[0], at + attack);
      g.gain.setValueCurveAtTime(c, at + attack + .001, body);
      o.start(at); o.stop(at + attack + body + .02); cueNodes.push(o);
    });
  }

  /* Spoken words are recorded clips made with tools/make-voice.mjs. List them here once they exist, and add them to FILES in sw.js.
     Until then the option is hidden, because the phone's built-in voice sounded poor. */
  const VOICE_CLIPS = null; // e.g. { in: 'audio/voice/breathe-in.mp3', out: 'audio/voice/breathe-out.mp3' }
  let voiceClips = null;
  function loadClips() {
    if (!VOICE_CLIPS || voiceClips) return voiceClips;
    voiceClips = Promise.all(Object.entries(VOICE_CLIPS).map(([k, url]) =>
      fetch(url).then(r => r.arrayBuffer()).then(b => ctx.decodeAudioData(b)).then(buf => [k, buf])))
      .then(Object.fromEntries, () => null);
    voiceClips.then(c => { A.clips = c; });
    return voiceClips;
  }
  function clip(type, at) {
    const buf = A.clips && A.clips[type];
    if (!buf) return;
    const s = ctx.createBufferSource(); s.buffer = buf; s.connect(A.cueBus); s.start(at); cueNodes.push(s);
  }

  function pad(out, notes, at) {
    const f = ctx.createBiquadFilter(), g = ctx.createGain(); f.type = 'lowpass'; f.frequency.value = 850;
    g.gain.setValueAtTime(0, at); g.gain.linearRampToValueAtTime(.075, at + 6);
    g.gain.setValueAtTime(.075, at + 10); g.gain.linearRampToValueAtTime(0, at + 18);
    f.connect(g); g.connect(out);
    notes.forEach(n => [-3, 3].forEach((cents, i) => {
      const o = ctx.createOscillator(); o.type = i ? 'triangle' : 'sine';
      o.frequency.value = midi(n); o.detune.value = cents; o.connect(f); o.start(at); o.stop(at + 18.1);
    }));
  }
  function key(out, note, at, level) {
    const g = ctx.createGain(); g.connect(out);
    g.gain.setValueAtTime(0, at); g.gain.linearRampToValueAtTime(level, at + .015);
    g.gain.exponentialRampToValueAtTime(.0005, at + 3.6);
    [[1, 1], [2, .16], [3, .05]].forEach(([h, a]) => {
      const o = ctx.createOscillator(), og = ctx.createGain(); og.gain.value = a;
      o.frequency.value = midi(note) * h; o.connect(og); og.connect(g); o.start(at); o.stop(at + 3.7);
    });
  }

  /* Learned sounds: files made in advance from measurements of real recordings.
     Each loop is decoded once into a compact 16-bit copy at the rate it was made at, then handed to sound-worklet.js, which
     plays it on the audio thread, as the iPhone app does. Thunder rolls play straight from their files. Together that keeps
     Night storm to about 16MB, where decoding everything the usual way took about 120MB.
     The current sound's files are fetched and decoded as the app opens, behind the launch screen, so they're ready by play. */
  const RAIN_FILES = ['storm-outside', 'storm-glass', 'storm-metal'], ROLLS = [1, 2, 3, 4, 5, 6].map(i => 'thunder' + i);
  const LOOPS = { window: RAIN_FILES, storm: [...RAIN_FILES, 'wind'], park: ['park'], hill: ['wind'] };
  /* The rate each loop was made at, so decoding doesn't stretch it to the device's rate. */
  const RATE = { 'storm-outside': 44100, 'storm-glass': 44100, 'storm-metal': 44100, park: 44100, wind: 22050 };
  const fileOf = n => 'sounds/' + n + (n === 'thrush' ? '.json' : n.startsWith('thunder') ? '.mp3' : '.flac');
  const DECODING = {}, READY = {}, SENT = new Set();
  /* Decoding needs no sound to be playing, so it runs before the first tap, in a context that never makes a sound. */
  function compact(n) {
    return DECODING[n] || (DECODING[n] = fetch(fileOf(n)).then(r => { if (!r.ok) throw new Error(n); return r.arrayBuffer(); })
      .then(bytes => new Promise((ok, fail) => {
        const OAC = window.OfflineAudioContext || window.webkitOfflineAudioContext;
        new OAC(2, 1, RATE[n]).decodeAudioData(bytes, ok, fail);
      }))
      .then(b => {
        const l = b.getChannelData(0), r = b.numberOfChannels > 1 ? b.getChannelData(1) : l, out = new Int16Array(b.length * 2);
        const to16 = x => Math.max(-32767, Math.min(32767, Math.round(x * 32767)));
        for (let i = 0; i < b.length; i++) { out[2 * i] = to16(l[i]); out[2 * i + 1] = to16(r[i]); }
        READY[n] = { name: n, rate: b.sampleRate, frames: b.length, data: out.buffer };
        sendClips();
      })
      .catch(e => { delete DECODING[n]; throw e; }));
  }
  /* Hands decoded loops to the worklet once it's running. The data moves rather than copies, so it's only held once. */
  function sendClips() {
    if (!A || !A.bank) return;
    Object.values(READY).forEach(c => { if (SENT.has(c.name)) return; SENT.add(c.name); A.bank.port.postMessage(c, [c.data]); delete READY[c.name]; });
  }
  let thrushSong = null;
  const thrush = () => thrushSong || (thrushSong = fetch(fileOf('thrush')).then(r => { if (!r.ok) throw new Error('thrush'); return r.json(); })
    .catch(e => { thrushSong = null; throw e; }));
  /* Thunder rolls play one at a time through this player, so they're never held decoded. Phones only let audio start from a
     tap, so it's started silently from one; it only reaches the speakers through Night storm. */
  const rollPlayer = new Audio(); rollPlayer.preload = 'auto';
  function rollSource() { if (!A.rolls) A.rolls = ctx.createMediaElementSource(rollPlayer); return A.rolls; }
  function unlockRolls() {
    if (!A || A.rollsUnlocked) return;
    rollSource(); A.rollsUnlocked = true;
    if (!rollPlayer.src) rollPlayer.src = fileOf(ROLLS[0]);
    rollPlayer.play().then(() => { if (!rollPlayer.dataset.rolling) rollPlayer.pause(); }, () => { A.rollsUnlocked = false; });
  }
  function preload(k) {
    (LOOPS[k] || []).forEach(n => compact(n).catch(() => {}));
    if (k === 'park') thrush().catch(() => {});
    /* Thunder is fetched once so the service worker keeps it for offline use; nothing here holds on to it. */
    if (k === 'storm') ROLLS.forEach(n => fetch(fileOf(n)).catch(() => {}));
  }
  /* Levels that sit the learned sounds alongside brown noise. */
  const LEVEL = { rain: 5.5, thunder: 5.3, wind: 1.5, park: 1.4 };

  /* Each sound runs through its own Distance, Tone and Fine tune before the music volume. */
  function makeChain() {
    const input = ctx.createGain(), warm = ctx.createBiquadFilter(), bright = ctx.createBiquadFilter(), near = ctx.createBiquadFilter();
    const level = ctx.createGain(), send = ctx.createGain();
    warm.type = 'lowshelf'; warm.frequency.value = 250; bright.type = 'highshelf'; bright.frequency.value = 3000; near.type = 'lowpass'; near.frequency.value = 20000;
    const bands = BANDS.map(([type, f, q]) => { const b = ctx.createBiquadFilter(); b.type = type; b.frequency.value = f; if (q) b.Q.value = q; return b; });
    [input, warm, bright, ...bands, near, level].reduce((a, b) => { a.connect(b); return b; });
    level.connect(A.musicBus); near.connect(send); send.gain.value = 0; send.connect(A.distant);
    return { input, warm, bright, bands, near, level, send };
  }
  function applyAdjust(v, now) {
    if (!v || !v.chain) return;
    const a = adj(v.kind), c = v.chain, t = ctx.currentTime, set = (p, x) => now ? p.setValueAtTime(x, t) : p.setTargetAtTime(x, t, .08);
    const d = a.distance / 100, tone = a.tone / 100;
    set(c.warm.gain, -tone * 7); set(c.bright.gain, tone * 7);
    a.bands.forEach((g, i) => set(c.bands[i].gain, g));
    set(c.near.frequency, 20000 * Math.pow(2200 / 20000, d));
    set(c.level.gain, 1 - .45 * d); set(c.send.gain, .9 * d);
    Object.entries(v.layers).forEach(([key, g]) => set(g.gain, v.layerBase[key] * Math.pow(layerValue(a, key) / 50, 1.6)));
  }

  /* The song thrush: phrases traced from a recording, sung by a tone in a new order each time. */
  function singer(J, to, spacing, level, start) {
    const dt = J.dt, phrases = J.phrases.filter(p => p.length > 1), top = Math.max(...phrases.flatMap(p => p.flatMap(n => n[2])));
    let at = start;
    return (now, horizon) => { if (at < now) at = now + .1;
      while (at < horizon) {
        const p = phrases[Math.floor(Math.random() * phrases.length)], pan = ctx.createStereoPanner(); pan.pan.value = Math.random() * .8 - .4; pan.connect(to);
        let end = at;
        p.forEach(([off, fs, as, h]) => {
          if (fs.length < 2) return;
          const s0 = at + off, d = fs.length * dt, g = ctx.createGain(); g.gain.value = 0; g.connect(pan);
          const amp = new Float32Array(as.length + 2); as.forEach((x, i) => { amp[i + 1] = level * Math.pow(10, (x - top) / 20); });
          g.gain.setValueCurveAtTime(amp, s0, d + 2 * dt);
          [[1, 1], [2, h[0]], [3, h[1]]].forEach(([k, w]) => { if (w < .04 || fs[0] * k > 15000) return;
            const o = ctx.createOscillator(), og = ctx.createGain(); og.gain.value = Math.min(w, 1);
            o.frequency.setValueCurveAtTime(Float32Array.from(fs, x => x * k), s0, d); o.connect(og); og.connect(g); o.start(s0); o.stop(s0 + d + 2 * dt + .02); });
          end = Math.max(end, s0 + d);
        });
        at = end + Math.max(.3, J.gaps[Math.floor(Math.random() * J.gaps.length)]) * spacing * (.7 + Math.random() * .8);
      } };
  }

  function startVoice(kind) {
    const out = ctx.createGain(), t = ctx.currentTime; out.gain.setValueAtTime(0, t);
    out.gain.linearRampToValueAtTime(1, t + .4);
    const v = { kind, out, stopped: false, sources: [], layers: {}, layerBase: {}, tick() {} };
    if (adjustable(kind)) { v.chain = makeChain(); out.connect(v.chain.input); } else out.connect(A.musicBus);
    const layer = (key, base) => { const g = ctx.createGain(); g.gain.value = 0; g.connect(out); v.layers[key] = g; v.layerBase[key] = base; return g; };
    const failed = () => { if (!v.stopped && running) $('status').textContent = "Part of this sound couldn't load. Check your connection."; };
    const loopClip = (name, node) => {
      compact(name).catch(failed);
      A.ready.then(() => {
        if (v.stopped) return;
        const w = new AudioWorkletNode(ctx, 'swellotic-loop', { numberOfInputs: 0, outputChannelCount: [2], processorOptions: { name, offset: Math.random() } });
        w.connect(node); v.sources.push({ stop() { w.port.postMessage('stop'); w.disconnect(); } });
      }).catch(failed);
    };
    const buffers = () => {
      A.brownBuf = A.brownBuf || loopBuffer(12, 2, brown);
      A.whiteBuf = A.whiteBuf || loopBuffer(11, 2, white);
      A.pinkBuf = A.pinkBuf || loopBuffer(13, 2, pink);
      return { brown: A.brownBuf, white: A.whiteBuf, pink: A.pinkBuf };
    };
    const drift = (param, rate, depth) => {
      const o = ctx.createOscillator(), d = ctx.createGain();
      o.frequency.value = rate; d.gain.value = depth; o.connect(d); d.connect(param); o.start(); v.sources.push(o);
    };
    const looped = (buffer, node) => { const s = ctx.createBufferSource(); s.buffer = buffer; s.loop = true; s.connect(node); s.start(); v.sources.push(s); };
    if (kind === 'brown') {
      A.brownBuf = A.brownBuf || loopBuffer(12, 2, brown);
      const g = ctx.createGain(); g.gain.value = .9; g.connect(out); looped(A.brownBuf, g);
    } else if (kind === 'rain') {
      A.brownBuf = A.brownBuf || loopBuffer(12, 2, brown);
      A.whiteBuf = A.whiteBuf || loopBuffer(11, 2, white);
      const hp = ctx.createBiquadFilter(), lp = ctx.createBiquadFilter(), g = ctx.createGain(), low = ctx.createGain();
      hp.type = 'highpass'; hp.frequency.value = 1100; lp.type = 'lowpass'; lp.frequency.value = 6500; g.gain.value = .16; low.gain.value = .3;
      hp.connect(lp); lp.connect(g); g.connect(out); low.connect(out);
      looped(A.whiteBuf, hp); looped(A.brownBuf, low);
    } else if (kind === 'pink') {
      const g = ctx.createGain(); g.gain.value = .75; g.connect(out); looped(buffers().pink, g);
    } else if (kind === 'beach') {
      const b = buffers(), low = ctx.createGain(), lp = ctx.createBiquadFilter(), swell = ctx.createGain();
      low.gain.value = .3; lp.type = 'lowpass'; lp.frequency.setValueAtTime(320, t); swell.gain.setValueAtTime(.04, t);
      low.connect(out); lp.connect(swell); swell.connect(out);
      looped(b.brown, low); looped(b.white, lp);
      let next = t + .1;
      v.tick = (now, horizon) => { if (next < now) next = now + .05;
        while (next < horizon) {
          const dur = 8 + Math.random() * 5, peak = .2 + Math.random() * .12;
          swell.gain.linearRampToValueAtTime(peak, next + dur * .42);
          swell.gain.linearRampToValueAtTime(.04, next + dur);
          lp.frequency.linearRampToValueAtTime(760 + Math.random() * 260, next + dur * .42);
          lp.frequency.linearRampToValueAtTime(320, next + dur);
          next += dur;
        }
      };
    } else if (kind === 'stream') {
      const b = buffers(), a1 = ctx.createBiquadFilter(), a2 = ctx.createBiquadFilter(), g1 = ctx.createGain(), g2 = ctx.createGain();
      a1.type = a2.type = 'bandpass'; a1.frequency.value = 800; a1.Q.value = .5; a2.frequency.value = 1900; a2.Q.value = 1;
      g1.gain.value = 1.1; g2.gain.value = .6; a1.connect(g1); a2.connect(g2); g1.connect(out); g2.connect(out);
      looped(b.pink, a1); looped(b.pink, a2); drift(a2.frequency, .13, 320);
    } else if (kind === 'wind') {
      const b = buffers(), f = ctx.createBiquadFilter(), g = ctx.createGain();
      f.type = 'bandpass'; f.frequency.value = 380; f.Q.value = .8; g.gain.value = .9;
      f.connect(g); g.connect(out); looped(b.pink, f); drift(f.frequency, .07, 170); drift(g.gain, .05, .3);
    } else if (kind === 'fire') {
      const b = buffers(), lp = ctx.createBiquadFilter(), g = ctx.createGain(), hp = ctx.createBiquadFilter();
      lp.type = 'lowpass'; lp.frequency.value = 480; g.gain.value = .75; hp.type = 'highpass'; hp.frequency.value = 1500;
      lp.connect(g); g.connect(layer('body', 1)); hp.connect(layer('crackle', 1)); looped(b.brown, lp);
      let next = t + .2;
      v.tick = (now, horizon) => { if (next < now) next = now + .05;
        while (next < horizon) {
          const s = ctx.createBufferSource(), e = ctx.createGain(), len = .005 + Math.random() * .02;
          s.buffer = b.white; s.connect(e); e.connect(hp);
          e.gain.setValueAtTime(.04 + Math.random() ** 3 * .28, next); e.gain.exponentialRampToValueAtTime(.0005, next + len);
          s.start(next, Math.random() * 8, len + .01);
          next += -Math.log(1 - Math.random()) / 3;
        }
      };
    } else if (kind === 'green') {
      const f = ctx.createBiquadFilter(), g = ctx.createGain(); f.type = 'bandpass'; f.frequency.value = 520; f.Q.value = .55; g.gain.value = 1.4;
      f.connect(g); g.connect(out); looped(buffers().pink, f);
    } else if (kind === 'window' || kind === 'storm') {
      RAIN_FILES.forEach(n => loopClip(n, layer(n.replace('storm-', ''), LEVEL.rain)));
      if (kind === 'storm') {
        loopClip('wind', layer('wind', LEVEL.wind));
        /* One roll at a time, with 15 to 45 seconds of rain between them. */
        const roll = ctx.createGain(); roll.gain.value = 0; roll.connect(layer('thunder', LEVEL.thunder)); rollSource().connect(roll);
        let next = t + 3 + Math.random() * 3, rolling = false;
        const done = () => { rolling = false; delete rollPlayer.dataset.rolling; next = ctx.currentTime + 15 + Math.random() * 30; };
        rollPlayer.onended = done;
        v.tick = now => {
          if (rolling || now < next) return;
          rolling = true; rollPlayer.dataset.rolling = '1';
          rollPlayer.src = fileOf(ROLLS[Math.floor(Math.random() * ROLLS.length)]);
          roll.gain.setValueAtTime(.6 + Math.random() * .4, ctx.currentTime);
          rollPlayer.play().catch(() => { done(); next = now + 10; });
        };
        v.end = () => { rollPlayer.onended = null; delete rollPlayer.dataset.rolling; rollPlayer.pause(); try { rollSource().disconnect(roll); } catch (e) {} };
      }
    } else if (kind === 'hill') {
      loopClip('wind', layer('wind', LEVEL.wind));
    } else if (kind === 'park') {
      loopClip('park', layer('park', LEVEL.park * .9));
      const birds = layer('birds', 1), echo = ctx.createDelay(1), back = ctx.createGain(), soft = ctx.createBiquadFilter(), bus = ctx.createGain();
      echo.delayTime.value = .19; back.gain.value = .22; soft.type = 'lowpass'; soft.frequency.value = 4500;
      bus.connect(birds); bus.connect(echo); echo.connect(soft); soft.connect(back); back.connect(echo); back.connect(birds);
      thrush().then(J => { if (!v.stopped) v.tick = singer(J, bus, .9, .075, ctx.currentTime + 1 + Math.random() * 2); }).catch(failed);
    } else if (kind === 'ambient') {
      const chords = [[50, 57, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 57, 62, 66], [45, 52, 57, 61, 64]];
      let next = t + .1, i = 0;
      v.tick = (now, horizon) => { if (next < now) next = now + .05; while (next < horizon) { pad(out, chords[i++ % 4], next); next += 13; } };
    } else if (kind === 'keys') {
      const chords = [[50, 60, 64, 65, 69], [43, 59, 64, 65, 69], [48, 59, 62, 64, 67], [45, 60, 64, 67, 71]];
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 1700; lp.connect(out);
      let next = t + .1, i = 0;
      v.tick = (now, horizon) => { if (next < now) next = now + .05;
        while (next < horizon) {
          const c = chords[i++ % 4]; key(lp, c[0], next, .16);
          [.75, 1.5, 2.25, 3, 3.75, 4.5].forEach(off => {
            if (Math.random() < .65) key(lp, c[1 + Math.floor(Math.random() * 4)] + 12, next + off + Math.random() * .03, .055 + Math.random() * .03);
          });
          next += 6;
        }
      };
    } else if (kind === 'classical') {
      /* The recordings stream from an audio element, so long pieces never sit in memory, and still pass through the music volume and room effect. */
      const src = playerSource(); src.connect(out);
      v.classical = true; owner = v;
      v.end = () => { try { src.disconnect(out); } catch (e) {} if (owner === v) { owner = null; player.pause(); } };
      playPiece();
    }
    applyAdjust(v, true);
    return v;
  }
  function stopVoice(v) {
    if (!v) return;
    v.stopped = true; const t = ctx.currentTime;
    v.out.gain.cancelScheduledValues(t); v.out.gain.setTargetAtTime(0, t, .25);
    setTimeout(() => { v.sources.forEach(s => { s.onended = null; try { s.stop(); } catch (e) {} }); if (v.end) v.end(); v.out.disconnect(); }, 1200);
  }

  /* Classical mix: public domain recordings listed in classical.json. The set repeats by default, and "Repeat this piece" loops one. */
  const player = new Audio(); player.preload = 'metadata';
  let pieces = [], owner = null, failures = 0;
  fetch('classical.json').then(r => r.json()).then(list => { pieces = list; cuePiece(); paint(); readSaved().then(() => setTimeout(keepAll, 4000)); }).catch(() => {});
  function playerSource() { if (!A.player) A.player = ctx.createMediaElementSource(player); return A.player; }
  const piece = () => pieces[S.piece] || pieces[0];
  function cuePiece() {
    if (!pieces.length) return;
    S.piece = ((+S.piece || 0) % pieces.length + pieces.length) % pieces.length;
    if (S.track !== 'classical') return;
    const url = new URL(piece().file, location.href).href;
    if (player.src !== url) player.src = url;
    player.loop = !!S.repeatOne;
  }
  function playPiece() {
    cuePiece();
    if (owner && running) player.play().catch(() => {});
  }
  function skipPiece(step) {
    if (!pieces.length) return;
    S.piece = playableFrom(+S.piece + step, step || 1); failures = 0;
    const live = owner && running && voice === owner;
    if (!live) { cuePiece(); save(); paintPiece(); return; }
    /* A short fade, so skipping never cuts off mid-note. */
    const g = owner.out.gain, t = ctx.currentTime;
    g.cancelScheduledValues(t); g.setTargetAtTime(0, t, .06);
    setTimeout(() => { playPiece(); save(); paintPiece(); g.setTargetAtTime(1, ctx.currentTime, .12); }, 300);
  }
  player.addEventListener('ended', () => skipPiece(1));
  player.addEventListener('playing', () => { failures = 0; });
  player.addEventListener('error', () => {
    if (!owner || !running) return;
    if (++failures >= pieces.length || (!navigator.onLine && !saved.size)) {
      $('status').textContent = navigator.onLine ? "The Classical mix couldn't load. Try another sound." : 'Connect to the internet to play the Classical mix, or turn on "Save all for offline" next time.';
      return;
    }
    skipPiece(1);
  });
  player.addEventListener('loadedmetadata', () => paintPiece());
  const clockText = s => isFinite(s) ? `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}` : '';
  function paintPiece() {
    if (!pieces.length) return;
    const p = piece();
    $('pieceTitle').textContent = `${p.composer}: ${p.title}`;
    $('pieceBy').textContent = p.performer;
    $('pieceCount').textContent = `Playing piece ${S.piece + 1} of ${pieces.length}.`;
    const time = player.duration ? `${clockText(player.currentTime)} / ${clockText(player.duration)}` : '';
    if ($('pieceTime').textContent !== time) $('pieceTime').textContent = time;
    $('repeatOne').setAttribute('aria-pressed', String(!!S.repeatOne));
  }
  /* Offline: the service worker plays any piece kept in the "swellotic-music" store. Pieces are kept after 30 seconds of listening,
     or all at once with "Save all for offline". Without a connection, only kept pieces are played. */
  const MUSIC = 'swellotic-music', canKeep = 'caches' in window && 'serviceWorker' in navigator;
  let saved = new Set(), queue = Promise.resolve(), queued = new Set(), keeping = 0, round = 0;
  const urlOf = i => new URL(pieces[i].file, location.href).href;
  function playableFrom(i, step) {
    const n = pieces.length; i = ((i % n) + n) % n;
    if (navigator.onLine || !saved.size) return i;
    for (let k = 0; k < n; k++, i = ((i + step) % n + n) % n) if (saved.has(urlOf(i))) return i;
    return i;
  }
  async function readSaved() {
    if (!canKeep) return;
    try { saved = new Set((await (await caches.open(MUSIC)).keys()).map(r => r.url)); } catch (e) {}
    paintSaved();
  }
  function keep(url) {
    if (!canKeep || saved.has(url) || queued.has(url)) return;
    queued.add(url); keeping++; paintSaved();
    const mine = round;
    queue = queue.then(async () => {
      try {
        if (!navigator.onLine || mine !== round) return;
        const res = await fetch(url, { cache: 'no-store' });
        if (res.status === 200 && mine === round) { await (await caches.open(MUSIC)).put(url, res); saved.add(url); }
      } catch (e) {} finally { if (mine === round) { queued.delete(url); keeping--; } paintSaved(); }
    });
  }
  function keepAll() { if (S.saveAll && navigator.onLine) pieces.forEach((_, i) => keep(urlOf(i))); }
  function paintSaved() {
    if (!pieces.length) return;
    $('saveRow').hidden = !canKeep; $('saveAll').checked = !!S.saveAll;
    const have = pieces.filter((_, i) => saved.has(urlOf(i))).length;
    $('savedNote').textContent = `${have} of ${pieces.length} pieces saved on this device.` + (keeping ? ` Saving ${have + 1}…` : '');
  }
  player.addEventListener('timeupdate', () => { if (player.currentTime > 30 && owner) keep(player.src); });
  $('saveAll').addEventListener('change', async e => {
    S.saveAll = e.target.checked; save();
    if (S.saveAll) {
      /* Ask the browser not to clear the saved music when space runs low. */
      try { await navigator.storage.persist(); } catch (err) {}
      keepAll();
    } else {
      /* Turning it off frees the space. Pieces you listen to are kept again as you hear them. */
      round++; queued.clear(); keeping = 0; paintSaved();
      await queue;
      try { await caches.delete(MUSIC); } catch (err) {}
      saved = new Set(); paintSaved();
    }
  });
  addEventListener('online', keepAll);

  function refreshVoice() {
    if (!running) return;
    stopVoice(voice); voice = startVoice(S.track);
  }

  /* Timeline: one list of phases drives sound and tide, so they cannot drift apart. */
  let phases = [], nextStart = 0;
  const clock = () => running ? ctx.currentTime : performance.now() / 1000;
  const paceAt = t => (S.ease && running && S.bpm < 10) ? 10 + (S.bpm - 10) * Math.min(1, (t - sessionStart) / 180) : S.bpm;
  function schedule() {
    const horizon = clock() + (running ? 4 : 1.5);
    while (nextStart < horizon) {
      const cycle = 60 / paceAt(nextStart), inhale = cycle * RATIOS[S.ratio][1], mid = nextStart + inhale, end = nextStart + cycle;
      phases.push({ type: 'in', start: nextStart, end: mid, bpm: 60 / cycle }, { type: 'out', start: mid, end, bpm: 60 / cycle });
      if (running) { playCue('in', nextStart, mid); playCue('out', mid, end); }
      nextStart = end;
    }
    const now = clock(); phases = phases.filter(p => p.end > now - 3);
    if (cueNodes.length > 240) cueNodes = cueNodes.slice(-120);
  }
  function switchCue() {
    if (!running) return;
    const now = ctx.currentTime, oldBus = A.cueBus, oldNodes = cueNodes;
    oldBus.gain.setTargetAtTime(0, now, .04);
    oldNodes.forEach(n => { try { n.stop(now + .3); } catch (e) {} });
    setTimeout(() => oldBus.disconnect(), 500);
    cueNodes = []; newCueBus();
    const current = phases.find(p => now >= p.start && now < p.end);
    if (current && current.end - now > (S.cue === 'words' ? 1 : .25)) playCue(current.type, now + .03, current.end);
    phases.filter(p => p.start > now).forEach(p => playCue(p.type, p.start, p.end));
  }
  function resetPreview() { if (!running) { phases = []; nextStart = clock(); schedule(); } }

  const fmt = s => `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
  function tick() {
    schedule();
    if (!running) return;
    if (voice) voice.tick(ctx.currentTime, ctx.currentTime + 5);
    if (S.track === 'classical') paintPiece();
    const elapsed = ctx.currentTime - sessionStart, seg = segmentAt(elapsed);
    if (seg.kind !== segment) enterSegment(seg.kind);
    const length = sessionLength();
    /* The session button doubles as the clock while a session runs. */
    const shown = S.mode === 'interval' ? `${seg.kind === 'rest' ? 'Rest' : 'Swell'} ${fmt(seg.left)}`
      : length ? `${fmt(Math.max(0, length - elapsed))} left` : fmt(elapsed);
    if ($('sessionSum').textContent !== shown) $('sessionSum').textContent = shown;
    if (length && elapsed >= length) stop('Session finished.');
  }

  /* Swell and rest: focus time and quiet breaks take turns on the session clock. Settings changed mid-session apply straight away. */
  let segment = 'swell';
  function segmentAt(elapsed) {
    if (S.mode !== 'interval') return { kind: 'swell', left: 0 };
    const swell = S.swellMin * 60, cycle = swell + S.restMin * 60, pos = elapsed % cycle;
    return pos < swell ? { kind: 'swell', left: swell - pos } : { kind: 'rest', left: cycle - pos };
  }
  function enterSegment(kind) {
    segment = kind;
    const t = ctx.currentTime, resting = kind === 'rest';
    ring(resting ? 62 : 69, t + .05);
    /* Sound fades out gently for a rest, after the chime has started, and fades back in for the next swell. */
    A.master.gain.cancelScheduledValues(t);
    A.master.gain.setTargetAtTime(resting ? 0 : 1, t + (resting ? .6 : .2), resting ? .7 : .5);
    if (owner) {
      if (resting) setTimeout(() => { if (segment === 'rest' && owner) player.pause(); }, 3500);
      else player.play().catch(() => {});
    }
    document.body.classList.toggle('resting', resting);
    $('status').textContent = resting ? 'Time for a break. The next swell starts by itself.' : '';
  }
  /* A soft two-note chime on its own path, so it's heard even while the rest has faded everything else. */
  function ring(note, at) {
    const level = .1 + .25 * gainCurve(Math.max(S.breathVol, 30));
    [[0, 1], [.35, .8]].forEach(([delay, amp], i) => [[1, 1], [2.76, .12]].forEach(([ratio, part]) => {
      const o = ctx.createOscillator(), g = ctx.createGain(), s = at + delay;
      o.frequency.value = midi(note + (i ? 7 : 0)) * ratio; o.connect(g); g.connect(A.alert);
      g.gain.setValueAtTime(0, s); g.gain.linearRampToValueAtTime(level * amp * part, s + .02);
      g.gain.exponentialRampToValueAtTime(.0003, s + 3.5);
      o.start(s); o.stop(s + 3.6);
    }));
  }

  function setGo() {
    $('go').classList.toggle('playing', running && !held);
    $('go').setAttribute('aria-label', !running ? 'Start' : held ? 'Resume' : 'Pause');
    showEnd(); showUpdate();
  }
  async function lockScreen() { try { wake = await navigator.wakeLock.request('screen'); } catch (e) { wake = null; } }

  async function start() {
    ensureAudio();
    if (S.track === 'storm') unlockRolls();
    /* Phones only let audio start straight from a tap, so the piece starts here, before anything waits. It stays silent until it's connected. */
    if (S.track === 'classical' && pieces.length) { S.piece = playableFrom(+S.piece, 1); playerSource(); cuePiece(); player.play().catch(() => {}); }
    setSession();
    await ctx.resume();
    if (S.cue === 'words') await loadClips();
    running = true; paused = false; held = false; showResume(false); sessionStart = ctx.currentTime; segment = 'swell';
    phases = []; nextStart = ctx.currentTime + .3; cueNodes = [];
    A.master.gain.cancelScheduledValues(sessionStart);
    A.master.gain.setValueAtTime(0, sessionStart); A.master.gain.linearRampToValueAtTime(1, sessionStart + .8);
    applyLevels(); voice = startVoice(S.track); schedule(); voice.tick(ctx.currentTime, ctx.currentTime + 5);
    setGo(); $('sessionSum').textContent = S.mode === 'interval' ? `Swell ${fmt(S.swellMin * 60)}` : sessionLength() ? `${fmt(sessionLength())} left` : fmt(0);
    $('status').textContent = '';
    lockScreen();
    count('session started', choices());
  }
  function ended(reason) {
    count('session ended', { reason, minutes: Math.round((ctx.currentTime - sessionStart) / 6) / 10, music: S.track, session: S.mode });
  }
  /* A session still playing when the page closes counts as closed. */
  addEventListener('pagehide', () => { if (running) ended('closed'); });
  function stop(message) {
    ended(message === 'Session finished.' ? 'finished' : 'stopped');
    const t = ctx.currentTime;
    A.master.gain.cancelScheduledValues(t); A.master.gain.setTargetAtTime(0, t, .15);
    stopVoice(voice); voice = null; running = false; paused = false; held = false; showResume(false);
    segment = 'swell'; document.body.classList.remove('resting');
    const nodes = cueNodes; cueNodes = [];
    setTimeout(() => { nodes.forEach(n => { try { n.stop(); } catch (e) {} }); if (!running) ctx.suspend(); }, 700);
    setGo(); paint();
    $('status').textContent = message || 'Press play to begin.';
    if (wake) { wake.release().catch(() => {}); wake = null; }
    resetPreview();
  }

  /* Visuals: every scene draws from the same breath level, so sound and picture stay together. */
  const canvas = $('tide'), g2 = canvas.getContext('2d');
  const still = matchMedia('(prefers-reduced-motion: reduce)');
  const lava = document.createElement('canvas'), lg = lava.getContext('2d');
  let level = .4;
  const rgb = hex => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
  const LAVA_BLOBS = [...Array(7)].map((_, i) => ({ x: .15 + i * .115, sx: .11 + i * .023, sy: .07 + (i % 4) * .03, p: i * 1.9, r: .13 + (i % 3) * .035 }));

  const sceneWidth = w => (innerWidth >= 900 && !$('app').classList.contains('quiet')) ? w - 436 : w;
  function ground(p, w, h) {
    const g = g2.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, p.ground[0]); g.addColorStop(1, p.ground[1]);
    g2.fillStyle = g; g2.fillRect(0, 0, w, h);
  }
  function wave(w, h, y, amp, len, shift, fill) {
    g2.beginPath(); g2.moveTo(0, h);
    for (let x = 0; x <= w; x += 12) g2.lineTo(x, y + Math.sin(x / len + shift) * amp);
    g2.lineTo(w, h); g2.closePath(); g2.fillStyle = fill; g2.fill();
  }
  function drawLava(p, w, h, t) {
    const lw = 110, lh = Math.max(60, Math.round(lw * h / w));
    if (lava.width !== lw || lava.height !== lh) { lava.width = lw; lava.height = lh; }
    const img = lg.createImageData(lw, lh), d = img.data, cols = p.colors.map(rgb);
    const size = .72 + level * .62, span = Math.min(lw, lh);
    const blobs = LAVA_BLOBS.map(b => ({
      x: (b.x + Math.sin(t * b.sx + b.p) * .1) * lw,
      y: (.5 + Math.sin(t * b.sy + b.p * 1.7) * .42) * lh,
      r: (b.r * size * span) ** 2
    }));
    for (let y = 0, i = 0; y < lh; y++) {
      const v = y / (lh - 1), m = v * 2, k = Math.min(1, Math.floor(m)), mix = m - k;
      for (let x = 0; x < lw; x++, i += 4) {
        let field = 0;
        for (const b of blobs) { const dx = x - b.x, dy = y - b.y; field += b.r / (dx * dx + dy * dy + 1); }
        const a = Math.min(1, Math.max(0, (field - .85) / .3));
        if (!a) continue;
        d[i] = cols[k][0] + (cols[k + 1][0] - cols[k][0]) * mix;
        d[i + 1] = cols[k][1] + (cols[k + 1][1] - cols[k][1]) * mix;
        d[i + 2] = cols[k][2] + (cols[k + 1][2] - cols[k][2]) * mix;
        d[i + 3] = a * 255;
      }
    }
    lg.putImageData(img, 0, 0);
    g2.imageSmoothingEnabled = true; g2.imageSmoothingQuality = 'high';
    g2.drawImage(lava, 0, 0, w, h);
  }
  function drawBloom(p, w, h, t) {
    const cx = sceneWidth(w) / 2, cy = h * .47, unit = Math.min(sceneWidth(w), h), petals = 8;
    const dist = unit * (.05 + level * .2), r = unit * (.11 + level * .14);
    g2.globalCompositeOperation = 'screen'; g2.globalAlpha = .46;
    for (let i = 0; i < petals; i++) {
      const a = i / petals * Math.PI * 2 + t * .05 + level * .5;
      g2.fillStyle = p.colors[i % 3];
      g2.beginPath(); g2.arc(cx + Math.cos(a) * dist, cy + Math.sin(a) * dist, r, 0, 7); g2.fill();
    }
  }
  function drawRings(p, w, h, t) {
    const cx = sceneWidth(w) / 2, cy = h * .47, unit = Math.hypot(sceneWidth(w), h) * .3;
    for (let i = 5; i >= 0; i--) {
      g2.globalAlpha = .34 + (5 - i) * .1; g2.fillStyle = p.colors[i % 3];
      const r = unit * (.14 + i * .16) * (.5 + level * .62) * (1 + Math.sin(t * .4 + i) * .015);
      g2.beginPath(); g2.arc(cx, cy, r, 0, 7); g2.fill();
    }
  }
  function drawAurora(p, w, h, t) {
    g2.globalCompositeOperation = 'screen';
    p.colors.forEach((c, i) => {
      const top = h * (.62 - level * .46) + i * h * .05;
      const g = g2.createLinearGradient(0, top - h * .1, 0, top + h * .62);
      g.addColorStop(0, c + '00'); g.addColorStop(.3, c + '8c'); g.addColorStop(1, c + '00');
      g2.fillStyle = g; g2.beginPath(); g2.moveTo(0, h);
      for (let x = 0; x <= w; x += 12) g2.lineTo(x, top + Math.sin(x / (170 + i * 60) + t * (.22 + i * .07) + i * 2) * h * .07);
      g2.lineTo(w, h); g2.closePath(); g2.fill();
    });
  }
  function drawTide(p, w, h, t) {
    const y = h * (.86 - level * .68);
    wave(w, h, y, 7, 150, t * .38, p.colors[0]);
    wave(w, h, y + 18, 5, 95, -t * .5, p.colors[1]);
  }
  const SCENES = { lava: drawLava, bloom: drawBloom, rings: drawRings, aurora: drawAurora, tide: drawTide };

  function draw() {
    requestAnimationFrame(draw);
    if (document.hidden) return;
    const dpr = Math.min(devicePixelRatio || 1, 2), w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) return;
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) { canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr); }
    g2.setTransform(dpr, 0, 0, dpr, 0, 0);

    const t = clock() - (running ? (ctx.outputLatency || 0) : 0);
    const p = phases.find(q => t >= q.start && t < q.end);
    if (p) {
      const x = (t - p.start) / (p.end - p.start), eased = .5 - .5 * Math.cos(Math.PI * x);
      level = p.type === 'in' ? eased : 1 - eased;
      const word = running && segment === 'rest' ? 'Rest' : p.type === 'in' ? 'In' : 'Out';
      if ($('word').textContent !== word) $('word').textContent = word;
      const left = Math.ceil(p.end - t), info = `${left} s left  ·  ${p.bpm.toFixed(1)} breaths/min`;
      if ($('timing').textContent !== info) $('timing').textContent = info;
    }
    const pal = PALETTES[S.palette] || PALETTES.sunset;
    ground(pal, w, h);
    if (still.matches) {
      g2.globalAlpha = .2 + level * .7; g2.fillStyle = pal.colors[0]; g2.fillRect(0, 0, w, h); g2.globalAlpha = 1;
      return;
    }
    (SCENES[S.visual] || drawLava)(pal, w, h, performance.now() / 1000);
    g2.globalAlpha = 1; g2.globalCompositeOperation = 'source-over';
    g2.fillStyle = 'rgba(10, 8, 16, .16)'; g2.fillRect(0, 0, w, h);
  }

  /* Controls */
  function paint() {
    $('bpm').value = S.bpm; $('breathVol').value = S.breathVol; $('musicVol').value = S.musicVol;
    $('room').checked = S.room; $('ease').checked = S.ease; $('words').checked = S.words; $('countdown').checked = S.countdown;
    const c = 60 / S.bpm, i = c * RATIOS[S.ratio][1];
    $('bpmOut').textContent = `${S.bpm} (${i.toFixed(1)} s in, ${(c - i).toFixed(1)} s out)`;
    const appMusic = S.track === 'none';
    $('musicVol').disabled = appMusic; $('room').disabled = appMusic;
    $('breathOut').textContent = S.breathVol ? S.breathVol + '%' : 'Silent';
    $('musicOut').textContent = appMusic ? 'In your music app' : S.musicVol + '%';
    $('sum-pace').textContent = `${S.bpm} a minute, ${CUES[S.cue]}`;
    $('sum-music').textContent = TRACKS[S.track][0] + (adjustable(S.track) && changed(S.track) ? ', adjusted' : '');
    paintAdjust();
    $('sum-look').textContent = `${VISUALS[S.visual]}, ${PALETTES[S.palette].name}`;
    const lim = limitMin(), interval = S.mode === 'interval';
    if (!running) $('sessionSum').textContent = interval ? `Swell ${S.swellMin} · Rest ${S.restMin} min${+S.rounds ? ` · ${S.rounds} rounds` : ''}` : lim ? `${lim} min timer` : 'No time limit';
    ['timer', 'interval'].forEach(m => { $('tab-' + m).setAttribute('aria-selected', String(S.mode === m)); $('tab-' + m).tabIndex = S.mode === m ? 0 : -1; $('pane-' + m).hidden = S.mode !== m; });
    $('customMin').value = S.customMin; $('customOut').textContent = `${S.customMin} min`; $('customRow').hidden = S.limit !== 'custom';
    $('swellMin').value = S.swellMin; $('swellOut').textContent = `${S.swellMin} min`;
    $('restMin').value = S.restMin; $('restOut').textContent = `${S.restMin} min`;
    $('intervalNote').textContent = +S.rounds ? `${S.rounds} swells with a rest between each, ${sessionLength() / 60} minutes in all.` : 'Swell and rest take turns until you press stop.';
    $('word').hidden = !S.words; $('timing').hidden = !S.countdown;
    document.documentElement.style.setProperty('--tint', PALETTES[S.palette].tint);
    [['breathVol', 0, 100], ['musicVol', 0, 100], ['bpm', 2, 12], ['customMin', 5, 240], ['swellMin', 5, 90], ['restMin', 1, 30]].forEach(([id, lo, hi]) => $(id).style.setProperty('--v', ($(id).value - lo) / (hi - lo) * 100 + '%'));
    $('classical').hidden = $('nowPlaying').hidden = S.track !== 'classical'; paintPiece(); paintSaved(); $('trackNote').textContent = TRACKS[S.track][1];
  }
  const bind = (id, key, cast, after) => $(id).addEventListener('input', e => {
    S[key] = cast(e.target); save(); paint(); applyLevels(); if (after) after();
  });
  bind('bpm', 'bpm', e => +e.value, resetPreview);
  bind('breathVol', 'breathVol', e => +e.value);
  bind('musicVol', 'musicVol', e => +e.value);
  bind('room', 'room', e => e.checked);
  bind('ease', 'ease', e => e.checked);
  bind('words', 'words', e => e.checked);
  bind('countdown', 'countdown', e => e.checked);
  bind('customMin', 'customMin', e => +e.value);
  chips($('rounds'), 'rounds', ROUNDS, 'rounds', () => { S.rounds = +S.rounds; save(); paint(); });
  /* Timer and Interval tabs: the open tab is the kind of session. Arrow keys move between them, as tabs usually do. */
  const pickMode = (m, fromKeys) => { S.mode = m; save(); paint(); if (fromKeys) $('tab-' + m).focus(); };
  ['timer', 'interval'].forEach(m => $('tab-' + m).addEventListener('click', () => pickMode(m)));
  $('tab-timer').parentElement.addEventListener('keydown', e => {
    if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key)) { e.preventDefault(); pickMode(S.mode === 'timer' ? 'interval' : 'timer', true); }
  });  bind('swellMin', 'swellMin', e => +e.value);
  bind('restMin', 'restMin', e => +e.value);
  chips($('limit'), 'limit', LIMITS, 'limit', () => { if (S.limit !== 'custom') S.limit = +S.limit; save(); paint(); });
  chips($('ratio'), 'ratio', RATIOS, 'ratio', () => { paint(); resetPreview(); });
  if (!VOICE_CLIPS) { delete CUES.words; if (S.cue === 'words') S.cue = 'bowl'; }
  chips($('cue'), 'cue', CUES, 'cue', () => { if (S.cue === 'words' && ctx) loadClips().then(switchCue); else switchCue(); paint(); });
  /* On iPhone and iPad, a web app can't keep playing in the background while mixing with another app, so "My music app" stops
     whenever you switch to it. Hide it there until there's a native app. */
  const appleMobile = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (appleMobile) { delete TRACKS.none; delete MUSICS.none; if (S.track === 'none') S.track = 'classical'; }
  const onTrack = () => { setSession(); cuePiece(); preload(S.track); if (S.track === 'storm') unlockRolls(); paint(); refreshVoice(); };
  chips($('track-moods'), 'track', MOODS, 'track', onTrack);
  chips($('track-noise'), 'track', NOISES, 'track', onTrack);
  chips($('track-music'), 'track', MUSICS, 'track', onTrack);
  preload(S.track);
  chips($('visual'), 'visual', VISUALS, 'visual', paint);
  chips($('palette'), 'palette', Object.fromEntries(Object.entries(PALETTES).map(([k, v]) => [k, v.name])), 'palette', paint);

  $('prevPiece').addEventListener('click', () => skipPiece(-1));
  $('nextPiece').addEventListener('click', () => skipPiece(1));
  $('repeatOne').addEventListener('click', () => { S.repeatOne = !S.repeatOne; player.loop = S.repeatOne; save(); paintPiece(); });
  $('go').addEventListener('click', () => !running ? start().catch(() => {
    running = false; $('status').textContent = "Sound couldn't start. Reload the page and press play again.";
  }) : held ? unhold() : hold());
  $('end').addEventListener('click', () => { if (running) stop(); });
  function setSheet(open) {
    $('app').classList.toggle('quiet', !open); $('quiet').setAttribute('aria-expanded', String(open));
  }
  $('quiet').addEventListener('click', () => setSheet($('app').classList.contains('quiet')));
  $('done').addEventListener('click', () => setSheet(false));
  /* Session drawer. The rest of the app is inert while it's open, and focus returns to the button when it closes. */
  let usingKeys = false;
  addEventListener('keydown', () => { usingKeys = true; }, true);
  addEventListener('pointerdown', () => { usingKeys = false; }, true);
  function setDrawer(open) {
    $('sessionSheet').classList.toggle('open', open); $('scrim').classList.toggle('open', open);
    $('app').inert = open; $('sessionBtn').setAttribute('aria-expanded', String(open));
    /* Focus moves to the drawer itself, which shows no ring after a tap. It returns to the button only for keyboard users. */
    if (open) setTimeout(() => $('sessionSheet').focus(), 50); else if (usingKeys) $('sessionBtn').focus();
  }
  const drawerOpen = () => $('sessionSheet').classList.contains('open');
  $('sessionBtn').addEventListener('click', () => setDrawer(true));

  /* Adjust sound sheet: Distance and Tone, with Fine tune folded away until it's wanted. Changes are kept for each sound. */
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const bandsChanged = a => a.bands.some(g => g !== 0);
  const layersChanged = k => (LAYERS[k] || []).some(([key]) => layerValue(adj(k), key) !== layerValue(designed(k), key));
  const changed = k => { const a = adj(k), d = designed(k); return a.distance !== d.distance || a.tone !== d.tone || bandsChanged(a) || layersChanged(k); };
  function summary(k) {
    const a = adj(k), d = designed(k), parts = [];
    if (a.distance !== d.distance) parts.push(a.distance > d.distance ? 'Further away' : 'Closer');
    if (a.tone !== d.tone) parts.push(a.tone > d.tone ? 'brighter' : 'warmer');
    (LAYERS[k] || []).forEach(([key, name]) => { const x = layerValue(a, key), y = layerValue(d, key);
      if (Math.abs(x - y) > 8) parts.push((x > y ? 'more ' : 'less ') + name.toLowerCase()); });
    if (bandsChanged(a)) parts.push('fine tuned');
    if (!parts.length) return 'As designed';
    const text = parts.slice(0, 3).join(', ') + (parts.length > 3 ? ' and more' : '');
    return text[0].toUpperCase() + text.slice(1);
  }
  const fill = (el, lo, hi, prop = '--v') => el.style.setProperty(prop, (el.value - lo) / (hi - lo) * 100 + '%');
  /* Boost and cut sliders fill outwards from the middle. */
  const fillMid = el => { const v = (el.value - el.min) / (el.max - el.min) * 100; el.style.setProperty('--lo', Math.min(v, 50) + '%'); el.style.setProperty('--hi', Math.max(v, 50) + '%'); };
  function store(k, change) { const a = adj(k); change(a); const d = designed(k);
    const keep = {}; ['distance', 'tone'].forEach(x => { if (a[x] !== d[x]) keep[x] = a[x]; });
    if (bandsChanged(a)) keep.bands = a.bands;
    const layers = {}; Object.entries(a.layers).forEach(([key, x]) => { if (x !== layerValue(d, key)) layers[key] = x; });
    if (Object.keys(layers).length) keep.layers = layers;
    if (Object.keys(keep).length) S.adjust[k] = keep; else delete S.adjust[k];
    save(); if (voice && voice.kind === k) applyAdjust(voice);
    $('adjustSum').textContent = summary(k); $('fineSum').textContent = fineText(k);
    $('sum-music').textContent = TRACKS[S.track][0] + (changed(S.track) ? ', adjusted' : '');
  }
  const fineText = k => { const a = adj(k), n = (layersChanged(k) ? 1 : 0) + (bandsChanged(a) ? 1 : 0);
    return n ? (layersChanged(k) && bandsChanged(a) ? 'Mix and frequencies changed' : layersChanged(k) ? 'Mix changed' : 'Frequencies changed') : 'Not changed'; };
  function paintAdjust() {
    const k = S.track; $('adjustBtn').hidden = !adjustable(k);
    if (!adjustable(k)) return;
    const a = adj(k);
    $('adjustTitle').textContent = TRACKS[k][0]; $('adjustSum').textContent = summary(k); $('fineSum').textContent = fineText(k);
    $('adjDistance').value = a.distance; fill($('adjDistance'), 0, 100);
    $('adjTone').value = a.tone; fill($('adjTone'), -100, 100);
    const box = $('layers'); box.textContent = '';
    if (LAYERS[k]) { const h = document.createElement('p'); h.className = 'group-label'; h.textContent = 'Mix'; box.append(h); }
    (LAYERS[k] || []).forEach(([key, name]) => {
      const row = document.createElement('div'), label = document.createElement('label'), input = document.createElement('input');
      row.className = 'row'; label.htmlFor = 'layer-' + key; label.textContent = name;
      Object.assign(input, { type: 'range', min: 0, max: 100, step: 1, id: 'layer-' + key, value: layerValue(a, key) }); fill(input, 0, 100);
      input.addEventListener('input', () => { fill(input, 0, 100); store(k, x => { x.layers[key] = +input.value; }); });
      row.append(label, input); box.append(row);
    });
    const faders = $('faders'); faders.textContent = '';
    const db = x => x > 0 ? '+' + x : x < 0 ? '−' + -x : '0';
    BANDS.forEach((f, i) => {
      const row = document.createElement('div'), label = document.createElement('label'), out = document.createElement('output'), input = document.createElement('input');
      row.className = 'row'; label.htmlFor = 'band-' + i; label.textContent = BAND_NAMES[i] + ' '; out.textContent = db(a.bands[i]); label.append(out);
      Object.assign(input, { type: 'range', min: -12, max: 12, step: 1, id: 'band-' + i, value: a.bands[i] }); fillMid(input);
      input.addEventListener('input', () => { fillMid(input); out.textContent = db(+input.value);
        store(k, x => { x.bands = [...x.bands]; x.bands[i] = +input.value; }); });
      row.append(label, input); faders.append(row);
    });
  }
  $('adjDistance').addEventListener('input', e => { fill(e.target, 0, 100); store(S.track, x => { x.distance = +e.target.value; }); });
  $('adjTone').addEventListener('input', e => { fill(e.target, -100, 100); store(S.track, x => { x.tone = +e.target.value; }); });
  $('fineBtn').addEventListener('click', () => { const open = $('fine').hidden; $('fine').hidden = !open; $('fineBtn').setAttribute('aria-expanded', String(open)); });
  $('adjustReset').addEventListener('click', () => { delete S.adjust[S.track]; save(); if (voice && voice.kind === S.track) applyAdjust(voice); paint(); });
  function setAdjust(open) {
    if (open) { paintAdjust(); $('fine').hidden = true; $('fineBtn').setAttribute('aria-expanded', 'false'); }
    $('adjustSheet').classList.toggle('open', open); $('scrim').classList.toggle('open', open);
    $('app').inert = open; $('adjustBtn').setAttribute('aria-expanded', String(open));
    if (open) setTimeout(() => $('adjustSheet').focus(), 50); else if (usingKeys) $('adjustBtn').focus();
  }
  const adjustOpen = () => $('adjustSheet').classList.contains('open');
  $('adjustBtn').addEventListener('click', () => setAdjust(true));
  $('adjustDone').addEventListener('click', () => setAdjust(false));
  $('sessionDone').addEventListener('click', () => setDrawer(false));
  $('scrim').addEventListener('click', () => { if (adjustOpen()) setAdjust(false); else setDrawer(false); });
  document.addEventListener('keydown', e => {
    if (e.key !== 'Escape') return;
    if (adjustOpen()) setAdjust(false); else if (drawerOpen()) setDrawer(false); else if (innerWidth < 900) setSheet(false);
  });
  const backOnScreen = () => { if (running && !document.hidden) { lockScreen(); tryResume(); } };
  document.addEventListener('visibilitychange', backOnScreen);
  addEventListener('pageshow', backOnScreen);
  addEventListener('focus', backOnScreen);
  /* A tap counts as permission to play, which phones need before sound can restart after some interruptions. */
  $('resume').addEventListener('click', () => {
    if (!running) return;
    if (held) { unhold(); return; }
    paused = true;
    ctx.resume().then(() => { if (ctx.state === 'running') soundBack(); }).catch(() => {
      $('status').textContent = "Sound couldn't restart. Try again, or end the session and press play.";
    });
  });

  /* Larger screens start with the everyday panels open; phones start with only the volumes. */
  const opened = S.open || (innerWidth >= 900 ? ['pace', 'music'] : ['pace']);
  document.querySelectorAll('.panel').forEach(panel => {
    panel.open = opened.includes(panel.id.replace('panel-', ''));
    panel.addEventListener('toggle', () => {
      S.open = [...document.querySelectorAll('.panel[open]')].map(q => q.id.replace('panel-', '')); save();
    });
  });

  /* Offline use and updates (see sw.js). A new version is only offered while nothing is playing, so a session is never cut off. */
  let waiting = null, updating = false;
  function showUpdate() { $('update').hidden = !waiting || running; }
  if ('serviceWorker' in navigator) {
    const sw = navigator.serviceWorker;
    const ready = w => { if (w && sw.controller) { waiting = w; showUpdate(); } };
    sw.register('sw.js', { updateViaCache: 'none' }).then(reg => {
      ready(reg.waiting);
      const watch = w => w && w.addEventListener('statechange', () => { if (w.state === 'installed') ready(w); });
      watch(reg.installing);
      reg.addEventListener('updatefound', () => watch(reg.installing));
      /* An installed app can stay open for days, so look for a new version when it comes back to the front. */
      let checked = Date.now();
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden && Date.now() - checked > 30 * 60e3) { checked = Date.now(); reg.update().catch(() => {}); }
      });
    }).catch(() => {});
    sw.addEventListener('controllerchange', () => { if (updating) location.reload(); else { waiting = null; showUpdate(); } });
    $('update').addEventListener('click', () => { if (waiting && !running) { updating = true; waiting.postMessage('update'); } });
  }

  /* Launch screen: CSS plays and hides it. A tap or key press skips it, and it's removed once it has faded. */
  const splash = $('splash');
  const skipSplash = () => splash.classList.add('skip');
  splash.addEventListener('pointerdown', skipSplash);
  document.addEventListener('keydown', skipSplash, { once: true });
  splash.addEventListener('animationend', e => {
    if (e.animationName === 'splash-out') { splash.remove(); document.body.classList.remove('launch'); }
  });

  /* Size the app to the visible screen. See --app-height in styles.css. */
  const fitScreen = () => {
    let h = innerHeight;
    /* An iPhone home-screen app that draws under the status bar is laid out one status bar too short, leaving an empty
       band at the bottom. When the app fills the screen there, use the screen's full height instead. */
    if (navigator.standalone) {
      const landscape = innerWidth > innerHeight, long = Math.max(screen.width, screen.height), short = Math.min(screen.width, screen.height);
      if (Math.abs(innerWidth - (landscape ? long : short)) < 2) h = Math.max(h, landscape ? short : long);
    }
    const root = document.documentElement.style;
    root.setProperty('--app-height', h + 'px');
    /* How far the real bottom of the screen sits below the layout's bottom, so sheets fixed to the bottom reach it. */
    root.setProperty('--short', (h - innerHeight) + 'px');
  };
  fitScreen(); addEventListener('resize', fitScreen); addEventListener('orientationchange', () => setTimeout(fitScreen, 300));

  setSheet(innerWidth >= 900);
  paint(); resetPreview(); setInterval(tick, 250); draw();
  count('app opened', {
    installed: matchMedia('(display-mode: standalone)').matches || navigator.standalone === true,
    device: /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.maxTouchPoints > 1 && /Mac/.test(navigator.platform)) ? 'iphone or ipad'
      : /Android/.test(navigator.userAgent) ? 'android' : 'computer'
  });
})();
