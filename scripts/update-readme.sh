#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$REPO_ROOT/README.md"
SLIDES_DIR="$REPO_ROOT/slides"
BASE_URL="https://alahmadiq8.github.io/slides/slides"

# ── OG image generation ────────────────────────────────────────────
# Generate a 1200x630 screenshot of each slide's title page using playwright-cli.
# Skipped when playwright-cli is not installed (e.g. in CI without a browser).
generate_og_images() {
  if ! command -v playwright-cli &>/dev/null; then
    echo "playwright-cli not found – skipping OG image generation."
    return
  fi

  echo "Generating OG images…"

  # Start a temporary HTTP server to serve slides
  local port=8976
  python3 -m http.server "$port" --directory "$SLIDES_DIR" &>/dev/null &
  local server_pid=$!
  # Give the server a moment to start
  sleep 1

  playwright-cli open
  playwright-cli resize 1200 630

  for file in "$SLIDES_DIR"/*.html; do
    [ -f "$file" ] || continue
    local bn
    bn="$(basename "$file")"
    local slug="${bn%.html}"
    local og_path="${SLIDES_DIR}/${slug}-og.png"

    playwright-cli goto "http://localhost:${port}/${bn}"
    # wait for fonts / reveal.js to render
    playwright-cli eval "new Promise(r => setTimeout(r, 2000))" >/dev/null 2>&1 || sleep 2
    playwright-cli screenshot --filename="$og_path"
    echo "  Generated ${slug}-og.png"
  done

  playwright-cli close
  kill "$server_pid" 2>/dev/null || true
}

if [ "${SKIP_OG:-}" != "1" ]; then
  generate_og_images
fi

# ── Build slides list & inject OG meta tags ────────────────────────
slides_tmp="$(mktemp)"
count=0
for file in "$SLIDES_DIR"/*.html; do
  [ -f "$file" ] || continue
  basename="$(basename "$file")"
  slug="${basename%.html}"

  # Extract <title> content (portable sed, no grep -P)
  title="$(sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p' "$file" | head -1)"
  if [ -z "$title" ]; then
    title="$slug"
  fi

  # Extract <meta name="description"> content
  description="$(sed -n 's/.*<meta name="description" content="\([^"]*\)".*/\1/p' "$file" | head -1)"
  if [ -z "$description" ]; then
    description="$title"
  fi

  slide_url="${BASE_URL}/${basename}"
  og_image_url="${BASE_URL}/${slug}-og.png"

  # Inject og: meta tags if not already present
  if ! grep -q 'og:title' "$file"; then
    og_tags='  <meta property="og:title" content="'"$title"'">\
  <meta property="og:description" content="'"$description"'">\
  <meta property="og:image" content="'"$og_image_url"'">\
  <meta property="og:url" content="'"$slide_url"'">\
  <meta property="og:type" content="website">\
  <meta name="twitter:card" content="summary_large_image">\
  <meta name="twitter:title" content="'"$title"'">\
  <meta name="twitter:description" content="'"$description"'">\
  <meta name="twitter:image" content="'"$og_image_url"'">'

    tmp_file="$(mktemp)"
    sed "/<title>/a\\
$og_tags" "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
    echo "  Injected OG tags into ${basename}"
  fi

  echo "- [${title}](${slide_url})" >> "$slides_tmp"
  count=$((count + 1))
done

if [ "$count" -eq 0 ]; then
  echo "*No slides yet.*" > "$slides_tmp"
fi

# ── Update README between markers ──────────────────────────────────
readme_tmp="$(mktemp)"
awk '
  /<!-- SLIDES-START -->/ {
    print
    while ((getline line < "'"$slides_tmp"'") > 0) print line
    skip=1; next
  }
  /<!-- SLIDES-END -->/ { skip=0 }
  skip { next }
  { print }
' "$README" > "$readme_tmp"

mv "$readme_tmp" "$README"
rm -f "$slides_tmp"
echo "README.md updated with ${count} slide(s)."
