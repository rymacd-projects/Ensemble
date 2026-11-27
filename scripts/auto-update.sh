#!/bin/bash
# Background updater for Ensemble (turned on by scripts/enable-auto-update.sh).
# Every couple of minutes it checks GitHub. When there is a newer version it builds it quietly,
# then closes Ensemble (which saves first), swaps in the new app and reopens it.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$HOME/Library/Application Support/EnsembleUpdater"
LOG="$HOME/Library/Logs/Ensemble-update.log"
mkdir -p "$STATE" "$(dirname "$LOG")"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# Only one updater at a time (a lock left behind by a crash is cleared after 45 minutes).
LOCK="$STATE/lock"
find "$LOCK" -maxdepth 0 -mmin +45 -exec rmdir {} \; 2>/dev/null
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

cd "$REPO" || exit 0
git fetch --quiet origin main 2>>"$LOG" || exit 0
REMOTE="$(git rev-parse origin/main)"
INSTALLED="$(cat "$STATE/installed_sha" 2>/dev/null || true)"
FAILED="$(cat "$STATE/failed_sha" 2>/dev/null || true)"
[ "$REMOTE" = "$INSTALLED" ] && exit 0
[ "$REMOTE" = "$FAILED" ] && exit 0   # that version didn't build; wait for the next one

log "New version $REMOTE found. Building."
git checkout --quiet -f main 2>>"$LOG"
git reset --hard --quiet origin/main 2>>"$LOG" || { log "Could not get the new code."; exit 0; }

fail() { echo "$REMOTE" > "$STATE/failed_sha"; log "$1 Keeping the current version."; exit 0; }

xcodegen generate >>"$LOG" 2>&1 || fail "XcodeGen failed."
xcodebuild -project Ensemble.xcodeproj \
  -scheme Ensemble \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  build >>"$LOG" 2>&1 || fail "Build failed."

NEW="$REPO/build/Build/Products/Release/Ensemble.app"
[ -d "$NEW" ] || fail "Built app not found."

# Close Ensemble politely. It saves your library when it quits.
WAS_RUNNING=0
if pgrep -x Ensemble >/dev/null; then
  WAS_RUNNING=1
  log "Closing Ensemble."
  pkill -TERM -x Ensemble
  for _ in $(seq 1 40); do
    pgrep -x Ensemble >/dev/null || break
    sleep 1
  done
  if pgrep -x Ensemble >/dev/null; then
    log "Ensemble didn't close. Will try again shortly."
    exit 0
  fi
fi

# Copy first, then swap, so there is never a moment with no app installed.
rm -rf /Applications/.Ensemble.new.app
ditto "$NEW" /Applications/.Ensemble.new.app || { log "Copy failed."; exit 0; }
rm -rf /Applications/Ensemble.app
mv /Applications/.Ensemble.new.app /Applications/Ensemble.app

echo "$REMOTE" > "$STATE/installed_sha"
rm -f "$STATE/failed_sha"
log "Updated to $REMOTE."

if [ "$WAS_RUNNING" = 1 ]; then
  open /Applications/Ensemble.app
  log "Reopened Ensemble."
fi
osascript -e 'display notification "Ensemble was updated to the newest version." with title "Ensemble"' >/dev/null 2>&1 || true
