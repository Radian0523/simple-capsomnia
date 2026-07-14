run_as_administrator() {
  local command="$1"

  /usr/bin/osascript \
    -e 'on run argv' \
    -e 'do shell script (item 1 of argv) with administrator privileges' \
    -e 'end run' \
    "$command"
}
