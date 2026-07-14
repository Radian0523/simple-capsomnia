#!/bin/zsh
set -euo pipefail

BUNDLE_ID="com.github.oonishidaichi.capsomnia"
HELPER_PATH="/Library/PrivilegedHelperTools/$BUNDLE_ID.pmset-helper"
CURRENT_UID="$(/usr/bin/id -u)"
SERVICE="gui/$CURRENT_UID/$BUNDLE_ID"
LOG_PATH="$HOME/Library/Logs/Capsomnia/capsomnia.log"

sleep_disabled() {
  /usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" { print $2; exit }'
}

service_pid() {
  /bin/launchctl print "$SERVICE" 2>/dev/null \
    | /usr/bin/awk '$1 == "pid" && $2 == "=" { print $3; exit }'
}

restore() {
  /usr/bin/sudo -n "$HELPER_PATH" off >/dev/null 2>&1 || true
  if [[ -z "$(service_pid)" ]]; then
    /bin/launchctl kickstart "$SERVICE" >/dev/null 2>&1 || true
  fi
}
trap restore EXIT

PID="$(service_pid)"
if [[ -z "$PID" ]]; then
  echo "Capsomnia LaunchAgent is not running." >&2
  exit 69
fi

LOG_LINES=0
if [[ -f "$LOG_PATH" ]]; then
  LOG_LINES="$(/usr/bin/wc -l < "$LOG_PATH" | /usr/bin/tr -d ' ')"
fi

/usr/bin/sudo -n "$HELPER_PATH" on
if [[ "$(sleep_disabled)" != "1" ]]; then
  echo "Helper did not enable SleepDisabled." >&2
  exit 70
fi

/bin/kill -TERM "$PID"

for _ in {1..50}; do
  if [[ "$(sleep_disabled)" == "0" ]] && [[ -z "$(service_pid)" ]]; then
    break
  fi
  /bin/sleep 0.1
done

if [[ "$(sleep_disabled)" != "0" ]]; then
  echo "Capsomnia did not restore SleepDisabled=0 during termination." >&2
  exit 70
fi
if [[ -n "$(service_pid)" ]]; then
  echo "Capsomnia did not terminate cleanly." >&2
  exit 70
fi

if ! /usr/bin/tail -n "+$((LOG_LINES + 1))" "$LOG_PATH" \
  | /usr/bin/grep -q 'event=terminate_restore mode=off status=0'; then
  echo "Successful termination restore was not logged." >&2
  exit 70
fi

/bin/launchctl kickstart "$SERVICE"
for _ in {1..50}; do
  if [[ -n "$(service_pid)" ]]; then
    break
  fi
  /bin/sleep 0.1
done

if [[ -z "$(service_pid)" ]]; then
  echo "Capsomnia did not restart after the termination test." >&2
  exit 70
fi

trap - EXIT
echo "Runtime test passed: helper on, termination restore off, LaunchAgent restart."
