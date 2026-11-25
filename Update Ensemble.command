#!/bin/bash
cd "$(dirname "$0")"
bash scripts/update.sh
echo ""
read -n 1 -s -r -p "Press any key to close this window."
