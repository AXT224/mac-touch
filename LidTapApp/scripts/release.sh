#!/bin/sh
# Builds a signed, notarized LidTap-macOS.zip for a GitHub release.
#   scripts/release.sh            sign with your Developer ID, notarize, staple
#   scripts/release.sh --adhoc    same hardened-runtime build, signed ad hoc, no notarization (to test locally)
#
# One-time setup (needs an Apple Developer Program membership):
#   1. Xcode → Settings → Accounts → your team → Manage Certificates → + → Developer ID Application.
#   2. Make an app-specific password at account.apple.com, then store it for notarytool:
#        xcrun notarytool store-credentials lidtap --apple-id <your Apple ID> --team-id <TEAMID>
# Override the defaults with LIDTAP_SIGN_ID (certificate name or hash) and LIDTAP_NOTARY_PROFILE.
set -e
cd "$(dirname "$0")/.."
APP="build/LidTap.app"
ZIP="build/LidTap-macOS.zip"
PROFILE="${LIDTAP_NOTARY_PROFILE:-lidtap}"

if [ "$1" = "--adhoc" ]; then
  ID="-"
else
  ID="${LIDTAP_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"
  if [ -z "$ID" ]; then
    echo "No Developer ID Application certificate in your keychain. See the setup steps at the top of this script." >&2
    exit 1
  fi
  if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "No notarytool credentials named \"$PROFILE\". See the setup steps at the top of this script." >&2
    exit 1
  fi
fi

scripts/build.sh --no-install
echo "Signing with ${ID}…"
# Hardened runtime and a secure timestamp are what notarization requires.
codesign --force --options runtime --timestamp$( [ "$ID" = "-" ] && echo "=none" ) \
  --entitlements Resources/LidTap.entitlements --identifier dev.lidtap.LidTap --sign "$ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
if [ "$ID" != "-" ]; then
  echo "Notarizing (usually a few minutes)…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"   # zip again so the download carries the stapled ticket
  spctl --assess --type execute --verbose=2 "$APP"
fi
echo "Ready: $ZIP"
