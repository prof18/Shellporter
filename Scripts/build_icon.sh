#!/usr/bin/env bash
set -euo pipefail

ICON_FILE=${1:-Icon.icon}
BASENAME=${2:-Icon}
OUT_ROOT=${3:-build/icon}

if [[ -z "${XCODE_APP:-}" ]]; then
  if DEVELOPER_DIR=$(xcode-select -p 2>/dev/null); then
    XCODE_APP=$(cd "$DEVELOPER_DIR/../.." && pwd)
  else
    XCODE_APP=/Applications/Xcode.app
  fi
fi

ICTOOL="$XCODE_APP/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICTOOL" ]]; then
  ICTOOL="$XCODE_APP/Contents/Applications/Icon Composer.app/Contents/Executables/icontool"
fi
if [[ ! -x "$ICTOOL" ]]; then
  echo "ictool/icontool not found. Set XCODE_APP if Xcode is elsewhere." >&2
  exit 1
fi

if [[ ! -e "$ICON_FILE" ]]; then
  echo "Icon source not found at: $ICON_FILE" >&2
  exit 1
fi
ICON_FILE=$(cd "$(dirname "$ICON_FILE")" && pwd)/$(basename "$ICON_FILE")

ICONSET_DIR="$OUT_ROOT/${BASENAME}.iconset"
TMP_DIR="$OUT_ROOT/tmp"
mkdir -p "$ICONSET_DIR" "$TMP_DIR"

MASTER_ART="$TMP_DIR/icon_art_824.png"
MASTER_1024="$TMP_DIR/icon_1024.png"

# Render inner art (no margin) with macOS Default appearance.
# Prefer modern ictool syntax (Xcode 26+), then fall back to legacy syntax.
if ! "$ICTOOL" "$ICON_FILE" \
  --export-image \
  --output-file "$MASTER_ART" \
  --platform macOS \
  --rendition Default \
  --width 824 \
  --height 824 \
  --scale 1 \
  --light-angle -45; then
  "$ICTOOL" "$ICON_FILE" \
    --export-preview macOS Default 824 824 1 -45 "$MASTER_ART"
fi

# Pad to 1024x1024 with transparent border.
sips --padToHeightWidth 1024 1024 "$MASTER_ART" --out "$MASTER_1024" >/dev/null

# Generate required sizes.
sizes=(16 32 64 128 256 512 1024)
for sz in "${sizes[@]}"; do
  out="$ICONSET_DIR/icon_${sz}x${sz}.png"
  sips -z "$sz" "$sz" "$MASTER_1024" --out "$out" >/dev/null
  if [[ "$sz" -ne 1024 ]]; then
    dbl=$((sz*2))
    out2="$ICONSET_DIR/icon_${sz}x${sz}@2x.png"
    sips -z "$dbl" "$dbl" "$MASTER_1024" --out "$out2" >/dev/null
  fi
done

# 512x512@2x already covered by 1024; ensure it exists.
cp "$MASTER_1024" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o Icon.icns

echo "Icon.icns generated at $(pwd)/Icon.icns"
