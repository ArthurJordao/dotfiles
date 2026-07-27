#!/bin/bash
set -euo pipefail

# Check if key is already imported
if gpg --list-secret-keys D62340DADE749208 &>/dev/null; then
    echo "GPG key already imported"
    exit 0
fi

echo "Importing GPG key from 1Password..."
op document get gpg-key --vault dotfiles > /tmp/gpg-import.asc
gpg --import /tmp/gpg-import.asc
rm -f /tmp/gpg-import.asc
echo "GPG key imported successfully"
