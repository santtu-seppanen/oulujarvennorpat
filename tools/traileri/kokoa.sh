#!/bin/sh
# Liittää kappaleen trailerivideoon: tools/traileri/kokoa.sh <video.avi> <kappale.mp3> <ulos.mp4>
# Video venytetään kappaleen pituuteen vain, jos --kesto on annettu renderöinnissä; muuten ffmpeg päättää lyhyemmän mukaan.
set -e
V="$1"; A="$2"; O="${3:-traileri.mp4}"
ffmpeg -y -i "$V" -i "$A" -map 0:v -map 1:a -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -c:a aac -b:a 256k \
  -af "afade=t=in:d=0.3,afade=t=out:st=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$A" | awk '{printf "%.2f", $1-2}'):d=2" \
  -shortest "$O"
echo "valmis: $O"
