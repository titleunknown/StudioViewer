#!/bin/sh
# Downloads a self-contained Python 3.13 for Apple Silicon (python-build-standalone, by Astral) into
# App/Python/python, checks it against the release's SHA256SUMS, and trims what the viewer never
# uses. The "Bundle Python" build phase then copies it into the app. Run it once, and again to update:
#     App/scripts/fetch-python.sh
set -e

REPO="astral-sh/python-build-standalone"
TAG="${TAG:-latest}"   # e.g. TAG=20261020 App/scripts/fetch-python.sh, to rebuild with a known release
# In download links the "+" is written %2B.
PATTERN='cpython-3\.13\.[0-9]+(\+|%2B)[0-9]+-aarch64-apple-darwin-install_only_stripped\.tar\.gz'
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HERE/Python"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$TAG" = "latest" ]; then RELEASE="releases/latest"; else RELEASE="releases/tags/$TAG"; fi
echo "Finding release $TAG of $REPO..."
curl -fsSL "https://api.github.com/repos/$REPO/$RELEASE" -o "$WORK/release.json"
URL=$(grep -oE "\"browser_download_url\": *\"[^\"]*$PATTERN\"" "$WORK/release.json" | head -1 | sed -E 's/.*"(https[^"]*)"/\1/')
SUMS=$(grep -oE '"browser_download_url": *"[^"]*SHA256SUMS"' "$WORK/release.json" | head -1 | sed -E 's/.*"(https[^"]*)"/\1/')
[ -n "$URL" ] || { echo "No matching Python build found in release $TAG." >&2; exit 1; }
NAME=$(basename "$URL" | sed 's/%2B/+/g')

echo "Downloading $NAME..."
curl -fL "$URL" -o "$WORK/python.tar.gz"
if [ -n "$SUMS" ]; then
  curl -fsSL "$SUMS" -o "$WORK/SHA256SUMS"
  WANT=$(grep " $NAME\$" "$WORK/SHA256SUMS" | cut -d' ' -f1)
  GOT=$(shasum -a 256 "$WORK/python.tar.gz" | cut -d' ' -f1)
  [ -n "$WANT" ] && [ "$WANT" = "$GOT" ] || { echo "Checksum mismatch for $NAME." >&2; exit 1; }
  echo "Checksum OK."
else
  echo "warning: the release has no SHA256SUMS file; not verified." >&2
fi

rm -rf "$OUT"
mkdir -p "$OUT"
tar -xzf "$WORK/python.tar.gz" -C "$OUT"   # unpacks to $OUT/python

# The viewer uses only the standard library's networking, json and sqlite parts. Drop the rest's bulk.
LIB="$OUT/python/lib/python3.13"
rm -rf "$LIB/test" "$LIB/idlelib" "$LIB/tkinter" "$LIB/turtledemo" "$LIB/ensurepip" "$LIB/lib2to3" \
       "$LIB/site-packages"/* "$OUT/python/share" "$OUT/python/include"
find "$OUT/python" -name '__pycache__' -prune -exec rm -rf {} +
find "$OUT/python/lib" -maxdepth 1 \( -name 'libtcl*' -o -name 'libtk*' -o -name 'tcl*' -o -name 'tk*' \) -prune -exec rm -rf {} +
find "$LIB/lib-dynload" -name '_tkinter*' -delete

echo "$NAME" > "$OUT/VERSION"
"$OUT/python/bin/python3" -I -c "import json, sqlite3, http.server, urllib.request; print('Python', __import__('sys').version.split()[0], 'works.')"
du -sh "$OUT/python"
