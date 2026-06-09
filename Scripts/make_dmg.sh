#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [[ -f "$ROOT/.env" ]]; then
  set -a; source "$ROOT/.env"; set +a
fi

source "$ROOT/version.env"

PRODUCT_NAME=${PRODUCT_NAME:-Shellporter}
APP_NAME=${APP_NAME:-Shellporter}
APP_BUNDLE=${APP_BUNDLE:-"$ROOT/${APP_NAME}.app"}
APP_IDENTITY=${APP_IDENTITY:-}
KEYCHAIN_PROFILE=${KEYCHAIN_PROFILE:-"NOTARIZATION_PASSWORD"}
DMG_NAME=${DMG_NAME:-"${APP_NAME}-${MARKETING_VERSION}.dmg"}
VOLUME_NAME=${VOLUME_NAME:-"$APP_NAME"}
RESOURCE_BUNDLE_NAME=${RESOURCE_BUNDLE_NAME:-"${PRODUCT_NAME}_${PRODUCT_NAME}.bundle"}
NOTARIZE_DMG=0

usage() {
  cat <<'USAGE'
Usage: Scripts/make_dmg.sh [--notarize]

Options:
  --notarize   Submit the DMG to Apple notarization and staple the ticket.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --notarize) NOTARIZE_DMG=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  echo "Run ./Scripts/sign-and-notarize.sh first." >&2
  exit 1
fi

validate_packaged_app() {
  local app="$1"
  local resource_bundle="$app/Contents/Resources/$RESOURCE_BUNDLE_NAME"
  local required_resources=(
    "en.lproj/Localizable.strings"
    "PrivacyInfo.xcprivacy"
    "shellporter-menubar-normal-18.png"
    "shellporter-menubar-normal-36.png"
  )

  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app" >/dev/null
  /usr/bin/xcrun stapler validate "$app" >/dev/null

  if [[ ! -d "$resource_bundle" ]]; then
    echo "Resource bundle not found in packaged app: $resource_bundle" >&2
    exit 1
  fi

  for resource in "${required_resources[@]}"; do
    if [[ ! -f "$resource_bundle/$resource" ]]; then
      echo "Required resource not found in packaged app: $resource_bundle/$resource" >&2
      exit 1
    fi
  done
}

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$APP_VERSION" != "$MARKETING_VERSION" ]]; then
  echo "App version $APP_VERSION does not match version.env $MARKETING_VERSION." >&2
  exit 1
fi

validate_packaged_app "$APP_BUNDLE"

STAGING_DIR="$ROOT/.build/dmg/${APP_NAME}-${MARKETING_VERSION}"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

STAGED_APP="$STAGING_DIR/${APP_NAME}.app"
/usr/bin/ditto "$APP_BUNDLE" "$STAGED_APP"
validate_packaged_app "$STAGED_APP"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_NAME"
/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_NAME" \
  >/dev/null

if [[ -n "$APP_IDENTITY" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$APP_IDENTITY" "$DMG_NAME"
fi

/usr/bin/hdiutil verify "$DMG_NAME" >/dev/null

if [[ "$NOTARIZE_DMG" == "1" ]]; then
  /usr/bin/xcrun notarytool submit "$DMG_NAME" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait
  /usr/bin/xcrun stapler staple "$DMG_NAME"
  /usr/bin/xcrun stapler validate "$DMG_NAME"
  /usr/sbin/spctl -a -t open --context context:primary-signature -vv "$DMG_NAME"
fi

echo "Done: $DMG_NAME"
