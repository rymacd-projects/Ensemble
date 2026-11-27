#!/bin/bash
# Turns on automatic updates. A small background job checks GitHub every couple of minutes.
# When there is a new version it builds it quietly, then closes Ensemble (saving first),
# updates it and reopens it. Turn it off again with scripts/disable-auto-update.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

STATE="$HOME/Library/Application Support/EnsembleUpdater"
CLONE="$STATE/repo"
PLIST="$HOME/Library/LaunchAgents/com.ensemble.updater.plist"
mkdir -p "$STATE" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

# The updater works in its own copy of the code, outside Documents, so macOS doesn't
# block a background job from reading it.
URL="$(git remote get-url origin)"
if [ ! -d "$CLONE/.git" ]; then
  git clone --quiet "$URL" "$CLONE"
fi

# The version that was just installed.
git rev-parse HEAD > "$STATE/installed_sha"
rm -f "$STATE/failed_sha"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.ensemble.updater</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$CLONE/scripts/auto-update.sh</string>
  </array>
  <key>StartInterval</key>
  <integer>120</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Automatic updates are on. New versions install within a few minutes of being published."
echo "(Log: ~/Library/Logs/Ensemble-update.log)"
