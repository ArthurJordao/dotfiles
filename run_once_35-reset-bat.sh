#!/bin/bash
# bat now uses the built-in `ansi` theme, so it follows the terminal palette and
# the custom theme dir is dead weight. An incompatible cache left behind by an
# older bat makes every invocation error, so clear it too.
set -euo pipefail

command -v bat >/dev/null 2>&1 || exit 0

rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/bat/themes"
bat cache --clear >/dev/null 2>&1 || true
