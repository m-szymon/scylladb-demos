#!/usr/bin/env bash
# Assemble deck.html from deck.json + slides/*.html, then print deck.pdf with headless Chromium.
#
#   ./build.sh          build deck.html and deck.pdf
#   ./build.sh html     build deck.html only
#
# deck.html opens in any browser: arrows navigate, "n" toggles speaker notes, "p" prints.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

TITLE=$(python3 -I -c 'import json;print(json.load(open("deck.json"))["title"])')
ORDER=$(python3 -I -c 'import json;print(" ".join(json.load(open("deck.json"))["order"]))')

{
  cat <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${TITLE}</title>
<link rel="stylesheet" href="viewer/deck.css">
</head>
<body>
<div class="deck">
EOF
  for id in $ORDER; do
    cat "slides/${id}.html"
    echo
  done
  cat <<'EOF'
</div>
<div id="hud"></div>
<div id="notes"></div>
<script src="viewer/deck.js"></script>
</body>
</html>
EOF
} > deck.html
echo "built deck.html ($(echo $ORDER | wc -w) slides)"

[[ "${1:-}" == "html" ]] && exit 0

CHROME="${CHROME:-}"
if [[ -z "$CHROME" ]]; then
  for c in google-chrome chromium chromium-browser "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux/chrome; do
    if command -v "$c" >/dev/null 2>&1 || [[ -x "$c" ]]; then CHROME="$c"; break; fi
  done
fi
[[ -n "$CHROME" ]] || { echo "no chromium found; set CHROME=/path/to/chrome" >&2; exit 1; }

"$CHROME" --headless --disable-gpu --no-sandbox --no-pdf-header-footer \
  --run-all-compositor-stages-before-draw --virtual-time-budget=5000 \
  --print-to-pdf="$PWD/deck.pdf" "file://$PWD/deck.html" 2>/dev/null
echo "built deck.pdf ($(du -h deck.pdf | cut -f1))"
