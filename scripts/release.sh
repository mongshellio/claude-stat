#!/usr/bin/env bash
# Build → sign → notarize → .dmg for sharing mongshell-menubar.app with others.
#
# ── One-time prerequisites ───────────────────────────────────────────────
# 1. Apple Developer account ($99/yr) and a "Developer ID Application"
#    certificate installed in your login keychain. Check with:
#        security find-identity -v -p codesigning
#    You should see: "Developer ID Application: <Name> (<TEAMID>)"
# 2. Store notarization credentials once (uses an app-specific password from
#    appleid.apple.com, NOT your Apple ID password):
#        xcrun notarytool store-credentials mongshell-menubar-notary \
#            --apple-id "you@example.com" --team-id "TEAMID" \
#            --password "abcd-efgh-ijkl-mnop"
#
# ── Usage ────────────────────────────────────────────────────────────────
#     DEV_ID="Developer ID Application: Your Name (TEAMID)" \
#     NOTARY_PROFILE="mongshell-menubar-notary" \
#     scripts/release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/mongshell-menubar.app"
DMG="$ROOT/mongshell-menubar.dmg"
DEV_ID="${DEV_ID:?set DEV_ID to your 'Developer ID Application: …' identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-mongshell-menubar-notary}"

echo "▶ building release bundle"
"$ROOT/scripts/make_app.sh" release   # produces mongshell-menubar.app (ad-hoc); we re-sign below

echo "▶ code signing (Developer ID + hardened runtime)"
codesign --force --options runtime --timestamp \
         --sign "$DEV_ID" "$APP/Contents/MacOS/mongshell-menubar"
codesign --force --options runtime --timestamp \
         --sign "$DEV_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "▶ building .dmg"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target
hdiutil create -volname "mongshell-menubar" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "▶ notarizing (submitting to Apple — may take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▶ stapling ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "✓ done → $DMG"
echo "  Share this .dmg. Recipients drag mongshell-menubar into Applications and open it."
