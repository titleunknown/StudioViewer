#!/bin/bash
# Builds a notarized, stapled StudioViewer.app and a zip to share, the same way Xcode's Organizer
# does "Direct Distribution": archive, sign with the team's cloud-managed Developer ID certificate,
# upload to Apple's notary service, wait, then export the stapled app. It uses the Apple account
# signed in to Xcode (Settings > Accounts), so no passwords or API keys are needed here.
#     App/scripts/release.sh            # output in App/build/release
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HERE/build/release"
ARCHIVE="$OUT/StudioViewer.xcarchive"
TEAM="T9V5W5P5J4"

[ -x "$HERE/Python/python/bin/python3" ] || { echo "Run App/scripts/fetch-python.sh first: a release must bundle Python." >&2; exit 1; }
[ -x "$HERE/Cloudflared/cloudflared" ] || { echo "Run App/scripts/fetch-cloudflared.sh first: a release must bundle cloudflared." >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
options() {  # $1 = export or upload
  cat > "$OUT/Export-$1.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>$1</string>
</dict></plist>
EOF
  echo "$OUT/Export-$1.plist"
}

echo "== Archiving (Release)"
xcodebuild archive -project "$HERE/StudioViewer.xcodeproj" -scheme "StudioViewer" -configuration Release \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet

echo "== Uploading to Apple's notary service (Developer ID)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$(options upload)" \
  -exportPath "$OUT/upload" -allowProvisioningUpdates -quiet

echo "== Waiting for notarization (usually a few minutes)"
for i in $(seq 1 60); do
  if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$OUT" -quiet 2>/dev/null; then
    break
  fi
  [ "$i" = 60 ] && { echo "Still not notarized after 30 minutes; check Xcode's Organizer." >&2; exit 1; }
  sleep 30
done

APP="$OUT/StudioViewer.app"
VERSION=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)
echo "== Checking"
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
spctl -a -t exec -vv "$APP"
ditto -c -k --keepParent "$APP" "$OUT/StudioViewer-$VERSION.zip"
echo "Done: $OUT/StudioViewer-$VERSION.zip"
