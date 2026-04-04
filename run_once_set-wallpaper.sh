#!/bin/bash
set -euo pipefail
osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$HOME/Pictures/wallpaper.png\" as POSIX file"
