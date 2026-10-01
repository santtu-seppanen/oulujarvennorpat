"""Oulujärven norppien kartta: oikeasta aineistosta pelin datatiedostoiksi (assets/map/).

Aloituspaikka 64.432089 N, 26.886448 E (Äpätinniemi, Vaala, Oulujärven etelärannalla).
Paikallinen kehys: origo ETRS-TM35FIN E 494531, N 7145169 (MML:n 2 m korkeusmallin pikselin keskipiste,
alle metrin päässä aloituspisteestä), x itään, z etelään, y ylös metreinä Oulujärven pinnasta.

Lähteet (kaikki avoimia, ks. LUEMINUT.md):
- MML korkeusmalli 2 m (CC BY 4.0): lehdet Q4444F, Q4444H, R4333E, R4333G (Kapsin peili).
- MML maastotietokanta (CC BY 4.0): Q4444R, R4333R (järvet, suot, hietikot, kalliot, kivet, vesikivet, matalikot,
  pellot, tiet, polut, rakennukset tyyppeineen, paikannimet).
- MML laserkeilaus 2011 (CC BY 4.0): Q4444F4, Q4444H2, R4333E3, R4333G1 (Funet). Yksittäiset puut latvusmallin
  paikallisista maksimeista (paikka, pituus, latvuksen leveys) ja rakennusten korkeudet.
- Luke VMI 2023 (CC BY 4.0, 16 m): puulajien tilavuusosuudet (mänty, kuusi, koivu, muut lehtipuut),
  keskipituus ja latvuspeitto laserin ulkopuolelle. Luetaan HTTP-aluepyynnöillä vain tarvittavat laatat.
- OpenStreetMap (ODbL): veneenlaskupaikat ja tiennimet.

Järven syvyyksiä ei ole avoimena (MML:n syvyyskäyrät poistettu avoimesta datasta 2012, Traficomin syvyysalueet
eivät ole avoimessa rajapinnassa): pohja arvioidaan etäisyydestä rantaan, matalikoista ja vesikivistä.

Ajo:  python3 -m venv venv && venv/bin/pip install "laspy[lazrs]" numpy scipy tifffile imagecodecs pyshp
      venv/bin/python tools/kartta/bake.py --cache <välimuistikansio>
"""
import argparse
import json
import math
import os
import struct
import urllib.request

import imagecodecs
import laspy
import numpy as np
import shapefile
import tifffile
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "map")

START_LAT, START_LON = 64.432089, 26.886448
E0, N0 = 494531.0, 7145169.0          # kehyksen origo (DEM-pikselin keskipiste)
NEAR_HALF, NEAR_STEP = 1000, 2         # tarkka maasto 2 x 2 km, 2 m ruutu (= DEM:n pikselit)
FAR_HALF, FAR_STEP = 5120, 16          # kaukomaasto 10 x 10 km, 16 m ruutu
DEM_SHEETS = {"R4333E": (0, 0), "R4333G": (0, 1), "Q4444F": (1, 0), "Q4444H": (1, 1)}
DEM_E, DEM_N = 488000.0, 7152000.0     # mosaiikin luoteiskulma (6000 x 6000 pikseliä, 2 m)
LAZ = {"Q4444F4": "Q444", "Q4444H2": "Q444", "R4333E3": "R433", "R4333G1": "R433"}
LAZ_BOX = (491000.0, 7143000.0, 497000.0, 7149000.0)
MTK_SHEETS = {"Q4444R": "Q4/Q44", "R4333R": "R4/R43"}
VMI_THEMES = ["manty", "kuusi", "koivu", "muulp", "keskipituus", "latvuspeitto"]

KAPSI = "https://kartat.kapsi.fi/files/"
FUNET = "https://www.nic.funet.fi/index/geodata/"
UA = {"User-Agent": "oulujarvennorpat-kartta/1.0"}

# Pintaluokat (sama numerointi kuin scripts/map.gd).
FOREST, WATER, SAND, ROCK, BOG, FIELD, YARD, ROAD, PATH, CLEARING, FILL, POND = range(12)
# Puulajit (scripts/map.gd).
PINE, SPRUCE, BIRCH, ASPEN, BUSH = range(5)


def fetch(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    print("haetaan", url)
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=300) as r, open(path + ".part", "wb") as f:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            f.write(b)
    os.replace(path + ".part", path)
    return path


def ranged(url, a, b):
    req = urllib.request.Request(url, headers=dict(UA, Range="bytes=%d-%d" % (a, b - 1)))
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


# --- Koordinaatit ---------------------------------------------------------------------------------------------

def tm35(lat_deg, lon_deg):
    """GRS80 -> ETRS-TM35FIN (JHS 197)."""
    a, f, k0, lon0, e0 = 6378137.0, 1 / 298.257222101, 0.9996, math.radians(27.0), 500000
    n = f / (2 - f)
    a1 = a / (1 + n) * (1 + n * n / 4 + n ** 4 / 64)
    e = math.sqrt(f * (2 - f))
    h1 = n / 2 - 2 / 3 * n * n + 5 / 16 * n ** 3 + 41 / 180 * n ** 4
    h2 = 13 / 48 * n * n - 3 / 5 * n ** 3 + 557 / 1440 * n ** 4
    h3 = 61 / 240 * n ** 3 - 103 / 140 * n ** 4
    h4 = 49561 / 161280 * n ** 4
    phi, lam = math.radians(lat_deg), math.radians(lon_deg)
    q = math.asinh(math.tan(phi)) - e * math.atanh(e * math.sin(phi))
    beta = math.atan(math.sinh(q))
    eta0 = math.atanh(math.cos(beta) * math.sin(lam - lon0))
    xi0 = math.asin(math.sin(beta) * math.cosh(eta0))
    xi = xi0 + sum(hh * math.sin(2 * k * xi0) * math.cosh(2 * k * eta0) for k, hh in enumerate((h1, h2, h3, h4), 1))
    eta = eta0 + sum(hh * math.cos(2 * k * xi0) * math.sinh(2 * k * eta0) for k, hh in enumerate((h1, h2, h3, h4), 1))
    return e0 + a1 * eta * k0, a1 * xi * k0


def loc(e, n):
    """TM35 -> pelin (x, z)."""
    return e - E0, N0 - n


# --- Korkeusmalli ---------------------------------------------------------------------------------------------

class Dem:
    def __init__(self, cache):
        self.a = np.zeros((6000, 6000), np.float32)
        for sh, (r, c) in DEM_SHEETS.items():
            p = fetch(KAPSI + "korkeusmalli/hila_2m/etrs-tm35fin-n2000/%s/%s/%s.tif" % (sh[:2], sh[:3], sh),
                      os.path.join(cache, "dem", sh + ".tif"))
            self.a[r * 3000:(r + 1) * 3000, c * 3000:(c + 1) * 3000] = tifffile.imread(p)

    @staticmethod
    def ij(e, n):
        """Pikselin (sarake, rivi) liukulukuina: keskipisteet kokonaisluvuissa."""
        return (np.asarray(e) - DEM_E) / 2.0 - 0.5, (DEM_N - np.asarray(n)) / 2.0 - 0.5

    def at(self, e, n):
        i, j = self.ij(e, n)
        return ndimage.map_coordinates(self.a, [np.atleast_1d(j), np.atleast_1d(i)], order=1, mode="nearest")


# --- Maastotietokanta -----------------------------------------------------------------------------------------

def mtk_records(cache, layer):
    """Kaikki tason (esim. "m_p") kohteet molemmilta lehdiltä: (luokka, teksti, osat [[(e, n), ...]], tietue)."""
    out = []
    for sh, d in MTK_SHEETS.items():
        z = fetch(KAPSI + "maastotietokanta/kaikki/etrs89/shp/%s/%s.shp.zip" % (d, sh),
                  os.path.join(cache, "mtk", sh + ".zip"))
        base = os.path.join(cache, "mtk", sh)
        if not os.path.isdir(base):
            import zipfile
            zipfile.ZipFile(z).extractall(base)
        p = os.path.join(base, "%s_%s_%s.shp" % (layer[0], sh, layer[2]))
        if not os.path.exists(p):
            continue
        r = shapefile.Reader(p, encoding="utf-8")
        for sr in r.iterShapeRecords():
            s = sr.shape
            if not s.points:
                continue
            parts = (list(s.parts) or [0]) + [len(s.points)]
            rings = [s.points[parts[k]:parts[k + 1]] for k in range(len(parts) - 1)]
            rec = sr.record.as_dict()
            out.append((rec["LUOKKA"], (rec.get("TEKSTI") or "").strip(), rings, rec))
    return out


def in_poly(poly, x, y):
    """Parillisuussääntö: pisteet (x, y) monikulmion sisällä (numpy)."""
    inside = np.zeros(len(x), bool)
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        cross = ((yi > y) != (yj > y)) & (x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-12) + xi)
        inside ^= cross
        j = i
    return inside


def ring_area(r):
    a = 0.0
    for k in range(len(r) - 1):
        a += r[k][0] * r[k + 1][1] - r[k + 1][0] * r[k][1]
    return a / 2.0


# --- Rasterointi DEM-mosaiikin ruudukkoon ---------------------------------------------------------------------

def raster_polys(shape_rc, polys, value, out):
    """Monikulmiot (rengaslistat TM35:ssä, reiät mukana) arvolla value rasteriin out (DEM-mosaiikin ruudukko)."""
    from PIL import Image, ImageDraw
    img = Image.new("L", (shape_rc[1], shape_rc[0]), 0)
    d = ImageDraw.Draw(img)
    for rings in polys:
        # Shapefile: ulkorengas myötäpäivään (pinta-ala < 0), reiät vastapäivään.
        for r in rings:
            pts = [((e - DEM_E) / 2.0 - 0.5, (DEM_N - n) / 2.0 - 0.5) for e, n in r]
            if len(pts) >= 3:
                d.polygon(pts, fill=255 if ring_area(r) < 0 else 0)
    m = np.asarray(img) > 0
    out[m] = value
    return m


def raster_lines(shape_rc, lines, width_m, value, out):
    from PIL import Image, ImageDraw
    img = Image.new("L", (shape_rc[1], shape_rc[0]), 0)
    d = ImageDraw.Draw(img)
    w = max(1, int(round(width_m / 2.0)))
    for r in lines:
        pts = [((e - DEM_E) / 2.0 - 0.5, (DEM_N - n) / 2.0 - 0.5) for e, n in r]
        d.line(pts, fill=255, width=w)
    m = np.asarray(img) > 0
    out[m] = value
    return m


# --- VMI (16 m) -----------------------------------------------------------------------------------------------

def vmi_read(cache, theme, e0, n0, e1, n1):
    path = os.path.join(cache, "vmi", "%s_%d_%d_%d_%d.npy" % (theme, e0, n0, e1, n1))
    gpath = os.path.join(cache, "vmi", "geo_%d_%d_%d_%d.json" % (e0, n0, e1, n1))
    if os.path.exists(path) and os.path.exists(gpath):
        return np.load(path), json.load(open(gpath))
    url = FUNET + "luke/vmi/2023/%s_vmi1x_1923.tif" % theme
    h = ranged(url, 0, 131072)
    off = struct.unpack("<I", h[4:8])[0]
    tags = {}
    for k in range(struct.unpack("<H", h[off:off + 2])[0]):
        tag, typ, cnt = struct.unpack("<HHI", h[off + 2 + k * 12:off + 10 + k * 12])
        tags[tag] = (typ, cnt, h[off + 10 + k * 12:off + 14 + k * 12])

    def val(t):
        typ, cnt, v = tags[t]
        if typ == 3 and cnt == 1:
            return struct.unpack("<H", v[:2])[0]
        if typ == 4 and cnt == 1:
            return struct.unpack("<I", v)[0]
        o = struct.unpack("<I", v)[0]
        sz, fm = {3: (2, "H"), 4: (4, "I"), 12: (8, "d")}[typ]
        d = h[o:o + cnt * sz] if o + cnt * sz <= len(h) else ranged(url, o, o + cnt * sz)
        return struct.unpack("<%d%s" % (cnt, fm), d)

    W = val(256)
    tw, th = val(322), val(323)
    offs, cnts = val(324), val(325)
    ps = val(33550)[0]
    tp = val(33922)
    ox, oy = tp[3], tp[4]
    x0, x1 = int((e0 - ox) // ps), int((e1 - ox) // ps) + 1
    y0, y1 = int((oy - n1) // ps), int((oy - n0) // ps) + 1
    out = np.full((y1 - y0, x1 - x0), 32767, np.uint16)
    tx = (W + tw - 1) // tw
    for ty in range(y0 // th, (y1 - 1) // th + 1):
        for txi in range(x0 // tw, (x1 - 1) // tw + 1):
            k = ty * tx + txi
            t = np.frombuffer(imagecodecs.lzw_decode(ranged(url, offs[k], offs[k] + cnts[k])), "<u2")
            t = t[:tw * th].reshape(th, tw)
            gy0, gx0 = ty * th, txi * tw
            ya, yb = max(y0, gy0), min(y1, gy0 + th)
            xa, xb = max(x0, gx0), min(x1, gx0 + tw)
            out[ya - y0:yb - y0, xa - x0:xb - x0] = t[ya - gy0:yb - gy0, xa - gx0:xb - gx0]
    geo = [ox + x0 * ps, oy - y0 * ps, ps]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    np.save(path, out)
    json.dump(geo, open(gpath, "w"))
    return out, geo


# --- Pääohjelma -----------------------------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", required=True, help="lähdeaineiston välimuisti (n. 120 Mt)")
    ap.add_argument("--osm", default="", help="OSM-ote (oletus haetaan välimuistiin)")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(64432)

    se, sn = tm35(START_LAT, START_LON)
    print("aloituspiste TM35 %.2f %.2f -> paikallinen %.2f %.2f" % (se, sn, *loc(se, sn)))

    dem = Dem(a.cache)
    S = dem.a.shape

    # --- Pintaluokat 2 m mosaiikissa (prioriteetti: myöhempi peittää) ---
    cls = np.full(S, FOREST, np.uint8)
    polys = {}
    for luokka, _t, rings, _r in mtk_records(a.cache, "m_p") + mtk_records(a.cache, "n_p"):
        polys.setdefault(luokka, []).append(rings)
    order = [(39110, CLEARING), (32611, FIELD), (32612, YARD), (33000, FILL),
             (35300, BOG), (35411, BOG), (35412, BOG), (35421, BOG), (35422, BOG),
             (34300, SAND), (34100, ROCK), (34700, ROCK)]
    for luokka, c in order:
        if luokka in polys:
            raster_polys(S, polys[luokka], c, cls)
    lakes = polys.get(36200, []) + polys.get(36211, [])
    lake_rings = []
    water = np.zeros(S, bool)
    lake_id = np.zeros(S, np.int32)
    lake_levels = []
    for k, rings in enumerate(lakes):
        tmp = np.zeros(S, np.uint8)
        m = raster_polys(S, [rings], 1, tmp)
        if not m.any():
            continue
        lake_id[m] = len(lake_levels) + 1
        lake_levels.append(float(np.median(dem.a[m])))
        lake_rings.append(rings)
        water |= m
    # Oulujärven pinta: aloituspaikan ympäristön tasoitettu vedenpinta korkeusmallista.
    i0, j0 = Dem.ij(E0, N0)
    i0, j0 = int(round(i0)), int(round(j0))
    win = (slice(j0 - 1000, j0 + 1000), slice(i0 - 1000, i0 + 1000))
    big = lake_id[win][water[win]]
    main_id = int(np.bincount(big).argmax())
    level = float(np.median(dem.a[win][(lake_id[win] == main_id)]))
    print("Oulujärven pinta %.2f m (N2000), järviä %d" % (level, len(lake_levels)))

    # Tiet ja polut (MTK) rasteriin äänille ja pinnoille.
    roads = []
    for luokka, name, rings, rec in mtk_records(a.cache, "l_v"):
        kind = {12111: "highway", 12112: "highway", 12121: "main", 12122: "main", 12131: "road", 12132: "road",
                12141: "drive", 12151: "drive", 12312: "track", 12313: "path", 12314: "cycleway",
                12316: "track"}.get(luokka)
        if kind is None:
            continue
        roads.append((kind, name, rings[0], rec.get("PAALLY", 0)))
    width = {"highway": 7.5, "main": 6.5, "road": 5.0, "drive": 3.5, "track": 2.6, "path": 1.0, "cycleway": 2.5}
    for kind in ["track", "path", "cycleway", "drive", "road", "main", "highway"]:
        lines = [r[2] for r in roads if r[0] == kind]
        if lines:
            raster_lines(S, lines, width[kind], PATH if kind in ("path", "track") else ROAD, cls)
    cls[water] = WATER
    # MTK jakaa Oulujärven lehtien rajoilla osiin: samalla pinnalla olevat osat ovat pääjärveä.
    main_ids = [k + 1 for k, v in enumerate(lake_levels) if abs(v - level) < 0.15]
    cls[water & ~np.isin(lake_id, main_ids)] = POND

    # --- Laser: latvusmalli, puut ja rakennusten korkeudet ---
    bx0, by0, bx1, by1 = LAZ_BOX
    cw, ch = int(bx1 - bx0), int(by1 - by0)
    chm = np.zeros((ch, cw), np.float32)
    roof_pts = []  # (e, n, korkeus maasta) rakennusten korkeuksiin
    for t, d in LAZ.items():
        p = fetch(FUNET + "mml/laserkeilaus/2008_latest/2011/%s/1/%s.laz" % (d, t), os.path.join(a.cache, "laz", t + ".laz"))
        las = laspy.read(p)
        x, y, z = np.asarray(las.x), np.asarray(las.y), np.asarray(las.z)
        c = np.asarray(las.classification)
        keep = np.isin(c, (1, 3, 13))
        x, y, z = x[keep], y[keep], z[keep]
        hag = z - dem.at(x, y)
        keep = (hag > 0.4) & (hag < 40.0)
        x, y, hag = x[keep], y[keep], hag[keep]
        roof_pts.append(np.stack([x, y, hag], 1))
        ci = np.clip((x - bx0).astype(int), 0, cw - 1)
        cj = np.clip((by1 - y).astype(int), 0, ch - 1)
        np.maximum.at(chm, (cj, ci), hag.astype(np.float32))
        print("laser %s: %d kasvillisuus-/kattopistettä" % (t, len(x)))
    roof_pts = np.concatenate(roof_pts)

    # Rakennukset (MTK) ja niiden korkeus laserista.
    buildings = []
    bmask = np.zeros((ch, cw), np.uint8)
    from PIL import Image, ImageDraw
    bimg = Image.new("L", (cw, ch), 0)
    bdraw = ImageDraw.Draw(bimg)
    for luokka, _t, rings, rec in mtk_records(a.cache, "r_p"):
        r = rings[0]
        e = [p[0] for p in r]
        n = [p[1] for p in r]
        cx, cz = loc(sum(e) / len(e), sum(n) / len(n))
        if abs(cx) > FAR_HALF or abs(cz) > FAR_HALF:
            continue
        kind = {42211: "home", 42212: "home", 42221: "home", 42231: "cottage", 42232: "cottage",
                42241: "industry", 42251: "public", 42261: "shed", 42262: "shed", 42270: "shed"}.get(luokka, "shed")
        hgt = None
        if bx0 <= min(e) and max(e) <= bx1 and by0 <= min(n) and max(n) <= by1:
            sel = (roof_pts[:, 0] >= min(e)) & (roof_pts[:, 0] <= max(e)) & (roof_pts[:, 1] >= min(n)) & (roof_pts[:, 1] <= max(n))
            cand = roof_pts[sel]
            if len(cand):
                inside = in_poly(np.array(r), cand[:, 0], cand[:, 1])
                if inside.sum() >= 3:
                    hgt = float(np.percentile(cand[inside, 2], 95))
            bdraw.polygon([(pe - bx0, by1 - pn) for pe, pn in r], fill=255)
        # Laserin 95. persentiili harjan korkeudeksi; ylle kurottavat puut rajataan pois tyypin enimmäiskorkeudella.
        cap = {"home": 9.0, "cottage": 6.0, "shed": 4.5}.get(kind, 10.0)
        if hgt is None or hgt < 2.0:
            hgt = {"home": 6.0, "cottage": 4.5, "shed": 3.2}.get(kind, 5.0)
        hgt = min(hgt, cap)
        pts = [[round(loc(pe, pn)[0], 2), round(loc(pe, pn)[1], 2)] for pe, pn in r]
        if pts[0] == pts[-1]:
            pts.pop()
        buildings.append({"kind": kind, "h": round(hgt, 1), "pts": pts})
    # Puut eivät kasva rakennusten päällä eivätkä aivan seinän vieressä (latvus katolla): 3 m vara.
    bmask = ndimage.binary_dilation(np.asarray(bimg) > 0, iterations=3)
    print("rakennuksia %d" % len(buildings))

    # Pihat: asuin- ja lomarakennusten ympärillä matala latvus -> piha (nurmi).
    yard = np.zeros(S, bool)
    for b in buildings:
        if b["kind"] in ("home", "cottage"):
            xs = [p[0] for p in b["pts"]]
            zs = [p[1] for p in b["pts"]]
            cx, cz = sum(xs) / len(xs), sum(zs) / len(zs)
            ci, cj = Dem.ij(E0 + cx, N0 - cz)
            ci, cj = int(round(ci)), int(round(cj))
            if 10 <= ci < S[1] - 10 and 10 <= cj < S[0] - 10:
                yy, xx = np.ogrid[-9:10, -9:10]
                yard[cj - 9:cj + 10, ci - 9:ci + 10] |= (xx * xx + yy * yy) <= 81
    # Latvusmalli 2 m:n ruutuun DEM-mosaiikissa pihojen rajaamiseksi.
    chm2 = chm.reshape(ch // 2, 2, cw // 2, 2).max(axis=(1, 3))
    li, lj = Dem.ij(bx0 + 1, by1 - 1)
    li, lj = int(round(li)), int(round(lj))
    canopy = np.zeros(S, np.float32)
    canopy[lj:lj + ch // 2, li:li + cw // 2] = chm2
    yard &= (canopy < 2.0) & (cls == FOREST)
    cls[yard] = YARD

    # Puut: latvusmallin paikalliset maksimit.
    filled = ndimage.grey_closing(chm, size=3)
    smooth = ndimage.gaussian_filter(filled, 0.8)
    mx3 = ndimage.maximum_filter(smooth, size=3)
    mx5 = ndimage.maximum_filter(smooth, size=5)
    peak = ((smooth >= mx3) & (smooth < 9.0) & (smooth >= 1.3)) | ((smooth >= mx5) & (smooth >= 9.0))
    peak &= ~bmask
    pj, pi = np.nonzero(peak)
    te = bx0 + pi + 0.5 + rng.uniform(-0.3, 0.3, len(pi))
    tn = by1 - pj - 0.5 + rng.uniform(-0.3, 0.3, len(pi))
    th = filled[pj, pi]
    # Ei vedessä eikä teillä.
    wi, wj = Dem.ij(te, tn)
    wi = np.clip(np.round(wi).astype(int), 0, S[1] - 1)
    wj = np.clip(np.round(wj).astype(int), 0, S[0] - 1)
    ok = ~np.isin(cls[wj, wi], (WATER, POND, ROAD))
    te, tn, th = te[ok], tn[ok], th[ok]
    print("laserpuita %d" % len(te))
    # 2011 keilauksen tiheys (n. 0,5 p/m²) erottaa vain valtapuut: täydennetään latvuston aukot puilla vain
    # sinne, missä laser näki latvustoa (pituus latvusmallista), niin että latvukset juuri ja juuri koskettavat.
    from scipy.spatial import cKDTree
    have = [np.stack([te, tn], 1)]
    add_e, add_n, add_h = [], [], []
    for _pass in range(4):
        step = 2.6
        ce, cn = np.meshgrid(np.arange(bx0 + step / 2, bx1, step), np.arange(by0 + step / 2, by1, step))
        ce = (ce + rng.uniform(-1.2, 1.2, ce.shape)).ravel()
        cn = (cn + rng.uniform(-1.2, 1.2, cn.shape)).ravel()
        ci = np.clip((ce - bx0).astype(int), 0, cw - 1)
        cj = np.clip((by1 - cn).astype(int), 0, ch - 1)
        hh = smooth[cj, ci]
        # Täydennyspuita ei pihoille (latvusmallin pihapuut ovat jo valtapuina mukana).
        yi, yj = Dem.ij(ce, cn)
        in_yard = cls[np.clip(np.round(yj).astype(int), 0, S[0] - 1), np.clip(np.round(yi).astype(int), 0, S[1] - 1)] == YARD
        sel = (hh >= 2.0) & ~bmask[cj, ci] & ~in_yard
        ce, cn, hh = ce[sel], cn[sel], hh[sel]
        d, _ = cKDTree(np.concatenate(have)).query(np.stack([ce, cn], 1))
        sel = (d > 1.25 * (0.5 + 0.09 * hh)) & (rng.random(len(ce)) < 0.55)
        ce, cn, hh = ce[sel], cn[sel], hh[sel]
        have.append(np.stack([ce, cn], 1))
        add_e.append(ce)
        add_n.append(cn)
        add_h.append(hh * rng.uniform(0.65, 1.0, len(hh)))
    ae_, an_, ah_ = np.concatenate(add_e), np.concatenate(add_n), np.concatenate(add_h)
    wi, wj = Dem.ij(ae_, an_)
    ok = ~np.isin(cls[np.clip(np.round(wj).astype(int), 0, S[0] - 1), np.clip(np.round(wi).astype(int), 0, S[1] - 1)],
                  (WATER, POND, ROAD))
    te = np.concatenate([te, ae_[ok]])
    tn = np.concatenate([tn, an_[ok]])
    th = np.concatenate([th, ah_[ok]])
    print("latvuston täydennys %d puuta" % ok.sum())

    # Puulajit VMI:n tilavuusosuuksista (16 m).
    ve0, vn0 = E0 - FAR_HALF - 32, N0 - FAR_HALF - 32
    ve1, vn1 = E0 + FAR_HALF + 32, N0 + FAR_HALF + 32
    vmi = {}
    for t in VMI_THEMES:
        vmi[t], geo = vmi_read(a.cache, t, ve0, vn0, ve1, vn1)
    gx0, gy0, gps = geo

    def vmi_cell(e, n):
        i = np.clip(((np.asarray(e) - gx0) // gps).astype(int), 0, vmi["manty"].shape[1] - 1)
        j = np.clip(((gy0 - np.asarray(n)) // gps).astype(int), 0, vmi["manty"].shape[0] - 1)
        return j, i

    def species(e, n, hgt):
        j, i = vmi_cell(e, n)
        vols = np.stack([vmi[t][j, i].astype(np.float32) for t in ("manty", "kuusi", "koivu", "muulp")], 1)
        vols[vols >= 32766] = 0.0
        tot = vols.sum(1)
        default = np.array([0.35, 0.2, 0.35, 0.1], np.float32)  # pihat, rannat, metsämaan ulkopuoli
        prob = np.where(tot[:, None] > 1.0, vols / np.maximum(tot, 1e-6)[:, None], default)
        # Taimikot ja pensaikot: matalissa enemmän lehtipuuta.
        young = hgt < 5.0
        prob[young] = prob[young] * 0.6 + np.array([0.15, 0.1, 0.5, 0.25]) * 0.4
        prob /= prob.sum(1, keepdims=True)
        u = rng.random(len(e))[:, None]
        sp = (u > np.cumsum(prob, 1)).sum(1).astype(np.uint8)
        sp = np.minimum(sp, 3)
        sp[hgt < 2.2] = BUSH
        return sp

    tsp = species(te, tn, th)

    # Laserin ulkopuolelle VMI-metsä: latvuspeiton mukaan puita 16 m soluihin, pituus keskipituudesta.
    fe, fn, fh = [], [], []
    cover = vmi["latvuspeitto"]
    hmean = vmi["keskipituus"]
    for j in range(cover.shape[0]):
        for i in range(cover.shape[1]):
            cv = cover[j, i]
            if cv >= 32766 or cv == 0:
                continue
            ce, cn = gx0 + (i + 0.5) * gps, gy0 - (j + 0.5) * gps
            if bx0 <= ce <= bx1 and by0 <= cn <= by1:
                continue
            if abs(ce - E0) > FAR_HALF or abs(cn - N0) > FAR_HALF:
                continue
            cnt = rng.poisson(cv / 100.0 * 5.0)
            hm = hmean[j, i] / 10.0 if hmean[j, i] < 32766 else 12.0
            for _ in range(cnt):
                e = ce + rng.uniform(-8, 8)
                n = cn + rng.uniform(-8, 8)
                fe.append(e)
                fn.append(n)
                fh.append(max(2.5, hm * rng.uniform(0.75, 1.2)))
    fe, fn, fh = np.array(fe), np.array(fn), np.array(fh)
    if len(fe):
        wi, wj = Dem.ij(fe, fn)
        ok = ~np.isin(cls[np.clip(np.round(wj).astype(int), 0, S[0] - 1), np.clip(np.round(wi).astype(int), 0, S[1] - 1)], (WATER, POND, ROAD, FIELD))
        fe, fn, fh = fe[ok], fn[ok], fh[ok]
    fsp = species(fe, fn, fh) if len(fe) else np.zeros(0, np.uint8)
    print("VMI-puita laserin ulkopuolella %d" % len(fe))

    # Kaikki puut: x, z (float32), pituus (0,1 m), latvuksen säde (0,05 m), laji.
    ae = np.concatenate([te, fe])
    an = np.concatenate([tn, fn])
    ah = np.concatenate([th, fh])
    asp = np.concatenate([tsp, fsp])
    ax, az = ae - E0, N0 - an
    # Aloituspaikalla ei puuta pelaajan päällä (6 m säde).
    sx0, sz0 = loc(se, sn)
    inside = (np.abs(ax) < FAR_HALF) & (np.abs(az) < FAR_HALF) & (np.hypot(ax - sx0, az - sz0) > 6.0)
    ax, az, ah, asp = ax[inside], az[inside], ah[inside], asp[inside]
    crown = np.where(asp == SPRUCE, 0.35 + 0.085 * ah, np.where(asp == PINE, 0.5 + 0.1 * ah, 0.6 + 0.12 * ah))
    crown = np.clip(crown, 0.4, 5.0)
    # Maanpinnan korkeus puun kohdalla: kolmiointi kuten pelin maastossa (terrain.gd, lävistäjä (1,0)-(0,1)).
    ti, tj = Dem.ij(E0 + ax, N0 - az)
    i0 = np.clip(np.floor(ti).astype(int), 0, S[1] - 2)
    j0 = np.clip(np.floor(tj).astype(int), 0, S[0] - 2)
    u, v = ti - i0, tj - j0
    A = dem.a
    h00, h10, h01, h11 = A[j0, i0], A[j0, i0 + 1], A[j0 + 1, i0], A[j0 + 1, i0 + 1]
    ay = np.where(u + v <= 1.0, h00 + (h10 - h00) * u + (h01 - h00) * v,
                  h11 + (h01 - h11) * (1 - u) + (h10 - h11) * (1 - v)) - level
    # Järjestys: kaukolohko (512 m), laji, lähilohko (128 m): kumpikin lohko ja laji on yhtenäinen väli.
    FC, NC = 512.0, 128.0
    nf, nn = int(FAR_HALF * 2 / FC), int(FAR_HALF * 2 / NC)
    fi = np.clip(((ax + FAR_HALF) // FC).astype(int), 0, nf - 1)
    fj = np.clip(((az + FAR_HALF) // FC).astype(int), 0, nf - 1)
    ni = np.clip(((ax + FAR_HALF) // NC).astype(int), 0, nn - 1)
    nj = np.clip(((az + FAR_HALF) // NC).astype(int), 0, nn - 1)
    order_ = np.lexsort((nj * nn + ni, asp, fj * nf + fi))
    ax, ay, az, ah, asp, crown = ax[order_], ay[order_], az[order_], ah[order_], asp[order_], crown[order_]
    fkey = (fj * nf + fi)[order_]
    nkey = (nj * nn + ni)[order_]
    far_tab = np.zeros((nf * nf, 5, 2), np.uint32)
    near_tab = np.zeros((nn * nn, 5, 2), np.uint32)
    for tab, key in ((far_tab, fkey), (near_tab, nkey)):
        comb = key.astype(np.int64) * 5 + asp
        change = np.r_[True, comb[1:] != comb[:-1]]
        starts = np.nonzero(change)[0]
        counts = np.diff(np.r_[starts, len(comb)])
        k = comb[starts]
        tab[k // 5, k % 5, 0] = starts
        tab[k // 5, k % 5, 1] = counts
    W = 2048
    Hh = (len(ax) + W - 1) // W
    t0 = np.zeros((Hh * W, 4), "<f4")
    t0[:len(ax)] = np.stack([ax, ay, az, ah], 1)
    t1 = np.zeros((Hh * W, 4), np.uint8)
    t1[:len(ax), 0] = np.clip(np.round(crown * 40), 1, 255)
    t1[:len(ax), 1] = asp
    t1[:len(ax), 2] = rng.integers(0, 256, len(ax))
    t1[:len(ax), 3] = rng.integers(0, 256, len(ax))
    with open(os.path.join(OUT, "puut.bin"), "wb") as f:
        f.write(b"ONP2" + struct.pack("<IIIffII", len(ax), W, Hh, FC, NC, nf, nn) + struct.pack("<f", FAR_HALF))
        f.write(far_tab.tobytes())
        f.write(near_tab.tobytes())
        f.write(t0.tobytes())
        f.write(t1.tobytes())
    print("puut.bin: %d puuta (%s)" % (len(ax), ", ".join("%s %d" % (n, (asp == k).sum())
          for k, n in enumerate(["mänty", "kuusi", "koivu", "haapa/muu", "pensas"]))))

    # --- Järven pohja: syvyys etäisyydestä rantaan, matalikot ja vesikivet ---
    ground = dem.a.copy()
    dist = ndimage.distance_transform_edt(water) * 2.0
    noise = ndimage.gaussian_filter(rng.standard_normal(S).astype(np.float32), 12) * 30.0
    depth = np.minimum(0.15 + dist * 0.03 + np.maximum(dist - 120, 0) * 0.02, 9.0) * np.clip(1.0 + 0.35 * noise, 0.6, 1.4)
    shallow = np.zeros(S, np.uint8)
    if 38700 in polys:
        raster_polys(S, polys[38700], 1, shallow)
    depth = np.where(shallow > 0, np.minimum(depth, 0.5 + 0.4 * np.abs(noise)), depth)
    rocks_water = []
    for luokka, name, rings, _r in mtk_records(a.cache, "n_s"):
        if luokka == 38511:
            e, n = rings[0][0]
            x, z = loc(e, n)
            if abs(x) < FAR_HALF and abs(z) < FAR_HALF:
                rocks_water.append([round(x, 1), round(z, 1)])
                ci, cj = Dem.ij(e, n)
                ci, cj = int(round(ci)), int(round(cj))
                yy, xx = np.ogrid[-3:4, -3:4]
                k = np.exp(-(xx * xx + yy * yy) / 3.0)
                sl = (slice(cj - 3, cj + 4), slice(ci - 3, ci + 4))
                depth[sl] = depth[sl] * (1 - k) + 0.25 * k
    lake_level_map = np.where(lake_id > 0, np.array([0.0] + lake_levels, np.float32)[lake_id], 0.0)
    ground = np.where(water, lake_level_map - np.maximum(depth, 0.1), ground)

    # --- Ruudukot peliin ---
    def node_grid(half, step):
        n = half * 2 // step + 1
        xs = np.arange(n) * step - half
        e = E0 + xs
        nn = N0 - xs  # z kasvaa etelään
        I, J = Dem.ij(e[None, :], nn[:, None])
        return n, I + 0 * J, J + 0 * I

    def write_grid(f, half, step, avg):
        n, I, J = node_grid(half, step)
        if avg:
            sm = ndimage.uniform_filter(ground, size=step // 2)
            hv = ndimage.map_coordinates(sm, [J, I], order=1, mode="nearest")
        else:
            hv = ndimage.map_coordinates(ground, [J, I], order=1, mode="nearest")
        rel = (hv - level).astype("<f4")
        # Solun pintaluokka keskipisteestä.
        ci = (I[:-1, :-1] + I[1:, 1:]) / 2
        cj = (J[:-1, :-1] + J[1:, 1:]) / 2
        cc = cls[np.clip(np.round(cj).astype(int), 0, S[0] - 1), np.clip(np.round(ci).astype(int), 0, S[1] - 1)]
        f.write(struct.pack("<Iff", n, float(step), float(half)))
        f.write(rel.tobytes())
        f.write(cc.astype(np.uint8).tobytes())
        return hv, cc

    with open(os.path.join(OUT, "maasto.bin"), "wb") as f:
        f.write(b"ONM2")
        hv, cc = write_grid(f, NEAR_HALF, NEAR_STEP, False)
        write_grid(f, FAR_HALF, FAR_STEP, True)
    print("maasto.bin: lähiruudukko %d^2 (%.1f..%.1f m järven pinnasta), kaukoruudukko %d^2"
          % (NEAR_HALF * 2 // NEAR_STEP + 1, hv.min() - level, hv.max() - level, FAR_HALF * 2 // FAR_STEP + 1))

    # --- Vektorikohteet ---
    def pt(e, n):
        x, z = loc(e, n)
        return [round(x, 2), round(z, 2)]

    def within(e, n, half=FAR_HALF):
        x, z = loc(e, n)
        return abs(x) <= half and abs(z) <= half

    def simplify(r, eps=0.8):
        r = np.asarray(r)
        if len(r) < 5:
            return r
        keep = np.zeros(len(r), bool)
        m = int(np.hypot(*(r - r[0]).T).argmax())  # suljettu rengas: jaetaan kauimmasta pisteestä
        keep[0] = keep[-1] = keep[m] = True
        stack = [(0, m), (m, len(r) - 1)]
        while stack:
            i, j = stack.pop()
            a_, b_ = r[i], r[j]
            ab = b_ - a_
            L = np.hypot(*ab) or 1e-9
            seg = r[i + 1:j]
            if not len(seg):
                continue
            d = np.abs(ab[0] * (seg[:, 1] - a_[1]) - ab[1] * (seg[:, 0] - a_[0])) / L
            k = int(d.argmax())
            if d[k] > eps:
                keep[i + 1 + k] = True
                stack += [(i, i + 1 + k), (i + 1 + k, j)]
        return r[keep]

    ponds = []
    for k, rings in enumerate(lake_rings):
        if k + 1 in main_ids:
            continue
        outer = [r for r in rings if ring_area(r) < 0]
        if not outer or not any(within(e, n) for e, n in outer[0]):
            continue
        rr = simplify(outer[0])
        ponds.append({"level": round(lake_levels[k] - level, 2),
                      "pts": [pt(e, n) for e, n in rr[:-1]]})
    feats = {"ponds": ponds, "roads": [], "stones": [], "water_rocks": rocks_water, "shallows": [], "names": [], "tar_pits": [],
             "beacons": [], "slipways": [], "barriers": [], "buildings": buildings}
    for kind, name, line, pav in roads:
        if not any(within(e, n) for e, n in line):
            continue
        feats["roads"].append({"kind": kind, "name": name, "paved": pav == 2, "pts": [pt(e, n) for e, n in line]})
    for luokka, name, rings, _r in mtk_records(a.cache, "m_s"):
        e, n = rings[0][0]
        if luokka == 34600 and within(e, n):
            feats["stones"].append(pt(e, n))
    for luokka, name, rings, _r in mtk_records(a.cache, "r_s"):
        e, n = rings[0][0]
        if luokka == 45400 and within(e, n):
            feats["tar_pits"].append(pt(e, n))
    for luokka, name, rings, _r in mtk_records(a.cache, "l_s"):
        e, n = rings[0][0]
        if not within(e, n):
            continue
        if luokka == 16120:
            feats["beacons"].append(pt(e, n))
        elif luokka == 12200:
            feats["barriers"].append(pt(e, n))
    for rings in polys.get(38700, []):
        r = rings[0]
        if any(within(e, n) for e, n in r):
            feats["shallows"].append([pt(e, n) for e, n in r[:-1]])
    for layer in ("m_t", "n_t", "l_t"):
        for luokka, name, rings, _r in mtk_records(a.cache, layer):
            e, n = rings[0][0]
            if name and within(e, n) and luokka not in (36291, 42102, 45402, 52192, 52193) and not name[0].isdigit() \
                    and not name.startswith("("):
                feats["names"].append({"name": name, "class": luokka, "p": pt(e, n)})

    # OSM: veneenlaskupaikat ja tiennimet (MTK:ssa nimettömille).
    osm_path = a.osm or os.path.join(a.cache, "area.osm")
    if not a.osm:
        fetch("https://api.openstreetmap.org/api/0.6/map?bbox=26.855,64.420,26.918,64.445", osm_path)
    import xml.etree.ElementTree as ET
    root = ET.parse(osm_path).getroot()
    nodes = {nd.get("id"): (float(nd.get("lat")), float(nd.get("lon"))) for nd in root.iter("node")}
    for nd in root.iter("node"):
        tags = {t.get("k"): t.get("v") for t in nd.iter("tag")}
        if tags.get("leisure") == "slipway":
            e, n = tm35(*nodes[nd.get("id")])
            if within(e, n):
                feats["slipways"].append(pt(e, n))
    for w in root.iter("way"):
        tags = {t.get("k"): t.get("v") for t in w.iter("tag")}
        if tags.get("leisure") == "slipway":
            ids = [r.get("ref") for r in w.iter("nd")]
            e, n = tm35(*nodes[ids[len(ids) // 2]])
            if within(e, n):
                feats["slipways"].append(pt(e, n))

    sx, sz = loc(se, sn)
    meta = {
        "start": {"lat": START_LAT, "lon": START_LON, "x": round(sx, 2), "z": round(sz, 2)},
        "origin_tm35": [E0, N0],
        "water_level_n2000": round(level, 3),
        "lakes": [round(v - level, 3) for v in lake_levels],
        "near": {"half": NEAR_HALF, "step": NEAR_STEP},
        "far": {"half": FAR_HALF, "step": FAR_STEP},
        "laser_box": [bx0 - E0, N0 - by1, bx1 - E0, N0 - by0],
        "sources": [
            "Korkeusmalli 2 m, maastotietokanta ja laserkeilausaineisto 2011 © Maanmittauslaitos (CC BY 4.0)",
            "Monilähteisen valtakunnan metsien inventoinnin (MVMI) kartta-aineisto 2023 © Luonnonvarakeskus (CC BY 4.0)",
            "© OpenStreetMap-tekijät (ODbL)",
        ],
    }
    feats["meta"] = meta
    with open(os.path.join(OUT, "kohteet.json"), "w", encoding="utf-8") as f:
        json.dump(feats, f, ensure_ascii=False, separators=(",", ":"))
    print("kohteet.json: " + ", ".join("%s %d" % (k, len(v)) for k, v in feats.items() if isinstance(v, list)))

    # Karttakuvat (minikartta ja M-kartta): suunnistuskartan tapaan pinnat, rinnevarjostus, 2,5 m käyrät,
    # tiet ja rakennukset. Lähialue 1 m/px (2000 x 2000), koko alue 8 m/px (1280 x 1280). Pohjoinen ylös.
    from PIL import Image, ImageDraw
    pal = np.array([[206, 222, 186], [120, 170, 215], [238, 224, 180], [190, 186, 178], [175, 200, 205],
                    [246, 214, 120], [226, 236, 190], [140, 120, 100], [140, 120, 100], [222, 232, 170],
                    [220, 210, 190], [120, 170, 215]], np.float32)

    def map_image(half, mpp):
        n = int(half * 2 / mpp)
        xs = (np.arange(n) + 0.5) * mpp - half
        I, J = Dem.ij(E0 + xs[None, :], N0 - xs[:, None])
        I = I + 0 * J
        J = J + 0 * I
        gsrc = ndimage.uniform_filter(ground, size=max(1, int(mpp / 2))) if mpp > 2 else ground
        hv = ndimage.map_coordinates(gsrc, [J, I], order=1, mode="nearest")
        cc = cls[np.clip(np.round(J).astype(int), 0, S[0] - 1), np.clip(np.round(I).astype(int), 0, S[1] - 1)]
        rgb = pal[cc].copy()
        gy, gx = np.gradient(hv, mpp)
        shade = np.clip(1.0 + (-gx * 0.7 + gy * 0.7) * 0.9, 0.7, 1.15)
        wet = np.isin(cc, (WATER, POND))
        rgb[~wet] *= shade[~wet, None]
        # Vesi tummuu syvemmälle.
        dep = np.clip(-hv, 0, 10) / 10.0
        rgb[wet] = rgb[wet] * (1 - 0.35 * dep[wet, None])
        # Käyrät (2,5 m, joka neljäs paksumpi) maalla.
        step_c = 2.5 if mpp <= 2 else 5.0
        lv = np.floor((hv + level) / step_c)
        edge = ((lv != np.roll(lv, 1, 0)) | (lv != np.roll(lv, 1, 1))) & ~wet
        rgb[edge] = rgb[edge] * 0.35 + np.array([170, 100, 40]) * 0.65
        img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))
        d = ImageDraw.Draw(img)

        def P(x, z):
            return ((x + half) / mpp, (z + half) / mpp)
        for r in feats["roads"]:
            w = {"highway": 7, "main": 6, "road": 5, "drive": 4, "track": 2.5, "path": 1.2, "cycleway": 2}[r["kind"]]
            col = (60, 60, 60) if r["kind"] in ("path", "track") else (110, 70, 40)
            px = [P(*q) for q in r["pts"]]
            if r["kind"] in ("path", "track"):
                d.line(px, fill=col, width=max(1, int(round(w / mpp))))
            else:
                d.line(px, fill=(60, 40, 30), width=max(2, int(round((w + 1.5) / mpp))))
                d.line(px, fill=(250, 200, 120), width=max(1, int(round(w / mpp))))
        for b in buildings:
            d.polygon([P(*q) for q in b["pts"]], fill=(40, 40, 40))
        return img

    map_image(NEAR_HALF, 1.0).save(os.path.join(OUT, "kartta_lahi.png"))
    map_image(FAR_HALF, 8.0).save(os.path.join(OUT, "kartta_koko.png"))
    print("karttakuvat kirjoitettu")


if __name__ == "__main__":
    main()
