#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS with Xcode installed." >&2
  exit 1
fi
command -v xcodebuild >/dev/null || { echo "Xcode command-line tools are required." >&2; exit 1; }

BUILD_ROOT="$ROOT/.build-unsigned"
OUTPUT_DIR="$ROOT/dist"
APP_PATH="$BUILD_ROOT/Build/Products/Release/VYBE.app"
ZIP_PATH="$OUTPUT_DIR/VYBE-3.0.0-Unsigned-macOS.zip"

rm -rf "$BUILD_ROOT" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

xcodebuild \
  -project "$ROOT/VYBE.xcodeproj" \
  -target VYBE \
  -configuration Release \
  -sdk macosx \
  -derivedDataPath "$BUILD_ROOT" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build reported success but VYBE.app was not found at: $APP_PATH" >&2
  exit 1
fi

# Fail if Xcode unexpectedly produced a signed app.
if /usr/bin/codesign -dv "$APP_PATH" >/dev/null 2>&1; then
  echo "Unexpected code signature detected; refusing to label this package unsigned." >&2
  exit 1
fi

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Unsigned app: $APP_PATH"
echo "Unsigned distribution ZIP: $ZIP_PATH"
echo "No Developer ID signing, Apple Development signing, or notarization was performed."
