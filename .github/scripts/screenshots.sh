#!/usr/bin/env bash
# Launches the simulator build in screenshot mode and captures each main screen.
# Usage: .github/scripts/screenshots.sh path/to/Fairway.app output-dir
set -euo pipefail

APP="$1"
OUT="$2"
BUNDLE_ID="io.github.ctibballs.fairway"
mkdir -p "$OUT"

# Run a command with a time limit (macOS has no `timeout`).
limit() { local seconds="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"; }
log() { echo "[$(date +%H:%M:%S)] $*"; }

# Pick the newest available iPhone simulator, preferring a Pro model.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
runtimes = sorted((k for k in devices if "iOS" in k), reverse=True)
for runtime in runtimes:
    phones = [d for d in devices[runtime] if d["name"].startswith("iPhone")]
    pros = [d for d in phones if "Pro" in d["name"] and "Max" not in d["name"]]
    pick = (pros or phones)
    if pick:
        print(pick[0]["udid"]); break
')
log "Using simulator $UDID"
limit 60 xcrun simctl boot "$UDID" || true
log "Waiting for boot"
limit 600 xcrun simctl bootstatus "$UDID" -b
log "Booted"
limit 30 xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
limit 120 xcrun simctl install "$UDID" "$APP"
log "Installed"
limit 30 xcrun simctl privacy "$UDID" grant location "$BUNDLE_ID" || true
# Stand on the fairway of demo hole 4 so distances show up.
limit 30 xcrun simctl location "$UDID" set 51.447495,-0.263080 || true

for screen in onboarding home round lobby match tournament play course map replay stats h2h handicap compete profile imperial; do
  limit 30 xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  limit 60 xcrun simctl launch "$UDID" "$BUNDLE_ID" -FairwayScreen "$screen" >/dev/null
  case "$screen" in
    lobby|map|course|replay) sleep 12 ;;
    match|tournament) sleep 16 ;;
    *) sleep 8 ;;
  esac
  limit 60 xcrun simctl io "$UDID" screenshot "$OUT/$screen.png" >/dev/null
  log "captured $screen"
done

# Fail loudly if the app crashed during any capture.
if ls ~/Library/Logs/DiagnosticReports/Fairway* >/dev/null 2>&1; then
  echo "::error::Fairway crashed in the simulator"
  head -80 ~/Library/Logs/DiagnosticReports/Fairway* || true
  exit 1
fi
