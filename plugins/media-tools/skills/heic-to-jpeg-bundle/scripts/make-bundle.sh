#!/usr/bin/env bash
# make-bundle.sh — turn a folder of HEIC (or any sips-readable images) into a
# shareable JPEG bundle: a browsable gallery + an optional password-protected ZIP
# sized to fit a host's per-file cap. macOS `sips` only — zero install.
#
# Usage:
#   make-bundle.sh --src DIR [options]
#
# Options:
#   --src DIR            Source folder of .heic/.HEIC/.jpg/.png images (required)
#   --out DIR            Output root (default: <src>/_bundle)
#   --title "TEXT"       Gallery <h1> (default: "Photos")
#   --view-edge PX       Long-edge for the per-photo "view" JPEGs (default: 2048)
#   --view-quality N     JPEG quality 1-100 for view tier (default: 82)
#   --full               Also emit a full-resolution JPEG tier (no resize)
#   --zip                Build a ZIP of the view tier
#   --zip-cap-mib N      Shrink the ZIP tier to land under N MiB (default: 25; Cloudflare Workers cap)
#   --password PW        Password-protect the ZIP (ZipCrypto — opens in Windows/7-Zip/macOS)
#   --jobs N             Parallel sips workers (default: 6)
#
# Output layout:
#   <out>/site/index.html         gallery (thumbnails -> full view JPEGs)
#   <out>/site/photos/photo-NNN.jpg
#   <out>/site/thumbs/photo-NNN.jpg
#   <out>/site/bundle.zip         (when --zip and it fits the cap; co-host on a static host)
#   <out>/full/photo-NNN.jpg      (when --full; full-res, host the ZIP off a large-file host)
set -euo pipefail

command -v sips >/dev/null || { echo "sips not found (macOS only)"; exit 1; }

SRC="" OUT="" TITLE="Photos" VIEW_EDGE=2048 VIEW_Q=82 FULL=0 ZIP=0 ZIP_CAP=25 PW="" JOBS=6
while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --title) TITLE="$2"; shift 2;;
    --view-edge) VIEW_EDGE="$2"; shift 2;;
    --view-quality) VIEW_Q="$2"; shift 2;;
    --full) FULL=1; shift;;
    --zip) ZIP=1; shift;;
    --zip-cap-mib) ZIP_CAP="$2"; shift 2;;
    --password) PW="$2"; shift 2;;
    --jobs) JOBS="$2"; shift 2;;
    *) echo "unknown option: $1"; exit 2;;
  esac
done
[ -n "$SRC" ] && [ -d "$SRC" ] || { echo "--src DIR required"; exit 2; }
OUT="${OUT:-$SRC/_bundle}"

# Collect source images (sips reads heic/jpg/png/tiff/...), sorted for stable order.
mapfile -t SRCS < <(find "$SRC" -maxdepth 1 -type f \
  \( -iname '*.heic' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.tiff' \) | sort)
N=${#SRCS[@]}
[ "$N" -gt 0 ] || { echo "no images found in $SRC"; exit 1; }

SITE="$OUT/site"; FULLD="$OUT/full"
rm -rf "$OUT"; mkdir -p "$SITE/photos" "$SITE/thumbs"
[ "$FULL" = 1 ] && mkdir -p "$FULLD"

throttle() { while (( $(jobs -rp | wc -l) >= JOBS )); do wait -n; done; }

echo "[bundle] $N images -> view ${VIEW_EDGE}px q${VIEW_Q}$([ "$FULL" = 1 ] && echo ' + full')"
i=0
for f in "${SRCS[@]}"; do
  i=$((i + 1)); out=$(printf 'photo-%03d.jpg' "$i")
  throttle
  {
    sips -s format jpeg -s formatOptions "$VIEW_Q" -Z "$VIEW_EDGE" "$f" --out "$SITE/photos/$out" >/dev/null 2>&1
    sips -s format jpeg -s formatOptions 70 -Z 420 "$f" --out "$SITE/thumbs/$out" >/dev/null 2>&1
    [ "$FULL" = 1 ] && sips -s format jpeg -s formatOptions 88 "$f" --out "$FULLD/$out" >/dev/null 2>&1
  } &
done
wait

# Gallery index.html
{
  cat <<HTML
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>${TITLE}</title>
<style>:root{color-scheme:light dark}*{box-sizing:border-box}
body{margin:0;font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif;background:#0f1115;color:#e6e8eb}
header{padding:26px 18px 14px;max-width:1100px;margin:0 auto}h1{font-size:1.5rem;margin:0 0 6px}
.sub{color:#9aa3ad;margin:0 0 16px}.btn{display:inline-flex;gap:8px;text-decoration:none;background:#1f6feb;color:#fff;padding:11px 16px;border-radius:9px;font-weight:600}
.btn small{font-weight:400;opacity:.8}.note{color:#9aa3ad;font-size:.85rem;margin:10px 0 0}
main{max-width:1100px;margin:0 auto;padding:10px 14px 60px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px}
.grid a{display:block;aspect-ratio:4/3;overflow:hidden;border-radius:7px;background:#1a1d23}
.grid img{width:100%;height:100%;object-fit:cover;display:block}</style></head><body>
<header><h1>${TITLE}</h1><p class="sub">${N} photos · JPEG · tap any photo for full size.</p>
HTML
  if [ "$ZIP" = 1 ]; then
    echo '<div><a class="btn" href="bundle.zip">⬇ Download all (ZIP)'"$([ -n "$PW" ] && echo ' <small>password-protected</small>')"'</a></div>'
    [ -n "$PW" ] && echo '<p class="note">The ZIP is password-protected — the password is in the message/page that linked you here.</p>'
  fi
  echo '</header><main><div class="grid">'
  for ((j = 1; j <= N; j++)); do
    n=$(printf '%03d' "$j")
    printf '<a href="photos/photo-%s.jpg" target="_blank" rel="noopener"><img loading="lazy" src="thumbs/photo-%s.jpg" alt="photo %s"></a>\n' "$n" "$n" "$n"
  done
  echo '</div></main></body></html>'
} > "$SITE/index.html"

# Optional ZIP, downscaled to fit the per-file cap.
if [ "$ZIP" = 1 ]; then
  command -v zip >/dev/null || { echo "zip not found"; exit 1; }
  ZSRC="$SITE/photos"; edge="$VIEW_EDGE"; q="$VIEW_Q"; tmp="$OUT/.ziptier"
  for _ in 1 2 3 4 5; do
    rm -f "$SITE/bundle.zip"
    ( cd "$ZSRC" && if [ -n "$PW" ]; then zip -q -0 -e -P "$PW" "$SITE/bundle.zip" photo-*.jpg; else zip -q -0 "$SITE/bundle.zip" photo-*.jpg; fi )
    mib=$(( $(stat -f%z "$SITE/bundle.zip") / 1048576 ))
    if [ "$mib" -lt "$ZIP_CAP" ]; then echo "[bundle] zip ${mib}MiB (<${ZIP_CAP}) at ${edge}px q${q}"; break; fi
    # too big: rebuild a smaller tier and retry
    edge=$(( edge * 78 / 100 )); q=$(( q > 72 ? q - 4 : q ))
    echo "[bundle] zip ${mib}MiB ≥ ${ZIP_CAP}; reshrinking to ${edge}px q${q}"
    rm -rf "$tmp"; mkdir -p "$tmp"; k=0
    for f in "${SRCS[@]}"; do k=$((k+1)); o=$(printf 'photo-%03d.jpg' "$k"); throttle
      sips -s format jpeg -s formatOptions "$q" -Z "$edge" "$f" --out "$tmp/$o" >/dev/null 2>&1 & done; wait
    ZSRC="$tmp"
  done
  rm -rf "$tmp"
fi

echo "[bundle] site: $(find "$SITE" -type f | wc -l | tr -d ' ') files, $(du -sh "$SITE" | cut -f1)  ->  $SITE"
[ "$FULL" = 1 ] && echo "[bundle] full-res tier: $(find "$FULLD" -type f | wc -l | tr -d ' ') files, $(du -sh "$FULLD" | cut -f1)  ->  $FULLD"
