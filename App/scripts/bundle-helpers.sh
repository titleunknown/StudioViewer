#!/bin/sh
# Xcode build phase "Bundle helpers": copies the programs the app runs into Contents/Resources and
# signs every binary in them with the app's identity, so the hardened, notarized app can run them:
#     App/Python/python      -> python/       (fetch-python.sh)      runs the viewer
#     App/Cloudflared/       -> cloudflared/  (fetch-cloudflared.sh)  remote sharing
# Without a helper's folder the build says so: the app then uses this Mac's own python3, and
# remote sharing reports cloudflared as missing.
#
# Each signed copy is cached and only redone when its VERSION, the signing identity or the
# configuration changes. Copying from the cache leaves unchanged files alone, so the app's own
# signature (made after this phase) stays valid from one build to the next. The phase declares
# each helper's VERSION file as an output, which tells Xcode to sign the app again when one changes.
set -e

RES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"

bundle() {  # name, source folder, executable that must exist, VERSION file, fetch script
  NAME="$1" SRC="$2" EXE="$3" VERSION_FILE="$4" FETCH="$5"
  DEST="$RES/$NAME"
  CACHE="$DERIVED_FILE_DIR/$NAME-signed"
  if [ ! -x "$SRC/$EXE" ]; then
    echo "note: No bundled $NAME (run App/scripts/$FETCH)."
    rm -rf "$DEST"
    return
  fi
  KEY="$(cat "$VERSION_FILE") | $EXPANDED_CODE_SIGN_IDENTITY | $CONFIGURATION"
  if [ "$(cat "$CACHE.key" 2>/dev/null)" != "$KEY" ]; then
    echo "Signing the bundled $NAME ($KEY)..."
    rm -rf "$CACHE" "$CACHE.key"
    rsync -a "$SRC/" "$CACHE/"
    if [ -n "$EXPANDED_CODE_SIGN_IDENTITY" ]; then
      if [ "$CONFIGURATION" = "Release" ]; then TIMESTAMP="--timestamp"; else TIMESTAMP="--timestamp=none"; fi
      find "$CACHE" -type f \( -perm -u+x -o -name '*.dylib' -o -name '*.so' \) | while read -r f; do
        if file -b "$f" | grep -q "Mach-O"; then
          codesign --force --options runtime $TIMESTAMP --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$f"
        fi
      done
    fi
    cp "$VERSION_FILE" "$CACHE/VERSION"
    echo "$KEY" > "$CACHE.key"
  fi
  rsync -a --delete "$CACHE/" "$DEST/"
}

bundle python "$SRCROOT/Python/python" bin/python3 "$SRCROOT/Python/VERSION" fetch-python.sh
bundle cloudflared "$SRCROOT/Cloudflared" cloudflared "$SRCROOT/Cloudflared/VERSION" fetch-cloudflared.sh
