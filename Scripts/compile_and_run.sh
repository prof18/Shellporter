#!/usr/bin/env bash
# Kill running instances, package, relaunch, verify.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a; source "$ROOT_DIR/.env"; set +a
fi
ENV_APP_NAME=${APP_NAME:-}
ENV_PRODUCT_NAME=${PRODUCT_NAME:-}
ENV_EXECUTABLE_NAME=${EXECUTABLE_NAME:-}
ENV_BUNDLE_ID=${BUNDLE_ID:-}
APP_NAME=${APP_NAME:-Shellporter}
PRODUCT_NAME=${PRODUCT_NAME:-Shellporter}
EXECUTABLE_NAME=${EXECUTABLE_NAME:-$APP_NAME}
BUNDLE_ID=${BUNDLE_ID:-com.prof18.shellporter}
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
APP_PROCESS_PATTERN="${APP_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}"
DEBUG_PROCESS_PATTERN="${ROOT_DIR}/.build/debug/${PRODUCT_NAME}"
RELEASE_PROCESS_PATTERN="${ROOT_DIR}/.build/release/${PRODUCT_NAME}"
RUN_TESTS=0
RELEASE_ARCHES=""
DEV_MODE=0

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
has_valid_codesign_identity() {
  local identity_name="$1"
  security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"${identity_name}\""
}

for arg in "$@"; do
  case "${arg}" in
    --dev) DEV_MODE=1 ;;
    --test|-t) RUN_TESTS=1 ;;
    --release-universal) RELEASE_ARCHES="arm64 x86_64" ;;
    --release-arches=*) RELEASE_ARCHES="${arg#*=}" ;;
    --help|-h)
      log "Usage: $(basename "$0") [--dev] [--test] [--release-universal] [--release-arches=\"arm64 x86_64\"]"
      exit 0
      ;;
  esac
done

if [[ "${DEV_MODE}" == "1" ]]; then
  if [[ -z "${ENV_APP_NAME}" ]]; then
    APP_NAME="Shellporter Dev"
  fi
  if [[ -z "${ENV_EXECUTABLE_NAME}" ]]; then
    EXECUTABLE_NAME="Shellporter Dev"
  fi
  if [[ -z "${ENV_BUNDLE_ID}" ]]; then
    BUNDLE_ID="com.prof18.shellporter.dev"
  fi
  if [[ -z "${ENV_PRODUCT_NAME}" ]]; then
    PRODUCT_NAME="Shellporter"
  fi
  APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
  APP_PROCESS_PATTERN="${APP_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}"
  DEBUG_PROCESS_PATTERN="${ROOT_DIR}/.build/debug/${PRODUCT_NAME}"
  RELEASE_PROCESS_PATTERN="${ROOT_DIR}/.build/release/${PRODUCT_NAME}"
fi

log "==> Killing existing ${APP_NAME} instances"
pkill -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
pkill -f "${DEBUG_PROCESS_PATTERN}" 2>/dev/null || true
pkill -f "${RELEASE_PROCESS_PATTERN}" 2>/dev/null || true
pkill -x "${EXECUTABLE_NAME}" 2>/dev/null || true

if [[ "${RUN_TESTS}" == "1" ]]; then
  log "==> swift test"
  swift test -q
fi

HOST_ARCH="$(uname -m)"
ARCHES_VALUE="${HOST_ARCH}"
if [[ -n "${RELEASE_ARCHES}" ]]; then
  ARCHES_VALUE="${RELEASE_ARCHES}"
fi

log "==> package app"
APP_DEV_CERT_NAME="${APP_NAME} Development"
PRODUCT_DEV_CERT_NAME="${PRODUCT_NAME} Development"
if [[ -n "${APP_IDENTITY:-}" ]]; then
  log "Using APP_IDENTITY='${APP_IDENTITY}' for signing."
  APP_IDENTITY="${APP_IDENTITY}" APP_NAME="${APP_NAME}" PRODUCT_NAME="${PRODUCT_NAME}" EXECUTABLE_NAME="${EXECUTABLE_NAME}" BUNDLE_ID="${BUNDLE_ID}" ARCHES="${ARCHES_VALUE}" "${ROOT_DIR}/Scripts/package_app.sh" release
elif has_valid_codesign_identity "${APP_DEV_CERT_NAME}"; then
  log "Using local development identity '${APP_DEV_CERT_NAME}' for stable signing."
  APP_IDENTITY="${APP_DEV_CERT_NAME}" APP_NAME="${APP_NAME}" PRODUCT_NAME="${PRODUCT_NAME}" EXECUTABLE_NAME="${EXECUTABLE_NAME}" BUNDLE_ID="${BUNDLE_ID}" ARCHES="${ARCHES_VALUE}" "${ROOT_DIR}/Scripts/package_app.sh" release
elif [[ "${APP_DEV_CERT_NAME}" != "${PRODUCT_DEV_CERT_NAME}" ]] && has_valid_codesign_identity "${PRODUCT_DEV_CERT_NAME}"; then
  log "Using local development identity '${PRODUCT_DEV_CERT_NAME}' for stable signing."
  APP_IDENTITY="${PRODUCT_DEV_CERT_NAME}" APP_NAME="${APP_NAME}" PRODUCT_NAME="${PRODUCT_NAME}" EXECUTABLE_NAME="${EXECUTABLE_NAME}" BUNDLE_ID="${BUNDLE_ID}" ARCHES="${ARCHES_VALUE}" "${ROOT_DIR}/Scripts/package_app.sh" release
else
  log "WARN: No stable signing identity found; falling back to ad-hoc signing."
  log "WARN: Accessibility permission may not persist across rebuilds."
  log "WARN: Run './Scripts/setup_dev_signing.sh' once to create a stable local identity."
  SIGNING_MODE=adhoc APP_NAME="${APP_NAME}" PRODUCT_NAME="${PRODUCT_NAME}" EXECUTABLE_NAME="${EXECUTABLE_NAME}" BUNDLE_ID="${BUNDLE_ID}" ARCHES="${ARCHES_VALUE}" "${ROOT_DIR}/Scripts/package_app.sh" release
fi

log "==> launch app"
if ! open "${APP_BUNDLE}"; then
  log "WARN: open failed; launching binary directly."
  "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 &
  disown
fi

for _ in {1..10}; do
  if pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1; then
    log "OK: ${APP_NAME} is running."
    exit 0
  fi
  sleep 0.4
done
fail "App exited immediately. Check crash logs in Console.app (User Reports)."
