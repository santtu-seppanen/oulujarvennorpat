// Protokollatesti paikallista palvelinta vasten: npx wrangler dev & node test.mjs
const URL = process.env.NORPAT_URL ?? "ws://localhost:8787/huone/TESTI" + Math.floor(Math.random() * 1e6);
const open = () => new Promise((res) => {
  const ws = new WebSocket(URL);
  ws.msgs = [];
  ws.onmessage = (e) => ws.msgs.push(JSON.parse(e.data));
  ws.onopen = () => res(ws);
  ws.onclose = () => res(ws);
});
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
let fails = 0;
const check = (ok, what) => { console.log((ok ? "OK   " : "VIKA ") + what); if (!ok) fails++; };

const a = await open(); await wait(200);
const b = await open(); await wait(200);
check(a.msgs[0]?.t === "welcome" && a.msgs[0].host === a.msgs[0].id, "ensimmäinen on host");
check(b.msgs[0]?.t === "welcome" && b.msgs[0].host === a.msgs[0].id, "toinen saa hostin tunnuksen");
check(a.msgs[1]?.t === "join" && a.msgs[1].id === b.msgs[0].id, "host näkee liittymisen");
a.send(JSON.stringify({ t: "s", x: 1 })); await wait(200);
check(b.msgs.at(-1)?.t === "s" && b.msgs.at(-1).from === a.msgs[0].id, "viesti välittyy lähettäjän kanssa");
const c = await open(); const d = await open(); await wait(200);
const e = await open(); await wait(300);
check(e.msgs[0]?.t === "full", "viides ei mahdu");
b.send(JSON.stringify({ t: "p", to: c.msgs[0].id })); await wait(200);
check(c.msgs.at(-1)?.t === "p" && d.msgs.at(-1)?.t !== "p", "to rajaa vastaanottajan");
a.close(); await wait(400);
const lv = b.msgs.at(-1);
check(lv?.t === "leave" && lv.host === b.msgs[0].id, "host vaihtuu lähtiessä");
[b, c, d].forEach((w) => w.close());
console.log("vikoja " + fails);
process.exit(fails ? 1 : 0);
