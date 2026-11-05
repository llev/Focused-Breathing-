(() => {
  const $ = id => document.getElementById(id);
  const S = { bpm: 6, ratio: 'even', cue: 'bowl', breathVol: 35, musicVol: 55, room: true, ease: false, track: 'brown', limit: 0, visual: 'lava', palette: 'sunset', open: null, words: true, countdown: false };
  try { Object.assign(S, JSON.parse(localStorage.getItem('breathing-room') || '{}')); } catch (e) {}
  const save = () => { try { localStorage.setItem('breathing-room', JSON.stringify(S)); } catch (e) {} };

  const RATIOS = { even: ['Even', .5], long: ['Longer out', .4], longest: ['Much longer out', 1 / 3] };
  const CUES = { bowl: 'Singing bowl', gong: 'Gong', words: 'Spoken words', piano: 'Soft piano', wood: 'Wooden marimba', tone: 'Soft hum', chime: 'Chime', breath: 'Ocean', none: 'Silent' };
  const TRACKS = {
    brown: ['Brown noise', 'Generated on your device, so it works offline.'],
    pink: ['Pink noise', 'Generated on your device, so it works offline.'],
    rain: ['Rain', 'Generated on your device, so it works offline.'],
    beach: ['Beach', 'Slow, soft waves generated on your device, so it works offline.'],
    stream: ['Stream', 'Generated on your device, so it works offline.'],
    wind: ['Wind', 'Generated on your device, so it works offline.'],
    fire: ['Fireplace', 'Generated on your device, so it works offline.'],
    ambient: ['Ambient', 'Slow chords generated on your device, so it works offline.'],
    keys: ['Soft keys', 'A simple generated sketch, not a finished recording.'],
    own: ['Audio files', 'Add audio files from this device. They stay on this device and play on a loop.'],
    none: ['My music app', 'Play music in Spotify, Apple Music or any other app, then press play here. The Breath slider changes only the breaths, and your music app controls the music. On a phone, the side buttons change both, so use the Breath slider to balance them.']
  };
  const LIMITS = { 0: 'No limit', 25: '25 min', 50: '50 min', 90: '90 min' };
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
  const ownBuffers = [];
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
    A = { master, breathBus, musicLevel, musicBus, dry, wet, far,
      cueNoise: loopBuffer(6, 1, white), brownBuf: null, whiteBuf: null };
    newCueBus();
    applyLevels();
    loadClips();
    ctx.onstatechange = () => {
      if (!running) return;
      if (ctx.state === 'running') soundBack();
      else { paused = true; tryResume(); }
    };
  }

  /* Phones pause web audio when another app takes over, the screen locks or the app leaves the screen.
     Restart it when Swellotic is back on screen, and ask for a tap where the phone won't allow that. */
  let paused = false;
  async function tryResume() {
    if (!running || !ctx || ctx.state === 'running' || document.hidden) return;
    try { await Promise.race([ctx.resume(), new Promise(r => setTimeout(r, 1500))]); } catch (e) {}
    if (!running) return;
    if (ctx.state === 'running') soundBack(); else showResume(true);
  }
  function soundBack() {
    if (!paused) return;
    paused = false; showResume(false);
    /* The audio clock stops while paused, so the breath carries on from where it was. Replan the breath sounds and fade in gently. */
    const t = ctx.currentTime;
    A.master.gain.cancelScheduledValues(t); A.master.gain.setValueAtTime(0, t); A.master.gain.linearRampToValueAtTime(1, t + .8);
    switchCue();
    lockScreen();
  }
  function showResume(show) { $('resume').hidden = !show; }

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

  function startVoice(kind) {
    const out = ctx.createGain(), t = ctx.currentTime; out.gain.setValueAtTime(0, t);
    out.gain.linearRampToValueAtTime(1, t + 1.2); out.connect(A.musicBus);
    const v = { out, stopped: false, sources: [], tick() {} };
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
      lp.connect(g); g.connect(out); hp.connect(out); looped(b.brown, lp);
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
    } else if (kind === 'own' && ownBuffers.length) {
      let i = 0;
      const play = () => {
        if (v.stopped || !ownBuffers.length) return;
        const s = ctx.createBufferSource(); s.buffer = ownBuffers[i++ % ownBuffers.length].buffer;
        s.connect(out); s.onended = play; s.start(); v.sources = [s];
      };
      play();
    }
    return v;
  }
  function stopVoice(v) {
    if (!v) return;
    v.stopped = true; const t = ctx.currentTime;
    v.out.gain.cancelScheduledValues(t); v.out.gain.setTargetAtTime(0, t, .25);
    setTimeout(() => { v.sources.forEach(s => { s.onended = null; try { s.stop(); } catch (e) {} }); v.out.disconnect(); }, 1200);
  }
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
    const elapsed = ctx.currentTime - sessionStart;
    $('clock').textContent = fmt(elapsed);
    if (S.limit && elapsed >= S.limit * 60) stop('Session finished.');
  }

  function setGo() { $('go').classList.toggle('playing', running); $('go').setAttribute('aria-label', running ? 'Stop' : 'Start'); showUpdate(); }
  async function lockScreen() { try { wake = await navigator.wakeLock.request('screen'); } catch (e) { wake = null; } }

  async function start() {
    ensureAudio();
    setSession();
    await ctx.resume();
    if (S.cue === 'words') await loadClips();
    running = true; paused = false; showResume(false); sessionStart = ctx.currentTime;
    phases = []; nextStart = ctx.currentTime + .3; cueNodes = [];
    A.master.gain.cancelScheduledValues(sessionStart);
    A.master.gain.setValueAtTime(0, sessionStart); A.master.gain.linearRampToValueAtTime(1, sessionStart + .8);
    applyLevels(); voice = startVoice(S.track); schedule(); voice.tick(ctx.currentTime, ctx.currentTime + 5);
    setGo(); $('clock').textContent = fmt(0); $('clock').hidden = false;
    $('status').textContent = S.track === 'own' && !ownBuffers.length ? 'Add audio files to hear your music.' : '';
    lockScreen();
  }
  function stop(message) {
    const t = ctx.currentTime;
    A.master.gain.cancelScheduledValues(t); A.master.gain.setTargetAtTime(0, t, .15);
    stopVoice(voice); voice = null; running = false; paused = false; showResume(false);
    const nodes = cueNodes; cueNodes = [];
    setTimeout(() => { nodes.forEach(n => { try { n.stop(); } catch (e) {} }); if (!running) ctx.suspend(); }, 700);
    setGo(); $('clock').hidden = true;
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
      const word = p.type === 'in' ? 'In' : 'Out';
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
    $('sum-music').textContent = TRACKS[S.track][0];
    $('sum-look').textContent = `${VISUALS[S.visual]}, ${PALETTES[S.palette].name}`;
    $('sum-sess').textContent = S.limit ? `${S.limit} minutes` : 'No time limit';
    $('word').hidden = !S.words; $('timing').hidden = !S.countdown;
    document.documentElement.style.setProperty('--tint', PALETTES[S.palette].tint);
    [['breathVol', 0, 100], ['musicVol', 0, 100], ['bpm', 2, 12]].forEach(([id, lo, hi]) => $(id).style.setProperty('--v', ($(id).value - lo) / (hi - lo) * 100 + '%'));
    $('own').hidden = S.track !== 'own'; $('trackNote').textContent = TRACKS[S.track][1];
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
  chips($('limit'), 'limit', LIMITS, 'limit', () => { S.limit = +S.limit; save(); paint(); });
  chips($('ratio'), 'ratio', RATIOS, 'ratio', () => { paint(); resetPreview(); });
  if (!VOICE_CLIPS) { delete CUES.words; if (S.cue === 'words') S.cue = 'bowl'; }
  chips($('cue'), 'cue', CUES, 'cue', () => { if (S.cue === 'words' && ctx) loadClips().then(switchCue); else switchCue(); paint(); });
  chips($('track'), 'track', TRACKS, 'track', () => { setSession(); paint(); refreshVoice(); });
  chips($('visual'), 'visual', VISUALS, 'visual', paint);
  chips($('palette'), 'palette', Object.fromEntries(Object.entries(PALETTES).map(([k, v]) => [k, v.name])), 'palette', paint);

  $('file').addEventListener('change', async e => {
    ensureAudio();
    const list = [...e.target.files]; e.target.value = '';
    for (const f of list) {
      $('status').textContent = `Loading ${f.name}…`;
      try {
        const buffer = await ctx.decodeAudioData(await f.arrayBuffer());
        ownBuffers.push({ name: f.name, buffer });
        const li = document.createElement('li'); li.textContent = f.name; $('files').append(li);
      } catch (err) { $('status').textContent = `${f.name} could not be read. Try an MP3, M4A or WAV file.`; return; }
    }
    $('status').textContent = '';
    if (running && S.track === 'own') refreshVoice();
  });
  $('go').addEventListener('click', () => running ? stop() : start().catch(() => {
    running = false; $('status').textContent = 'Sound could not start. Reload the page and press Start again.';
  }));
  function setSheet(open) {
    $('app').classList.toggle('quiet', !open); $('quiet').setAttribute('aria-expanded', String(open));
  }
  $('quiet').addEventListener('click', () => setSheet($('app').classList.contains('quiet')));
  $('done').addEventListener('click', () => setSheet(false));
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && innerWidth < 900) setSheet(false); });
  const backOnScreen = () => { if (running && !document.hidden) { lockScreen(); tryResume(); } };
  document.addEventListener('visibilitychange', backOnScreen);
  addEventListener('pageshow', backOnScreen);
  addEventListener('focus', backOnScreen);
  /* A tap counts as permission to play, which phones need before sound can restart after some interruptions. */
  $('resume').addEventListener('click', () => {
    if (!running) return;
    paused = true;
    ctx.resume().then(() => { if (ctx.state === 'running') soundBack(); }).catch(() => {
      $('status').textContent = 'Sound could not restart. Press stop, then play.';
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

  setSheet(innerWidth >= 900);
  paint(); resetPreview(); setInterval(tick, 250); draw();
})();
