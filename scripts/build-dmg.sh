#!/usr/bin/env bash
# Builds a Release, ad-hoc signed Widgee.app and packs it into dist/Widgee-<version>.dmg.
#
# Usage: scripts/build-dmg.sh
# Env:   ARCHS   architectures to build (default: "arm64 x86_64")
#        ALLOW_ARM64_FALLBACK=1  retry with arm64 only if the universal build fails
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found. $2"; }

need xcodegen "Install: brew install xcodegen"
need xcodebuild "Install Xcode."
need codesign "Xcode command line tools are required."
need hdiutil "This script must run on macOS."

VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([^"[:space:]]*\)"\{0,1\}[[:space:]]*$/\1/p' project.yml | head -n1)"
[[ -n "$VERSION" ]] || die "MARKETING_VERSION not found in project.yml"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] || die "MARKETING_VERSION '$VERSION' is not SemVer"

ARCHS="${ARCHS:-arm64 x86_64}"
DIST="$ROOT/dist"
DMG="$DIST/Widgee-$VERSION.dmg"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/widgee-build.XXXXXX")"
MOUNT_DIR=""
cleanup() {
  if [[ -n "$MOUNT_DIR" ]]; then hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> Widgee $VERSION, archs: $ARCHS"
echo "==> Generating Xcode project"
xcodegen generate --quiet || die "xcodegen failed"

build() {
  local archs="$1"
  rm -rf "$WORK/derived"
  xcodebuild -project Widgee.xcodeproj -scheme Widgee -configuration Release \
    -derivedDataPath "$WORK/derived" \
    ARCHS="$archs" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    build >"$WORK/xcodebuild.log" 2>&1
}

echo "==> Building Release"
if ! build "$ARCHS"; then
  if [[ "${ALLOW_ARM64_FALLBACK:-0}" == "1" && "$ARCHS" != "arm64" ]]; then
    echo "warning: build for '$ARCHS' failed, falling back to arm64 only" >&2
    tail -n 20 "$WORK/xcodebuild.log" >&2
    ARCHS="arm64"
    build "$ARCHS" || { tail -n 40 "$WORK/xcodebuild.log" >&2; die "xcodebuild failed (see log above)"; }
  else
    tail -n 40 "$WORK/xcodebuild.log" >&2
    die "xcodebuild failed for '$ARCHS' (set ALLOW_ARM64_FALLBACK=1 to retry with arm64 only)"
  fi
fi

APP_SRC="$WORK/derived/Build/Products/Release/Widgee.app"
[[ -d "$APP_SRC" ]] || die "Widgee.app not found at $APP_SRC"

STAGE="$WORK/stage"
mkdir -p "$STAGE"
ditto "$APP_SRC" "$STAGE/Widgee.app"

echo "==> Ad-hoc signing"
codesign --force --deep -s - "$STAGE/Widgee.app"
codesign --verify --deep --strict --verbose=2 "$STAGE/Widgee.app" || die "codesign verification failed"

BIN="$STAGE/Widgee.app/Contents/MacOS/Widgee"
echo "==> Architectures: $(lipo -archs "$BIN")"

mkdir -p "$DIST"
rm -f "$DMG"

echo "==> Creating $DMG"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "Widgee $VERSION" \
    --window-pos 200 120 --window-size 540 360 \
    --icon-size 96 \
    --icon "Widgee.app" 130 170 \
    --app-drop-link 410 170 \
    --no-internet-enable \
    "$DMG" "$STAGE" || die "create-dmg failed"
else
  echo "warning: create-dmg not installed (brew install create-dmg); using hdiutil fallback without window layout" >&2
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Widgee $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null \
    || die "hdiutil create failed"
fi
[[ -f "$DMG" ]] || die "DMG was not created"

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
echo "    sha256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
