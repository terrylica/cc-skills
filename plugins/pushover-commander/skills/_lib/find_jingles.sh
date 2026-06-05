#!/usr/bin/env bash
# find_jingles.sh <mixkit-category> [maxN]
# Print direct MP3 URLs from a Mixkit free SFX/stock-music category (free license, attribution optional).
# Categories incl: win game musical alarm bell tones alerts notification celebration funny
# (stock music: pass a /free-stock-music/tag/<tag>/ path-style category like "tag/happy")
set -euo pipefail
cat="${1:?usage: find_jingles.sh <category> [maxN]}"
maxN="${2:-15}"
case "$cat" in
  tag/*) url="https://mixkit.co/free-stock-music/${cat}/";;
  *)     url="https://mixkit.co/free-sound-effects/${cat}/";;
esac
env -u HTTPS_PROXY -u HTTP_PROXY -u https_proxy -u http_proxy \
  curl -sSL -m 30 --noproxy '*' -A "Mozilla/5.0" "$url" \
  | grep -oE 'https://assets\.mixkit\.co/[^"]+\.mp3' | sort -u | head -n "$maxN"
