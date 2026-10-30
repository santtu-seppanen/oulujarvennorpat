"""Muuntaa assets/map/puut.bin:n ONP2 -> ONP3 ilman laserdataa (bake.py tekee ONP3:n suoraan samoilla säännöillä).

  python3 tools/kartta/puut_v3.py

- Harvennus leivotaan dataan: joka toinen puu jää (ennen trees.gd:n THIN = 2, jolloin toinen puoli piirrettiin turhaan
  maan alle painettuna).
- Järjestys: kaukolohko (512 m), laji, keskilohko (128 m), lähilohko (32 m, 4 x 4 keskilohkon sisällä): jokainen
  kolmesta lohkotasosta ja laji on yhtenäinen väli.
- ONP3 = ONP2 + lähilohkojen puumäärät (uint16) kaikille keskilohko x laji x 16 -yhdistelmille.
"""
import os
import struct
import sys

import numpy as np

SUB = 32.0
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "map", "puut.bin")


def main() -> None:
    raw = open(OUT, "rb").read()
    if raw[:4] != b"ONP2":
        sys.exit("puut.bin ei ole ONP2 (jo muunnettu?)")
    count, w, h = struct.unpack_from("<III", raw, 4)
    fc, nc, nf, nn = struct.unpack_from("<ffII", raw, 16)
    half = struct.unpack_from("<f", raw, 32)[0]
    pos = 36 + nf * nf * 40 + nn * nn * 40
    a = np.frombuffer(raw, "<f4", w * h * 4, pos).reshape(-1, 4)[:count]
    pos += w * h * 16
    b = np.frombuffer(raw, np.uint8, w * h * 4, pos).reshape(-1, 4)[:count]
    keep = np.arange(count) % 2 == 0
    a, b = a[keep], b[keep]
    sp = b[:, 1].astype(int)
    si = np.clip(((a[:, 0] + half) // SUB).astype(int), 0, nn * 4 - 1)
    sj = np.clip(((a[:, 2] + half) // SUB).astype(int), 0, nn * 4 - 1)
    ni, nj = si // 4, sj // 4
    fi, fj = ni // 4, nj // 4
    sub = (sj % 4) * 4 + (si % 4)
    order = np.lexsort((sub, nj * nn + ni, sp, fj * nf + fi))
    a, b, sp = a[order], b[order], sp[order]
    fkey = (fj * nf + fi)[order]
    nkey = (nj * nn + ni)[order]
    sub = sub[order]
    far_tab = np.zeros((nf * nf, 5, 2), np.uint32)
    near_tab = np.zeros((nn * nn, 5, 2), np.uint32)
    for tab, key in ((far_tab, fkey), (near_tab, nkey)):
        comb = key.astype(np.int64) * 5 + sp
        starts = np.nonzero(np.r_[True, comb[1:] != comb[:-1]])[0]
        counts = np.diff(np.r_[starts, len(comb)])
        k = comb[starts]
        tab[k // 5, k % 5, 0] = starts
        tab[k // 5, k % 5, 1] = counts
    sub_tab = np.zeros((nn * nn, 5, 16), "<u2")
    np.add.at(sub_tab, (nkey, sp, sub), 1)
    n = len(a)
    nh = (n + w - 1) // w
    t0 = np.zeros((nh * w, 4), "<f4")
    t0[:n] = a
    t1 = np.zeros((nh * w, 4), np.uint8)
    t1[:n] = b
    with open(OUT, "wb") as f:
        f.write(b"ONP3" + struct.pack("<IIIffII", n, w, nh, fc, nc, nf, nn) + struct.pack("<f", half))
        f.write(far_tab.tobytes())
        f.write(near_tab.tobytes())
        f.write(sub_tab.tobytes())
        f.write(t0.tobytes())
        f.write(t1.tobytes())
    print("puut.bin ONP3: %d puuta (oli %d), %d x %d" % (n, count, w, nh))


main()
