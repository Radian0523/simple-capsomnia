#!/bin/zsh
set -euo pipefail

APP_NAME="Capsomnia"
ROOT_DIR="${0:A:h:h}"
source "$ROOT_DIR/scripts/admin-authorization.zsh"
INFO_PLIST="$ROOT_DIR/resources/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
HELPER_ID="$BUNDLE_ID.pmset-helper"
HELPER_PATH="/Library/PrivilegedHelperTools/$HELPER_ID"
SUDOERS_PATH="/etc/sudoers.d/capsomnia_oonishidaichi"
IGNORED_SUDOERS_PATH="/etc/sudoers.d/$BUNDLE_ID"
SYSTEM_APP="/Applications/$APP_NAME.app"
SYSTEM_AGENT="/Library/LaunchAgents/$BUNDLE_ID.plist"
CURRENT_USER="$(/usr/bin/id -un)"
CURRENT_UID="$(/usr/bin/id -u)"
SERVICE="gui/$CURRENT_UID/$BUNDLE_ID"
APP_BUNDLE="$HOME/Applications/$APP_NAME.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
LOG_DIR="$HOME/Library/Logs/$APP_NAME"
AGENT_REPORTER="$APP_BUNDLE/Contents/MacOS/CapsomniaAgentReporter"
ENABLE_AGENT_ACTIVITY="${ENABLE_AGENT_ACTIVITY:-0}"

service_pid() {
  /bin/launchctl print "$SERVICE" 2>/dev/null \
    | /usr/bin/awk '$1 == "pid" && $2 == "=" { print $3; exit }'
}

wait_for_service_exit() {
  for _ in {1..70}; do
    if ! /bin/launchctl print "$SERVICE" >/dev/null 2>&1; then
      return 0
    fi
    /bin/sleep 0.1
  done
  return 1
}

if [[ "$BUNDLE_ID" != "com.github.oonishidaichi.capsomnia" ]]; then
  echo "Unexpected bundle identifier: $BUNDLE_ID" >&2
  exit 78
fi
if [[ "$CURRENT_USER" == "root" || "$CURRENT_USER" == *[!A-Za-z0-9._-]* ]]; then
  echo "Unsupported installer user: $CURRENT_USER" >&2
  exit 64
fi
if [[ "$ENABLE_AGENT_ACTIVITY" != "0" && "$ENABLE_AGENT_ACTIVITY" != "1" ]]; then
  echo "ENABLE_AGENT_ACTIVITY must be 0 or 1." >&2
  exit 64
fi

UPSTREAM_PATHS=(
  "/Library/PrivilegedHelperTools/capsomnia-pmset"
  "/usr/local/sbin/capsomnia-pmset"
  "/etc/sudoers.d/capsomnia"
  "/Library/LaunchAgents/com.github.fuji-mak.capsomnia.plist"
  "$HOME/Library/LaunchAgents/com.github.fuji-mak.capsomnia.plist"
)
for path in "${UPSTREAM_PATHS[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then
    echo "Conflicting upstream artifact found; uninstall it first: $path" >&2
    exit 73
  fi
done

if [[ -e "$SYSTEM_APP" || -L "$SYSTEM_APP" ]]; then
  echo "A system-wide Capsomnia app exists; remove it before local install: $SYSTEM_APP" >&2
  exit 73
fi
if [[ -e "$SYSTEM_AGENT" || -L "$SYSTEM_AGENT" ]]; then
  echo "A system LaunchAgent exists; remove it before local install: $SYSTEM_AGENT" >&2
  exit 73
fi
if [[ -e "$APP_BUNDLE" ]]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$EXISTING_ID" != "$BUNDLE_ID" ]]; then
    echo "Refusing to replace app with a different bundle identifier: $EXISTING_ID" >&2
    exit 73
  fi
fi

BUILT_APP="$(BUILD_FLAVOR=development APP_SIGN_ID=- "$ROOT_DIR/scripts/build-app.sh")"
BUILT_HELPER="$(APP_SIGN_ID=- "$ROOT_DIR/scripts/build-helper.sh")"
/usr/bin/codesign --verify --all-architectures --deep --strict "$BUILT_APP"
/usr/bin/codesign --verify --all-architectures --strict "$BUILT_HELPER"

SUDOERS_TMP="$(/usr/bin/mktemp)"
AGENT_TMP="$(/usr/bin/mktemp)"
cleanup() {
  /bin/rm -f "$SUDOERS_TMP" "$AGENT_TMP"
}
trap cleanup EXIT

/bin/mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$LOG_DIR"

for directory in "/Library/PrivilegedHelperTools" "/etc/sudoers.d"; do
  if [[ ! -d "$directory" ]]; then
    echo "Required privileged directory is missing: $directory" >&2
    exit 77
  fi
  OWNER="$(/usr/bin/stat -f '%u:%g' "$directory")"
  MODE="$(/usr/bin/stat -f '%Lp' "$directory")"
  if [[ "$OWNER" != "0:0" ]] || (( (8#$MODE & 8#022) != 0 )); then
    echo "Unsafe privileged directory: $directory owner=$OWNER mode=$MODE" >&2
    exit 77
  fi
done

if [[ -x "$HELPER_PATH" ]]; then
  /usr/bin/sudo -n "$HELPER_PATH" off >/dev/null 2>&1 || true
fi
/bin/launchctl bootout "$SERVICE" 2>/dev/null || true
if ! wait_for_service_exit; then
  OLD_PID="$(service_pid)"
  if [[ "$OLD_PID" == <-> ]]; then
    /bin/kill -KILL "$OLD_PID" 2>/dev/null || true
  fi
  wait_for_service_exit || {
    echo "Existing Capsomnia service did not stop." >&2
    exit 70
  }
fi

/bin/rm -rf "$APP_BUNDLE"
/usr/bin/ditto "$BUILT_APP" "$APP_BUNDLE"
/usr/bin/codesign --verify --all-architectures --deep --strict "$APP_BUNDLE"

if [[ "$ENABLE_AGENT_ACTIVITY" == "1" ]]; then
  "$AGENT_REPORTER" install-hooks
  /usr/bin/defaults write "$BUNDLE_ID" agentActivityEnabled -bool true
fi

HELPER_DIGEST="$(/usr/bin/shasum -a 256 "$BUILT_HELPER" | /usr/bin/awk '{print $1}')"

/bin/cat > "$SUDOERS_TMP" <<EOF
# Capsomnia: allow only the signed fixed pmset helper commands.
$CURRENT_USER ALL=(root) NOPASSWD: sha256:$HELPER_DIGEST $HELPER_PATH on
$CURRENT_USER ALL=(root) NOPASSWD: sha256:$HELPER_DIGEST $HELPER_PATH off
$CURRENT_USER ALL=(root) NOPASSWD: sha256:$HELPER_DIGEST $HELPER_PATH display-sleep
EOF
/usr/sbin/visudo -cf "$SUDOERS_TMP"

for value in "$BUILT_HELPER" "$HELPER_PATH" "$SUDOERS_TMP" "$SUDOERS_PATH" \
  "$IGNORED_SUDOERS_PATH" "$HELPER_DIGEST"; do
  if [[ ! "$value" =~ '^[A-Za-z0-9._/-]+$' ]]; then
    echo "Unsafe value passed to administrator command: $value" >&2
    exit 64
  fi
done

echo "macOS will request administrator approval for the fixed helper and sudoers rule."
PRIVILEGED_INSTALL_COMMAND="
set -eu
source_digest=\$(/usr/bin/shasum -a 256 '$BUILT_HELPER' | /usr/bin/cut -d ' ' -f 1)
[ \"\$source_digest\" = '$HELPER_DIGEST' ]
/usr/bin/install -o root -g wheel -m 0755 '$BUILT_HELPER' '$HELPER_PATH'
installed_digest=\$(/usr/bin/shasum -a 256 '$HELPER_PATH' | /usr/bin/cut -d ' ' -f 1)
[ \"\$installed_digest\" = '$HELPER_DIGEST' ]
/usr/sbin/visudo -cf '$SUDOERS_TMP'
/bin/rm -f '$IGNORED_SUDOERS_PATH'
/usr/bin/install -o root -g wheel -m 0440 '$SUDOERS_TMP' '$SUDOERS_PATH'
/usr/sbin/visudo -cf '$SUDOERS_PATH'
/usr/bin/cmp -s '$SUDOERS_TMP' '$SUDOERS_PATH'
"
run_as_administrator "$PRIVILEGED_INSTALL_COMMAND" >/dev/null

/usr/bin/codesign --verify --all-architectures --strict "$HELPER_PATH"
INSTALLED_HELPER_DIGEST="$(/usr/bin/shasum -a 256 "$HELPER_PATH" | /usr/bin/awk '{print $1}')"
if [[ "$INSTALLED_HELPER_DIGEST" != "$HELPER_DIGEST" ]]; then
  echo "Installed helper digest does not match the approved build." >&2
  exit 77
fi

/bin/cat > "$AGENT_TMP" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$BUNDLE_ID</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_BUNDLE/Contents/MacOS/$APP_NAME</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/launchd-stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/launchd-stderr.log</string>
</dict>
</plist>
EOF
/usr/bin/plutil -lint "$AGENT_TMP"
/usr/bin/install -m 0644 "$AGENT_TMP" "$LAUNCH_AGENT"

/bin/launchctl bootstrap "gui/$CURRENT_UID" "$LAUNCH_AGENT"
/bin/launchctl enable "$SERVICE"
/bin/sleep 1
/bin/launchctl print "$SERVICE" >/dev/null

echo "Installed $APP_NAME for $CURRENT_USER."
echo "App: $APP_BUNDLE"
echo "Helper: $HELPER_PATH"
echo "Helper SHA-256: $HELPER_DIGEST"
echo "Sudoers: $SUDOERS_PATH"
echo "LaunchAgent: $LAUNCH_AGENT"
if [[ "$ENABLE_AGENT_ACTIVITY" == "1" ]]; then
  echo "Agent Activity: enabled for Codex and Claude Code"
  echo "Codex approval: review the Capsomnia reporter commands in /hooks before they can run"
fi
