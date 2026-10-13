// Oulujärven norpat: moninpelin äänilinkki selaimessa (scripts/aanilinkki.gd lataa tämän JavaScriptBridgellä).
// Mikki kaapataan selaimen getUserMedialla (kaiunpoisto, kohinanvaimennus ja automaattinen taso päällä) ja
// toisten puhe soitetaan Web Audiolla suoraan, ohi Godotin miksauksen: säikeettömässä selainbuildissa
// Godot miksaa pääsäikeessä, ja pitkät ruudut rikkoisivat puheen.
// Pakkaus on sama kuin työpöytäversiossa (aanilinkki.gd): 16 kHz mono, IMA ADPCM, 960 näytettä (60 ms) kehyksessä,
// otsake: ennustin (int16 LE), askelindeksi, 0. Kehys base64-merkkijonona välityspalvelimen kautta.
// Testi Nodella: node tools/testit/aanilinkki_js.mjs (ilman selainta vain pakkaus).

(function (g) {
  const RATE = 16000;
  const FRAME = 960;
  const GATE = 0.008; // kehyksen RMS, jonka ylittyessä puhe lähtee
  const HANG = 8; // kehystä hiljaisuutta ennen kuin lähetys taukoaa
  const PREBUF = 0.12; // s: puheen alussa puskuria ennen soittoa
  const MAX_LAG = 0.5; // s: tätä enempää viivettä ei kerätä (pudotetaan kehyksiä)
  const IT = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8];
  const ST = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80,
    88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724,
    796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428,
    4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385,
    24623, 27086, 29794, 32767];

  // Kehys (Float32Array, FRAME näytettä) tavuiksi; st = {p, i} jatkuu kehyksestä toiseen.
  function encode(x, st) {
    const out = new Uint8Array(4 + x.length / 2);
    out[0] = st.p & 0xff;
    out[1] = (st.p >> 8) & 0xff;
    out[2] = st.i;
    let p = st.p;
    let i = st.i;
    for (let k = 0; k < x.length; k++) {
      const s = Math.max(-32768, Math.min(32767, Math.round(x[k] * 32767)));
      let diff = s - p;
      let nib = 0;
      if (diff < 0) {
        nib = 8;
        diff = -diff;
      }
      let step = ST[i];
      let vp = step >> 3;
      if (diff >= step) { nib |= 4; diff -= step; vp += step; }
      step >>= 1;
      if (diff >= step) { nib |= 2; diff -= step; vp += step; }
      step >>= 1;
      if (diff >= step) { nib |= 1; vp += step; }
      p = Math.max(-32768, Math.min(32767, p + (nib & 8 ? -vp : vp)));
      i = Math.max(0, Math.min(88, i + IT[nib]));
      if (k & 1) out[4 + (k >> 1)] |= nib << 4;
      else out[4 + (k >> 1)] = nib;
    }
    st.p = p;
    st.i = i;
    return out;
  }

  function decode(b) {
    const n = (b.length - 4) * 2;
    const out = new Float32Array(n);
    let p = (b[0] | (b[1] << 8)) << 16 >> 16;
    let i = Math.min(88, b[2]);
    for (let k = 0; k < n; k++) {
      const nib = k & 1 ? b[4 + (k >> 1)] >> 4 : b[4 + (k >> 1)] & 15;
      const step = ST[i];
      let vp = step >> 3;
      if (nib & 4) vp += step;
      if (nib & 2) vp += step >> 1;
      if (nib & 1) vp += step >> 2;
      p = Math.max(-32768, Math.min(32767, p + (nib & 8 ? -vp : vp)));
      i = Math.max(0, Math.min(88, i + IT[nib]));
      out[k] = p / 32768;
    }
    return out;
  }

  function toB64(b) {
    let s = "";
    for (let k = 0; k < b.length; k++) s += String.fromCharCode(b[k]);
    return btoa(s);
  }

  function fromB64(s) {
    const t = atob(s);
    const b = new Uint8Array(t.length);
    for (let k = 0; k < t.length; k++) b[k] = t.charCodeAt(k);
    return b;
  }

  function rms(x) {
    let e = 0;
    for (let k = 0; k < x.length; k++) e += x[k] * x[k];
    return Math.sqrt(e / x.length);
  }

  // Mikin näytteet 16 kHz:iin (keskiarvo kunkin lähtönäytteen väliltä) ja kehyksiksi.
  const WORKLET = `
class NorpatCap extends AudioWorkletProcessor {
  constructor() {
    super();
    this.r = sampleRate / ${RATE};
    this.pos = 0; this.acc = 0; this.n = 0; this.k = 0;
    this.buf = new Float32Array(${FRAME});
  }
  process(inputs) {
    const x = inputs[0] && inputs[0][0];
    if (!x) return true;
    for (let i = 0; i < x.length; i++) {
      this.acc += x[i]; this.n++; this.pos += 1;
      if (this.pos >= this.r) {
        this.pos -= this.r;
        this.buf[this.k++] = this.acc / this.n;
        this.acc = 0; this.n = 0;
        if (this.k === ${FRAME}) { this.port.postMessage(this.buf.slice()); this.k = 0; }
      }
    }
    return true;
  }
}
registerProcessor("norpat-cap", NorpatCap);
`;

  const V = {
    RATE, FRAME, GATE, HANG, encode, decode, toB64, fromB64, rms,
    muted: false,
    on: false, // mikki käynnissä
    error: "",
    _ctx: null,
    _gain: null,
    _stream: null,
    _node: null,
    _out: [],
    _st: { p: 0, i: 0 },
    _hang: 0,
    _next: {}, // pelaajan tunnus -> seuraavan kehyksen soittoaika
    _talk: false,

    _ensureCtx() {
      if (!this._ctx) {
        this._ctx = new (g.AudioContext || g.webkitAudioContext)();
        this._gain = this._ctx.createGain();
        this._gain.connect(this._ctx.destination);
        // Selain voi pitää äänikontekstin pysähdyksissä, kunnes käyttäjä koskee sivuun.
        const resume = () => { if (this._ctx.state !== "running") this._ctx.resume(); };
        g.addEventListener("pointerdown", resume);
        g.addEventListener("keydown", resume);
      }
      if (this._ctx.state !== "running") this._ctx.resume();
      return this._ctx;
    },

    async start() {
      if (this.on || this._starting) return;
      this._starting = true;
      this.error = "";
      try {
        const ctx = this._ensureCtx();
        this._stream = await navigator.mediaDevices.getUserMedia({
          audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 },
        });
        const url = URL.createObjectURL(new Blob([WORKLET], { type: "application/javascript" }));
        await ctx.audioWorklet.addModule(url);
        URL.revokeObjectURL(url);
        const src = ctx.createMediaStreamSource(this._stream);
        this._node = new AudioWorkletNode(ctx, "norpat-cap");
        this._node.port.onmessage = (e) => this._frame(e.data);
        // Työkappale tarvitsee ulostulon pysyäkseen käynnissä: hiljainen haara kaiuttimiin.
        const mute = ctx.createGain();
        mute.gain.value = 0;
        src.connect(this._node);
        this._node.connect(mute);
        mute.connect(ctx.destination);
        this.on = true;
      } catch (e) {
        this.error = e && e.name === "NotAllowedError" ? "lupa" : String((e && e.message) || e);
        this.stop();
      }
      this._starting = false;
    },

    stop() {
      if (this._node) {
        this._node.port.onmessage = null;
        this._node.disconnect();
        this._node = null;
      }
      if (this._stream) {
        this._stream.getTracks().forEach((t) => t.stop());
        this._stream = null;
      }
      this.on = false;
      this._out = [];
      this._hang = 0;
      this._talk = false;
    },

    _frame(x) {
      const loud = rms(x) > GATE;
      if (this.muted || (!loud && this._hang <= 0)) {
        this._talk = false;
        return;
      }
      this._hang = loud ? HANG : this._hang - 1;
      this._talk = true;
      this._out.push(toB64(encode(x, this._st)));
    },

    setMuted(m) {
      this.muted = !!m;
    },

    setVolume(v) {
      this._ensureCtx();
      this._gain.gain.value = v;
    },

    // Godot hakee joka ruudulla: lähetettävät kehykset ja tila.
    take() {
      const f = this._out;
      this._out = [];
      return JSON.stringify({ f, on: this.on, e: this.error, talk: this._talk });
    },

    play(id, s) {
      const ctx = this._ensureCtx();
      const x = decode(fromB64(s));
      const now = ctx.currentTime;
      let t = this._next[id] || 0;
      if (t < now + 0.02) t = now + PREBUF; // puheen alku tai katko: pieni puskuri
      else if (t > now + MAX_LAG) return; // ruuhka: kehys pois, ettei viive kasva
      const b = ctx.createBuffer(1, x.length, RATE);
      b.copyToChannel(x, 0);
      const src = ctx.createBufferSource();
      src.buffer = b;
      src.connect(this._gain);
      src.start(t);
      this._next[id] = t + x.length / RATE;
    },
  };
  g.NorpatVoice = V;
})(globalThis);
