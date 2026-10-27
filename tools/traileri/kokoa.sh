#!/bin/sh
# Liittää kappaleen trailerivideoon: tools/traileri/kokoa.sh <video.avi> <kappale.mp3> <ulos.mp4>
# Videon alusta leikataan 1,5 s (traileri.gd antaa maailman rakentua 45 ruutua ennen kuvausta), joten kuva ja musiikki ovat samassa tahdissa.
# CRF 25 pitää 190 s 720p-videon alle GitHubin 100 Mt:n tiedostorajan.
set -e
V="$1"; A="$2"; O="${3:-traileri.mp4}"
ffmpeg -y -ss 1.5 -i "$V" -i "$A" -map 0:v -map 1:a -c:v libx264 -preset slow -crf 25 -pix_fmt yuv420p -c:a aac -b:a 192k \
  -af "afade=t=in:d=0.3,afade=t=out:st=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$A" | awk '{printf "%.2f", $1-2}'):d=2" \
  -shortest "$O"
echo "valmis: $O"
