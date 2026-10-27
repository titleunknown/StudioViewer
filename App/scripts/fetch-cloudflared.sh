#!/bin/sh
# Downloads cloudflared (Cloudflare's tunnel client, Apache-2.0) for Apple Silicon into
# App/Cloudflared, checks it against the SHA-256 listed in the release notes, and saves its licence.
# The "Bundle helpers" build phase then copies and signs it into the app. Run once, and again to update:
#     App/scripts/fetch-cloudflared.sh              # the latest release
#     TAG=2026.10.2 App/scripts/fetch-cloudflared.sh   # a specific one
set -e

REPO="cloudflare/cloudflared"
TAG="${TAG:-latest}"
ASSET="cloudflared-darwin-arm64.tgz"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HERE/Cloudflared"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$TAG" = "latest" ]; then RELEASE="releases/latest"; else RELEASE="releases/tags/$TAG"; fi
echo "Finding release $TAG of $REPO..."
curl -fsSL "https://api.github.com/repos/$REPO/$RELEASE" -o "$WORK/release.json"
VERSION=$(/usr/bin/python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['tag_name'])" "$WORK/release.json")
URL=$(/usr/bin/python3 -I -c "import json,sys; print(next(a['browser_download_url'] for a in json.load(open(sys.argv[1]))['assets'] if a['name'] == sys.argv[2]))" "$WORK/release.json" "$ASSET")
# The release notes list "cloudflared-darwin-arm64.tgz: <sha256>".
WANT=$(/usr/bin/python3 -I -c "
import json, re, sys
body = json.load(open(sys.argv[1]))['body']
m = re.search(re.escape(sys.argv[2]) + r':\s*([0-9a-f]{64})', body)
print(m.group(1) if m else '')" "$WORK/release.json" "$ASSET")

echo "Downloading $ASSET ($VERSION)..."
curl -fL "$URL" -o "$WORK/$ASSET"
mkdir -p "$WORK/x"
tar -xzf "$WORK/$ASSET" -C "$WORK/x"
# The listed checksum is of the cloudflared program inside the .tgz, not of the .tgz itself.
GOT=$(shasum -a 256 "$WORK/x/cloudflared" | cut -d' ' -f1)
[ -n "$WANT" ] && [ "$WANT" = "$GOT" ] || { echo "Checksum mismatch or missing for $ASSET." >&2; exit 1; }
echo "Checksum OK."
# And it must carry Cloudflare's own Developer ID signature.
codesign --verify --strict "$WORK/x/cloudflared"
codesign -dvv "$WORK/x/cloudflared" 2>&1 | grep -q "^TeamIdentifier=68WVV388M8$" \
  || { echo "cloudflared isn't signed by Cloudflare Inc. (68WVV388M8)." >&2; exit 1; }
echo "Signed by Cloudflare Inc. OK."

rm -rf "$OUT"
mkdir -p "$OUT"
mv "$WORK/x/cloudflared" "$OUT/cloudflared"
chmod +x "$OUT/cloudflared"
curl -fsSL "https://raw.githubusercontent.com/$REPO/$VERSION/LICENSE" -o "$OUT/LICENSE"
echo "$VERSION" > "$OUT/VERSION"
"$OUT/cloudflared" --version
