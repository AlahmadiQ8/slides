#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$REPO_ROOT/README.md"
SLIDES_DIR="$REPO_ROOT/slides"
BASE_URL="https://alahmadiq8.github.io/slides/slides"

# Build the markdown list of slides into a temp file
slides_tmp="$(mktemp)"
count=0
for file in "$SLIDES_DIR"/*.html; do
  [ -f "$file" ] || continue
  basename="$(basename "$file")"

  # Extract <title> content (portable sed, no grep -P)
  title="$(sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p' "$file" | head -1)"

  # Fall back to filename without extension
  if [ -z "$title" ]; then
    title="${basename%.html}"
  fi

  echo "- [${title}](${BASE_URL}/${basename})" >> "$slides_tmp"
  count=$((count + 1))
done

if [ "$count" -eq 0 ]; then
  echo "*No slides yet.*" > "$slides_tmp"
fi

# Replace content between markers using awk (atomic write via temp file)
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
