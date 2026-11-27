#!/bin/bash
# Builds Ensemble and installs it to /Applications, with a shortcut on your Desktop.
# Safe to run again any time (that's also how you update).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Ensemble installer"

# 1. Xcode (needed to compile the app)
if ! xcodebuild -version >/dev/null 2>&1; then
  echo ""
  echo "Xcode is required but wasn't found."
  echo "Install it free from the Mac App Store, open it once so it can finish setup, then run this again."
  exit 1
fi

# 2. XcodeGen (creates the Xcode project from project.yml)
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "==> Installing XcodeGen with Homebrew"
    brew install xcodegen
  else
    echo ""
    echo "Homebrew isn't installed. Install it from https://brew.sh, then run this again."
    exit 1
  fi
fi

echo "==> Generating the Xcode project"
xcodegen generate

echo "==> Building Ensemble (this takes a minute or two the first time)"
xcodebuild -project Ensemble.xcodeproj \
  -scheme Ensemble \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  build | tail -n 5

APP="build/Build/Products/Release/Ensemble.app"
if [ ! -d "$APP" ]; then
  echo "Build finished but Ensemble.app wasn't found. Scroll up for the error."
  exit 1
fi

echo "==> Installing to /Applications"
osascript -e 'tell application "Ensemble" to quit' >/dev/null 2>&1 || true
rm -rf /Applications/Ensemble.app
ditto "$APP" /Applications/Ensemble.app

echo "==> Adding a shortcut to your Desktop"
rm -f "$HOME/Desktop/Ensemble"
osascript -e 'tell application "Finder" to make new alias file to POSIX file "/Applications/Ensemble.app" at desktop' >/dev/null 2>&1 \
  || ln -sf /Applications/Ensemble.app "$HOME/Desktop/Ensemble"

echo "==> Turning on automatic updates"
bash scripts/enable-auto-update.sh || echo "(Couldn't turn on automatic updates. Ensemble is installed and works fine.)"

echo ""
echo "Done! Ensemble is in your Applications folder and on your Desktop."
echo "From now on, just double-click it. No Terminal needed."
open /Applications/Ensemble.app
