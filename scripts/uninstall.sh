#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
source "$ROOT_DIR/scripts/admin-authorization.zsh"

APP_NAME="Capsomnia"
BUNDLE_ID="com.github.oonishidaichi.capsomnia"
HELPER_PATH="/Library/PrivilegedHelperTools/$BUNDLE_ID.pmset-helper"
SUDOERS_PATH="/etc/sudoers.d/capsomnia_oonishidaichi"
IGNORED_SUDOERS_PATH="/etc/sudoers.d/$BUNDLE_ID"
CURRENT_UID="$(/usr/bin/id -u)"
SERVICE="gui/$CURRENT_UID/$BUNDLE_ID"
APP_BUNDLE="$HOME/Applications/$APP_NAME.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
AGENT_REPORTER="$APP_BUNDLE/Contents/MacOS/CapsomniaAgentReporter"
AGENT_ACTIVITY_DIR="$HOME/Library/Application Support/$APP_NAME/AgentActivity"

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

if [[ -e "$APP_BUNDLE" ]]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$EXISTING_ID" != "$BUNDLE_ID" ]]; then
    echo "Refusing to remove app with a different bundle identifier: $EXISTING_ID" >&2
    exit 73
  fi
fi

if [[ -x "$HELPER_PATH" ]]; then
  /usr/bin/sudo -n "$HELPER_PATH" off 2>/dev/null || true
fi

if [[ -x "$AGENT_REPORTER" ]]; then
  "$AGENT_REPORTER" remove-hooks
fi

/bin/launchctl bootout "$SERVICE" 2>/dev/null || true
if ! wait_for_service_exit; then
  OLD_PID="$(service_pid)"
  if [[ "$OLD_PID" == <-> ]]; then
    /bin/kill -KILL "$OLD_PID" 2>/dev/null || true
  fi
  wait_for_service_exit || {
    echo "Capsomnia service did not stop." >&2
    exit 70
  }
fi

/bin/rm -f "$LAUNCH_AGENT"
/bin/rm -rf "$APP_BUNDLE"
/bin/rm -rf "$AGENT_ACTIVITY_DIR"
/usr/bin/defaults delete "$BUNDLE_ID" agentActivityEnabled 2>/dev/null || true

echo "macOS will request administrator approval to restore sleep and remove Capsomnia's privileged files."
PRIVILEGED_UNINSTALL_COMMAND="
set -eu
/usr/bin/pmset -a disablesleep 0
/bin/rm -f '$HELPER_PATH' '$SUDOERS_PATH' '$IGNORED_SUDOERS_PATH'
"
run_as_administrator "$PRIVILEGED_UNINSTALL_COMMAND" >/dev/null

SLEEP_DISABLED="$(/usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" { print $2; exit }')"
if [[ "$SLEEP_DISABLED" != "0" ]]; then
  echo "Failed to restore normal sleep; SleepDisabled=$SLEEP_DISABLED" >&2
  exit 70
fi

echo "Uninstalled $APP_NAME and restored normal sleep."
