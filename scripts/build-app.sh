#!/bin/zsh
set -euo pipefail

APP_NAME="Capsomnia"
ROOT_DIR="${0:A:h:h}"
INFO_PLIST="$ROOT_DIR/resources/Info.plist"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_SIGN_ID="${APP_SIGN_ID:--}"
BUILD_FLAVOR="${BUILD_FLAVOR:-development}"

case "$BUILD_FLAVOR" in
  development|release) ;;
  *)
    echo "Invalid BUILD_FLAVOR: $BUILD_FLAVOR" >&2
    exit 64
    ;;
esac

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
if [[ "$BUNDLE_ID" != "com.github.oonishidaichi.capsomnia" ]]; then
  echo "Unexpected bundle identifier: $BUNDLE_ID" >&2
  exit 78
fi

/usr/bin/swift build -c release >&2
/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

/usr/bin/install -m 0755 "$ROOT_DIR/.build/release/$APP_NAME" \
  "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
/usr/bin/install -m 0644 "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/install -m 0644 "$ROOT_DIR/resources/AppIcon.icns" \
  "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
/usr/bin/install -m 0755 "$ROOT_DIR/scripts/uninstall.sh" \
  "$APP_BUNDLE/Contents/Resources/uninstall.sh"

/usr/libexec/PlistBuddy -c "Set :CapsomniaBuildFlavor $BUILD_FLAVOR" \
  "$APP_BUNDLE/Contents/Info.plist"

# Remove staging metadata before signing. Signed output is never mutated afterward.
/usr/bin/xattr -cr "$APP_BUNDLE"

if [[ "$APP_SIGN_ID" == "-" ]]; then
  /usr/bin/codesign --force --options runtime --sign - "$APP_BUNDLE"
else
  /usr/bin/codesign --force --options runtime --timestamp --sign "$APP_SIGN_ID" "$APP_BUNDLE"
fi

/usr/bin/codesign --verify --all-architectures --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNED_ID="$(/usr/bin/codesign -dvv "$APP_BUNDLE" 2>&1 \
  | /usr/bin/awk -F= '$1 == "Identifier" { print $2; exit }')"
if [[ "$SIGNED_ID" != "$BUNDLE_ID" ]]; then
  echo "Signed app identifier mismatch: $SIGNED_ID" >&2
  exit 78
fi

echo "$APP_BUNDLE"
