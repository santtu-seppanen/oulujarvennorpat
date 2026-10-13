// Äänilinkin selainpuolen pakkauksen testi (Node, ilman selainta): node tools/testit/aanilinkki_js.mjs
// --vertailu tulostaa vain vertailukehykset (JSON), joita tools/testit/aanilinkkitesti.gd vertaa GDScriptin
// pakkaukseen: selaimen ja työpöytäversion pitää pakata bitilleen samoin.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const src = readFileSync(fileURLToPath(new URL("../../scripts/aanilinkki.js", import.meta.url)), "utf8");
new Function(src)();
const V = globalThis.NorpatVoice;

// Kokonaisluvuista laskettu signaali (sama kuin aanilinkkitesti.gd): kaksi kolmioaaltoa (n. 185 Hz ja 2,8 kHz).
function signal(frames) {
  const x = new Float32Array(frames * V.FRAME);
  for (let k = 0; k < x.length; k++) {
    const a = Math.abs(((k * 37) % 4000) - 2000) - 1000;
    const b = Math.abs(((k * 211) % 600) - 300) - 150;
    x[k] = (a * 12 + b * 20) / 32767;
  }
  return x;
}

const x = signal(5);
const st = { p: 0, i: 0 };
const enc = [];
for (let f = 0; f < 5; f++) enc.push(V.toB64(V.encode(x.subarray(f * V.FRAME, (f + 1) * V.FRAME), st)));

if (process.argv.includes("--vertailu")) {
  const dec = V.decode(V.fromB64(enc[4]));
  let sum = 0;
  for (const v of dec) sum += Math.round(v * 32768);
  console.log(JSON.stringify({ enc, sum }));
  process.exit(0);
}

let fails = 0;
const check = (ok, what) => { console.log((ok ? "OK   " : "VIKA ") + what); if (!ok) fails++; };

// Pakkaus ja purku: signaali-kohinasuhde.
let e = 0, n = 0;
const st2 = { p: 0, i: 0 };
for (let f = 0; f < 5; f++) {
  const fr = x.subarray(f * V.FRAME, (f + 1) * V.FRAME);
  const y = V.decode(V.encode(fr, st2));
  for (let k = 0; k < fr.length; k++) { e += fr[k] * fr[k]; n += (fr[k] - y[k]) ** 2; }
}
const snr = 10 * Math.log10(e / n);
check(snr > 20, `pakkaus ja purku: SNR ${snr.toFixed(1)} dB`);
check(enc[0].length < 700, `kehys ${enc[0].length} merkkiä (alle palvelimen 8192)`);

// Hiljaisuus ei lähde, puhe lähtee ja perään HANG kehystä jälkiääntä.
V._out = [];
V._hang = 0;
V.muted = false;
const quiet = new Float32Array(V.FRAME);
const loud = x.subarray(0, V.FRAME);
V._frame(quiet);
check(V._out.length === 0, "hiljaisuus ei lähde");
V._frame(loud);
for (let k = 0; k < V.HANG + 3; k++) V._frame(quiet);
check(V._out.length === 1 + V.HANG, `puhe ja ${V.HANG} kehystä jälkiääntä lähti (${V._out.length})`);
V._out = [];
V.setMuted(true);
V._frame(loud);
check(V._out.length === 0, "mykistettynä ei lähde");
const t = JSON.parse(V.take());
check(Array.isArray(t.f) && t.on === false && t.e === "", "take() palauttaa tilan");

console.log("vikoja " + fails);
process.exit(fails ? 1 : 0);
