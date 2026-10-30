#!/usr/bin/env bash
# Launches the simulator build in screenshot mode and captures each main screen.
# Usage: .github/scripts/screenshots.sh path/to/Fairway.app output-dir
set -uo pipefail

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

# A fresh simulator can stay busy (data migration) for a while after booting, which makes
# the first launches time out. Warm up with one patient launch before capturing anything.
for attempt in 1 2 3; do
  if limit 180 xcrun simctl launch "$UDID" "$BUNDLE_ID" -FairwayScreen home >/dev/null; then
    sleep 10
    limit 120 xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    log "Warmed up"
    break
  fi
  log "Warm-up launch $attempt timed out; waiting"
  sleep 30
done

reboot_simulator() {
  log "Rebooting simulator"
  limit 120 xcrun simctl shutdown "$UDID" || true
  limit 60 xcrun simctl boot "$UDID" || true
  limit 600 xcrun simctl bootstatus "$UDID" -b || true
  limit 30 xcrun simctl location "$UDID" set 51.447495,-0.263080 || true
}

hangs=()
previous="(start)"
# Map-heavy screens last, so a rendering hang can't cost the others.
for screen in onboarding home setup round lobby teams match tournament results teamresults trophies rules play stats h2h handicap compete profile imperial course map replay; do
  # terminate fails harmlessly when the app isn't running; exit 142 means it timed out (hung).
  limit 30 xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null
  status=$?
  if [ "$status" -eq 142 ]; then
    log "app hung after $previous"
    hangs+=("$previous")
    reboot_simulator
  fi
  if ! limit 60 xcrun simctl launch "$UDID" "$BUNDLE_ID" -FairwayScreen "$screen" >/dev/null; then
    log "launch of $screen failed"
    hangs+=("$screen")
    reboot_simulator
    continue
  fi
  case "$screen" in
    lobby|map|course|replay) sleep 12 ;;
    match|tournament) sleep 16 ;;
    *) sleep 8 ;;
  esac
  limit 60 xcrun simctl io "$UDID" screenshot "$OUT/$screen.png" >/dev/null || log "screenshot of $screen failed"
  log "captured $screen"
  previous="$screen"
done

if [ ${#hangs[@]} -gt 0 ]; then
  echo "::warning::Simulator became unresponsive after: ${hangs[*]}"
fi

# Fail loudly if the app crashed during any capture.
if ls ~/Library/Logs/DiagnosticReports/Fairway* >/dev/null 2>&1; then
  echo "::error::Fairway crashed in the simulator"
  head -80 ~/Library/Logs/DiagnosticReports/Fairway* || true
  exit 1
fi
