#!/bin/bash
# Pulls the latest Ensemble from GitHub and reinstalls it.
set -euo pipefail
cd "$(dirname "$0")/.."
git pull --ff-only
./scripts/install.sh
