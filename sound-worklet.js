/* Swellotic's learned sounds, played on the audio thread.

   Browsers normally keep decoded sound as 32-bit numbers at the device's rate, which made Night storm hold about 120MB.
   This keeps each loop as 16-bit samples at the rate it was made at, as the iPhone app does, and plays it from there:
   the same sound in about a third of the memory, or less for the wind, which was made at half the rate.

   CLIPS is shared by every processor in the audio context. app.js sends each decoded loop once, through the bank node,
   and any number of loops can then play it without copying. */
const CLIPS = new Map();

/* Receives loops from app.js. Its one output is never connected (browsers need at least one), so it costs nothing. */
class Bank extends AudioWorkletProcessor {
  constructor() {
    super();
    this.port.onmessage = e => {
      const { name, rate, frames, data } = e.data;
      CLIPS.set(name, { rate, frames, data: new Int16Array(data) });
    };
  }
  process() { return true; }
}
registerProcessor('swellotic-bank', Bank);

/* Plays one loop from a random point. It waits silently until its loop arrives, then fades in over half a second, and
   blends between samples, so a loop made at any rate plays at the device's rate. */
class Loop extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const o = options.processorOptions || {};
    this.name = o.name;
    this.offset = o.offset || 0;
    this.clip = null;
    this.pos = 0;
    this.arrive = 0;
    this.stopped = false;
    this.port.onmessage = e => { if (e.data === 'stop') this.stopped = true; };
  }

  process(inputs, outputs) {
    if (this.stopped) return false;
    if (!this.clip) {
      const c = CLIPS.get(this.name);
      if (!c) return true;
      this.clip = c;
      this.pos = Math.floor(this.offset * (c.frames - 1));
    }
    const out = outputs[0], left = out[0], right = out[1] || out[0];
    const c = this.clip, d = c.data, n = c.frames, step = c.rate / sampleRate, scale = 1 / 32768, rise = 2 / sampleRate;
    let p = this.pos, a = this.arrive;
    for (let i = 0; i < left.length; i++) {
      const j = p | 0, f = p - j, k = j + 1 === n ? 0 : j + 1;
      left[i] = (d[2 * j] * (1 - f) + d[2 * k] * f) * scale * a;
      right[i] = (d[2 * j + 1] * (1 - f) + d[2 * k + 1] * f) * scale * a;
      p += step;
      if (p >= n) p -= n;
      if (a < 1) a = Math.min(1, a + rise);
    }
    this.pos = p;
    this.arrive = a;
    return true;
  }
}
registerProcessor('swellotic-loop', Loop);
