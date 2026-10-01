// Oulujärven norpat: moninpelin välityspalvelin. Jokainen huone (koodi, esim. "NORP") on oma Durable Object,
// joka välittää pelaajien JSON-viestit toisilleen. Pelilogiikka on pelissä: ensimmäisenä liittynyt pelaaja on
// host, joka ohjaa vapaita hahmoja ja kelloa. Palvelin vain jakaa tunnukset, kertoo kuka on host ja välittää.
//
//   GET /huone/<KOODI>   WebSocket-yhteys huoneeseen
//
// Palvelimelta: {t:"welcome", id, host, peers}, {t:"join", id, host}, {t:"leave", id, host} ja täydestä
// huoneesta {t:"full"}, jonka jälkeen pelaaja sulkee yhteyden itse.
// Pelaajien viestit välitetään muille sellaisenaan, kenttä from lisättynä; kenttä to rajaa vastaanottajan.

import { DurableObject } from "cloudflare:workers";

const MAX_PLAYERS = 4; // mökin porukka
const MAX_MSG = 8192;

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const m = url.pathname.match(/^\/huone\/([A-Za-z0-9]{3,12})$/);
    if (!m) {
      return new Response("Oulujärven norpat: moninpelipalvelin\n", { headers: { "content-type": "text/plain; charset=utf-8" } });
    }
    if (req.headers.get("Upgrade") !== "websocket") {
      return new Response("WebSocket-yhteys tarvitaan\n", { status: 426 });
    }
    const room = env.ROOMS.get(env.ROOMS.idFromName(m[1].toUpperCase()));
    return room.fetch(req);
  },
};

export class Room extends DurableObject {
  // Avoimet yhteydet tunnuksineen; säilyy horrostilan yli (attachment).
  peers(except) {
    const out = [];
    for (const ws of this.ctx.getWebSockets()) {
      if (ws === except || ws.readyState !== WebSocket.OPEN) continue;
      const a = ws.deserializeAttachment();
      if (a && !a.left) out.push({ ws, id: a.id });
    }
    return out;
  }

  host(peers) {
    return peers.length ? Math.min(...peers.map((p) => p.id)) : 0;
  }

  async fetch(req) {
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    const others = this.peers(server);
    if (others.length >= MAX_PLAYERS) {
      // Ei suljeta heti: muuten selain ei ehdi nähdä viestiä vaan pelkän epäonnistuneen yhteyden.
      server.serializeAttachment({ left: true });
      server.send(JSON.stringify({ t: "full" }));
      return new Response(null, { status: 101, webSocket: client });
    }
    const id = (await this.ctx.storage.get("next")) ?? 1;
    await this.ctx.storage.put("next", id + 1);
    server.serializeAttachment({ id });
    const all = [...others, { ws: server, id }];
    const host = this.host(all);
    server.send(JSON.stringify({ t: "welcome", id, host, peers: others.map((p) => p.id) }));
    const join = JSON.stringify({ t: "join", id, host });
    for (const p of others) p.ws.send(join);
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, msg) {
    if (typeof msg !== "string" || msg.length > MAX_MSG) return;
    const a = ws.deserializeAttachment();
    if (!a || a.left) return;
    let d;
    try {
      d = JSON.parse(msg);
    } catch {
      return;
    }
    if (d === null || typeof d !== "object" || Array.isArray(d)) return;
    d.from = a.id;
    const out = JSON.stringify(d);
    for (const p of this.peers(ws)) {
      if (d.to === undefined || d.to === p.id) p.ws.send(out);
    }
  }

  webSocketClose(ws, code) {
    this.gone(ws);
    try {
      ws.close(code === 1005 || code === 1006 ? 1000 : code, "bye");
    } catch {}
  }

  webSocketError(ws) {
    this.gone(ws);
  }

  gone(ws) {
    const a = ws.deserializeAttachment();
    if (!a || a.left) return;
    ws.serializeAttachment({ ...a, left: true });
    const rest = this.peers(ws);
    const leave = JSON.stringify({ t: "leave", id: a.id, host: this.host(rest) });
    for (const p of rest) p.ws.send(leave);
  }
}
