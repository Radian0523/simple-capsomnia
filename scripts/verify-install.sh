#!/bin/zsh
set -euo pipefail

APP_NAME="Capsomnia"
BUNDLE_ID="com.github.oonishidaichi.capsomnia"
HELPER_PATH="/Library/PrivilegedHelperTools/$BUNDLE_ID.pmset-helper"
SUDOERS_PATH="/etc/sudoers.d/capsomnia_oonishidaichi"
CURRENT_UID="$(/usr/bin/id -u)"
APP_BUNDLE="$HOME/Applications/$APP_NAME.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
AGENT_REPORTER="$APP_BUNDLE/Contents/MacOS/CapsomniaAgentReporter"

/usr/bin/codesign --verify --all-architectures --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/codesign --verify --all-architectures --strict --verbose=2 "$AGENT_REPORTER"
/usr/bin/codesign --verify --all-architectures --strict --verbose=2 "$HELPER_PATH"

HELPER_OWNER_MODE="$(/usr/bin/stat -f '%u:%g:%Lp' "$HELPER_PATH")"
if [[ "$HELPER_OWNER_MODE" != "0:0:755" ]]; then
  echo "Unexpected helper owner/mode: $HELPER_OWNER_MODE" >&2
  exit 77
fi

SUDOERS_OWNER_MODE="$(/usr/bin/stat -f '%u:%g:%Lp' "$SUDOERS_PATH")"
if [[ "$SUDOERS_OWNER_MODE" != "0:0:440" ]]; then
  echo "Unexpected sudoers owner/mode: $SUDOERS_OWNER_MODE" >&2
  exit 77
fi

HELPER_DIGEST="$(/usr/bin/shasum -a 256 "$HELPER_PATH" | /usr/bin/awk '{print $1}')"

/usr/bin/sudo -n -l "$HELPER_PATH" on >/dev/null
/usr/bin/sudo -n -l "$HELPER_PATH" off >/dev/null
/usr/bin/sudo -n -l "$HELPER_PATH" display-sleep >/dev/null

/usr/bin/plutil -lint "$LAUNCH_AGENT"
/bin/launchctl print "gui/$CURRENT_UID/$BUNDLE_ID" >/dev/null

if [[ "$(/usr/bin/defaults read "$BUNDLE_ID" agentActivityEnabled 2>/dev/null || true)" == "1" ]]; then
  if [[ "$("$AGENT_REPORTER" status)" != "enabled" ]]; then
    echo "Agent Activity is enabled but its hooks are not configured." >&2
    exit 77
  fi
fi

echo "Installation verified."
echo "Helper SHA-256: $HELPER_DIGEST"
/usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" { print "SleepDisabled=" $2; exit }'
