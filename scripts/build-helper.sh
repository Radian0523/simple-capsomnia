#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
INFO_PLIST="$ROOT_DIR/resources/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
HELPER_ID="$BUNDLE_ID.pmset-helper"
HELPER_OUTPUT="$ROOT_DIR/dist/$HELPER_ID"
APP_SIGN_ID="${APP_SIGN_ID:--}"

if [[ "$BUNDLE_ID" != "com.github.oonishidaichi.capsomnia" ]]; then
  echo "Unexpected bundle identifier: $BUNDLE_ID" >&2
  exit 78
fi

/usr/bin/swift build -c release >&2
/bin/mkdir -p "$ROOT_DIR/dist"
/usr/bin/install -m 0755 "$ROOT_DIR/.build/release/$HELPER_ID" "$HELPER_OUTPUT"

# Remove staging metadata before signing. Signed output is never mutated afterward.
/usr/bin/xattr -cr "$HELPER_OUTPUT"

if [[ "$APP_SIGN_ID" == "-" ]]; then
  /usr/bin/codesign --force --options runtime --identifier "$HELPER_ID" \
    --sign - "$HELPER_OUTPUT"
else
  /usr/bin/codesign --force --options runtime --timestamp --identifier "$HELPER_ID" \
    --sign "$APP_SIGN_ID" "$HELPER_OUTPUT"
fi

/usr/bin/codesign --verify --all-architectures --strict --verbose=2 "$HELPER_OUTPUT"
SIGNED_ID="$(/usr/bin/codesign -dvv "$HELPER_OUTPUT" 2>&1 \
  | /usr/bin/awk -F= '$1 == "Identifier" { print $2; exit }')"
if [[ "$SIGNED_ID" != "$HELPER_ID" ]]; then
  echo "Signed helper identifier mismatch: $SIGNED_ID" >&2
  exit 78
fi

echo "$HELPER_OUTPUT"
