#!/bin/sh
# Installs the 1Password CLI if it is missing.
#
# Wired as chezmoi's hooks.read-source-state.pre, so templates calling
# onepasswordRead always find `op` present. It runs on EVERY source-state read,
# not just apply -- keep the happy path to a single `command -v`.
#
# NOT a template: hooks run before the template machinery exists, hence uname.
# The leading dot keeps chezmoi from managing this file as a target.

set -eu

command -v op >/dev/null 2>&1 && exit 0

echo "1Password CLI not found; installing it before reading source state." >&2

case "$(uname -s)" in
    Darwin)
        # A cask, not a formula: `brew install 1password-cli` fails with
        # "No available formula with the name".
        brew install --cask 1password-cli
        ;;
    Linux)
        # AUR-only, so paru rather than pacman. CachyOS ships paru.
        paru -S --needed --noconfirm 1password-cli
        ;;
    *)
        echo "Unsupported OS $(uname -s); install the 1Password CLI manually." >&2
        exit 1
        ;;
esac
