#!/usr/bin/env bash
# make_custom_sound.sh <src_url_or_file> <out.mp3> [start_sec=0] [dur=29] [bitrate=128k]
# Produce a Pushover-compliant custom sound: LOUD (loudnorm I=-10, peak -1dB), <=30s, <500KB MP3.
# Prints a JSON report; exits non-zero if the result would exceed Pushover's 500KB limit.
set -euo pipefail
src="${1:?usage: make_custom_sound.sh <src> <out.mp3> [start] [dur] [bitrate]}"
out="${2:?out path required}"
start="${3:-0}"; dur="${4:-29}"; br="${5:-128k}"

tmp=""
case "$src" in
  http*://*)
    tmp="$(mktemp).mp3"
    env -u HTTPS_PROXY -u HTTP_PROXY -u https_proxy -u http_proxy \
      curl -sSL -m 60 --noproxy '*' -A "Mozilla/5.0" -o "$tmp" "$src"
    src="$tmp";;
esac

ffmpeg -y -hide_banner -loglevel error -ss "$start" -t "$dur" -i "$src" \
  -af "loudnorm=I=-10:TP=-1.0:LRA=11" -ac 2 -b:a "$br" -map_metadata -1 "$out"
[ -n "$tmp" ] && rm -f "$tmp"

bytes=$(stat -f%z "$out")
d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out")
vd=$(ffmpeg -hide_banner -i "$out" -af volumedetect -f null /dev/null 2>&1)
mx=$(printf '%s' "$vd" | grep -oE 'max_volume: [-0-9.]+' | awk '{print $2}')
mn=$(printf '%s' "$vd" | grep -oE 'mean_volume: [-0-9.]+' | awk '{print $2}')
if [ "$bytes" -lt 500000 ]; then ok=true; else ok=false; fi
printf '{"out":"%s","bytes":%s,"kb":%s,"dur":%s,"max_db":"%s","mean_db":"%s","under_500kb":%s}\n' \
  "$out" "$bytes" "$((bytes/1024))" "$d" "$mx" "$mn" "$ok"
if [ "$ok" = false ]; then echo "make_custom_sound: result >=500KB — lower --bitrate (e.g. 112k/96k) or --dur" >&2; exit 1; fi
