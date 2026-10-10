#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version>" >&2
  exit 64
fi

VERSION="$1"
ROOT_DIR="${0:A:h:h}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Mochi.app"
CONTENTS_DIR="$APP_DIR/Contents"
MOCHI_BUILD_CACHE_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/mochi-release-cache"

mkdir -p "$MOCHI_BUILD_CACHE_ROOT/clang" "$MOCHI_BUILD_CACHE_ROOT/swiftpm"
export CLANG_MODULE_CACHE_PATH="$MOCHI_BUILD_CACHE_ROOT/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$MOCHI_BUILD_CACHE_ROOT/swiftpm"

rm -rf "$DIST_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

swift build --disable-sandbox --package-path "$ROOT_DIR" -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build --disable-sandbox --package-path "$ROOT_DIR" -c release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN_DIR/MochiApp" "$CONTENTS_DIR/MacOS/MochiApp"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Packaging/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-$(date +%s)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

if [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT_DIR/Packaging/Mochi.entitlements" \
    --sign "$APPLE_SIGNING_IDENTITY" "$APP_DIR"
else
  # Bind the bundle metadata and resources for local/test builds as well. Release
  # CI replaces this ad-hoc signature with the configured Developer ID identity.
  codesign --force --deep --sign - "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIST_DIR/Mochi-$VERSION.zip"
DMG_VENV="$MOCHI_BUILD_CACHE_ROOT/dmgbuild-venv"
if [[ ! -x "$DMG_VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$DMG_VENV"
  "$DMG_VENV/bin/pip" install --quiet "dmgbuild==1.6.7"
fi
"$DMG_VENV/bin/dmgbuild" -s "$ROOT_DIR/scripts/dmg-settings.py" \
  -D app="$APP_DIR" -D root="$ROOT_DIR" Mochi "$DIST_DIR/Mochi.dmg"

if [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$DIST_DIR/Mochi.dmg"
fi

if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
  xcrun notarytool submit "$DIST_DIR/Mochi.dmg" \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
  xcrun stapler staple "$DIST_DIR/Mochi.dmg"
  xcrun stapler validate "$DIST_DIR/Mochi.dmg"
  spctl --assess --type open --context context:primary-signature -v "$DIST_DIR/Mochi.dmg"
fi

shasum -a 256 "$DIST_DIR/Mochi.dmg" > "$DIST_DIR/Mochi.dmg.sha256"
DMG_SHA="$(awk '{print $1}' "$DIST_DIR/Mochi.dmg.sha256")"
jq -n \
  --arg version "$VERSION" \
  --arg commit "${GITHUB_SHA:-local}" \
  --arg sha256 "$DMG_SHA" \
  --arg download "https://github.com/jerrysun-ofive/mochi/releases/download/v$VERSION/Mochi.dmg" \
  '{version:$version,gitCommit:$commit,minimumMacOS:"13.0",architectures:["arm64","x86_64"],dmgURL:$download,dmgSHA256:$sha256}' \
  > "$DIST_DIR/release-manifest.json"

file "$CONTENTS_DIR/MacOS/MochiApp"
