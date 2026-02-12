#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [[ -f "$ROOT/.env" ]]; then
  set -a; source "$ROOT/.env"; set +a
fi

APP_NAME=${APP_NAME:-Shellporter}
APP_IDENTITY=${APP_IDENTITY:?"Set APP_IDENTITY in .env (e.g. 'Developer ID Application: Your Name (TEAMID)')"}
APPLE_ID=${APPLE_ID:?"Set APPLE_ID in .env (your Apple ID email for notarization)"}
TEAM_ID=${TEAM_ID:?"Set TEAM_ID in .env (your Apple Developer Team ID)"}
# App-specific password stored in Keychain.
# To set it up: xcrun notarytool store-credentials "NOTARIZATION_PASSWORD" \
#   --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "<app-specific-password>"
KEYCHAIN_PROFILE=${KEYCHAIN_PROFILE:-"NOTARIZATION_PASSWORD"}
APP_BUNDLE="${APP_NAME}.app"
source "$ROOT/version.env"
ZIP_NAME="${APP_NAME}-${MARKETING_VERSION}.zip"

trap 'rm -f /tmp/${APP_NAME}Notarize.zip' EXIT

ARCHES_VALUE=${ARCHES:-"arm64 x86_64"}
ARCH_LIST=( ${ARCHES_VALUE} )
for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c release --arch "$ARCH"
done
APP_IDENTITY="${APP_IDENTITY}" ARCHES="${ARCHES_VALUE}" "$ROOT/Scripts/package_app.sh" release

DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "/tmp/${APP_NAME}Notarize.zip"

xcrun notarytool submit "/tmp/${APP_NAME}Notarize.zip" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

xcrun stapler staple "$APP_BUNDLE"

xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"

spctl -a -t exec -vv "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"

echo "Done: $ZIP_NAME"
