#!/bin/bash
# Turns automatic updates off. Ensemble keeps working; update by hand with "Update Ensemble.command".
PLIST="$HOME/Library/LaunchAgents/com.ensemble.updater.plist"
launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"
echo "Automatic updates are off."
