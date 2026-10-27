#!/usr/bin/env python3
"""Nauhoittaa pelin käsikirjoitetut repliikit macOS:n `say`-komennolla (assets/puhe/<ääni>_<tiiviste>.ogg).

Käyttö (pelin juuresta):  python3 tools/puhe/nauhoita.py [--kaikki]
- hakee repliikit pelistä (godot --headless -s tools/puhe/lauseet.gd, lähde scripts/puhe_lauseet.gd),
- nauhoittaa vain puuttuvat (--kaikki nauhoittaa kaikki uudelleen),
- muokkaa äänen ffmpegillä (korkeus, tempo, nalkutus) ja pakkaa ogg-muotoon.
Tiedoston nimi: ääni + tekstin MD5:n 10 ensimmäistä merkkiä (sama laskenta kuin scripts/puhe.gd key()).
Vaatii: macOS (say), ffmpeg, oggenc (brew install vorbis-tools) ja godot PATHissa. Päivitä lopuksi tuonti: godot --headless --path . --import
"""
import hashlib
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "puhe")
FI = "(Finnish (Finland))"

# ääni -> [say-ääni, sanat/min, äänenkorkeus (1 = sellaisenaan), tempo, nalkutus (vibrato-syvyys)]
VOICES = {
    "santtu": ["Eddy " + FI, 185, 1.08, 1.0, 0.0],
    "marko": ["Rocko " + FI, 170, 0.86, 1.0, 0.0],
    "jaakko": ["Reed " + FI, 195, 1.0, 1.0, 0.0],
    "jukka": ["Grandpa " + FI, 175, 0.92, 1.0, 0.0],
    # Nalkuttava mies: nasaali ja kireä (korkeampi), nopea purkaus, hieman värinää.
    "esimies": ["Reed " + FI, 225, 1.1, 1.1, 0.18],
    # Nalkuttava nainen: korkea, terävä ja nopea, enemmän värinää ja loppuun nouseva sävy.
    "vaimo": ["Shelley " + FI, 215, 1.12, 1.12, 0.28],
}


def key(voice, text):
    return "%s_%s" % (voice, hashlib.md5(text.strip().encode("utf-8")).hexdigest()[:10])


def phrases():
    out = subprocess.run(["godot", "--headless", "--path", ROOT, "-s", "tools/puhe/lauseet.gd"],
                         capture_output=True, text=True, cwd=ROOT).stdout
    res = []
    for line in out.splitlines():
        if line.startswith("LAUSE\t"):
            _, voice, text = line.split("\t", 2)
            res.append((voice, text))
    return res


def record(voice, text, path):
    v, wpm, pitch, tempo, nag = VOICES[voice]
    spoken = re.sub(r"[*♥]", "", text).replace("…", "...")
    with tempfile.TemporaryDirectory() as d:
        aiff = os.path.join(d, "a.aiff")
        subprocess.run(["say", "-v", v, "-r", str(wpm), "-o", aiff, spoken], check=True)
        # Korkeus asetrate-suodattimella (nopeus korjataan atempolla), nalkutus vibratolla ja puristuksella.
        sr = 22050
        flt = ["aresample=%d" % sr, "asetrate=%d" % round(sr * pitch), "aresample=%d" % sr, "atempo=%.4f" % (tempo / pitch)]
        if nag > 0:
            flt.append("vibrato=f=6.5:d=%.2f" % nag)
            flt.append("acompressor=threshold=0.05:ratio=6:attack=5:release=80")
        flt.append("silenceremove=start_periods=1:start_threshold=-50dB")
        flt.append("loudnorm=I=-18:TP=-2")
        wav = os.path.join(d, "b.wav")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", aiff, "-ar", str(sr), "-ac", "1", "-af", ",".join(flt), wav], check=True)
        subprocess.run(["oggenc", "-Q", "-q", "-0.5", "-o", path, wav], check=True)  # ffmpegissä ei ole libvorbista


def main():
    force = "--kaikki" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    todo = []
    for voice, text in phrases():
        path = os.path.join(OUT, key(voice, text) + ".ogg")
        if force or not os.path.exists(path):
            todo.append((voice, text, path))
    print("Nauhoitetaan %d riviä" % len(todo))
    for n, (voice, text, path) in enumerate(todo, 1):
        record(voice, text, path)
        if n % 50 == 0:
            print("  %d/%d" % (n, len(todo)))
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
    print("Valmis: %d tiedostoa, %.1f Mt" % (len(os.listdir(OUT)), total / 1e6))


if __name__ == "__main__":
    main()
