#!/bin/bash
set -euo pipefail

FISH="$(command -v fish || true)"
if [ -z "$FISH" ]; then
    echo "fish is not installed yet — skipping default-shell change."
    echo "Re-run 'chezmoi apply' after packages are installed, or run: chsh -s \"\$(command -v fish)\""
    exit 0
fi

# chsh refuses a shell that is not listed in /etc/shells.
if ! grep -qxF "$FISH" /etc/shells; then
    echo "Registering $FISH in /etc/shells"
    echo "$FISH" | sudo tee -a /etc/shells > /dev/null
fi

# Resolved, not literal: /bin/fish and /usr/bin/fish are the same binary.
if [ "$(readlink -f "$SHELL")" != "$(readlink -f "$FISH")" ]; then
    echo "Setting login shell to $FISH"
    chsh -s "$FISH"
else
    echo "Login shell already $FISH"
fi
