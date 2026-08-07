#!/bin/sh
# Installs the 1Password CLI if it is missing.
#
# Wired as chezmoi's hooks.read-source-state.pre, which runs after the repo is
# cloned but before chezmoi reads source state -- the only window in which a
# prerequisite can be installed for the same apply that needs it. Templates
# calling onepasswordRead therefore always find `op` present.
#
# NOT a template: hooks run before any template machinery exists, so the OS has
# to be detected with uname. The leading dot keeps chezmoi from treating this
# file as source state.
#
# This runs on EVERY source-state read -- `chezmoi data`, `execute-template`,
# `diff`, not just `apply`. Keep the happy path to a single `command -v`.

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
