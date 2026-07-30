#!/usr/bin/env bash
# Assembles mongshell-menubar.app from the SwiftPM build product.
# Usage: scripts/make_app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/mongshell-menubar.app"
BIN="$ROOT/.build/$CONFIG/mongshell-menubar"

echo "▶ swift build -c $CONFIG"
swift build -c "$CONFIG" --package-path "$ROOT"

echo "▶ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/mongshell-menubar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Code signature so Keychain / UserNotifications / ASWebAuth work locally.
#
# Prefer a self-signed code-signing certificate over an ad-hoc signature. The
# Keychain's "always allow" grant is bound to the app's designated requirement,
# and an ad-hoc signature pins that to the binary's cdhash — which changes on
# every rebuild, so the Claude Code credentials prompt comes back each time. A
# certificate makes the requirement `identifier … and certificate leaf = H"…"`,
# which survives rebuilds. See README § 개발용 for creating one.
#
# NOTE: `find-identity` without `-v` on purpose. A self-signed root is reported
# as CSSMERR_TP_NOT_TRUSTED (no trust anchor), so `-v` filters it out — but
# codesign doesn't need a trust chain, and Keychain ACL matching only compares
# the leaf certificate's hash. Requiring `-v` would mean never using the cert.
SIGN_ID="${SIGN_ID:-mongshell-menubar Dev}"
if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$SIGN_ID\""; then
  echo "▶ codesign ($SIGN_ID)"
  codesign --force --deep --sign "$SIGN_ID" "$APP" || {
    echo "  (signing with '$SIGN_ID' failed — falling back to ad-hoc)"
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  }
else
  echo "▶ ad-hoc codesign (no '$SIGN_ID' identity — Keychain prompts will repeat)"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
    echo "  (codesign skipped/failed — app still runs unsigned for local dev)"
fi

echo "✓ built $APP"
