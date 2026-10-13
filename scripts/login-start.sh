#!/bin/zsh
set -eu
cd "${0:A:h:h}"
label=local.touchbar-tool.login
agent="$HOME/Library/LaunchAgents/$label.plist"
app="$PWD/build/TouchbarTool.app"
domain="gui/$(id -u)"
case "${1:-status}" in
  enable)
    [[ -d "$app" ]] || { print -u2 'Build the App first'; exit 1; }
    [[ ! -e "$agent" ]] || { print -u2 'Existing login plist will not be overwritten; inspect or disable first'; exit 1; }
    mkdir -p "${agent:h}"
    /usr/bin/python3 - "$agent" "$app" "$label" <<'PY'
import plistlib, sys
from pathlib import Path
path, app, label = sys.argv[1:]
with Path(path).open('xb') as stream:
    plistlib.dump({'Label': label, 'ProgramArguments': ['/usr/bin/open', '-g', app],
                  'RunAtLoad': True, 'LimitLoadToSessionType': 'Aqua'}, stream)
Path(path).chmod(0o644)
PY
    plutil -lint "$agent"
    launchctl bootstrap "$domain" "$agent"
    print 'Login startup enabled for current user only; quit remains effective (no KeepAlive).'
    ;;
  disable)
    if [[ -e "$agent" ]]; then
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$agent")" == "$label" ]] || { print -u2 'Unexpected plist; refusing to modify'; exit 1; }
      launchctl bootout "$domain/$label" 2>/dev/null || true
      rm "$agent"
    fi
    print 'Login startup disabled; running App is not terminated.'
    ;;
  status)
    if [[ -e "$agent" ]]; then
      plutil -lint "$agent"
      launchctl print "$domain/$label"
    else
      print 'Login startup is not configured.'
    fi
    ;;
  *) print -u2 'Usage: scripts/login-start.sh enable|disable|status'; exit 2 ;;
esac
