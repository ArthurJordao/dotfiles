#!/bin/bash
set -euo pipefail

# Check if key is already imported
if gpg --list-secret-keys D62340DADE749208 &>/dev/null; then
    echo "GPG key already imported"
    exit 0
fi

echo "Importing GPG key from Bitwarden..."
ITEM_ID=$(bw get item gpg-key --raw | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
ATTACH_ID=$(bw get item gpg-key --raw | python3 -c "import json,sys; print(json.load(sys.stdin)['attachments'][0]['id'])")
bw get attachment "$ATTACH_ID" --itemid "$ITEM_ID" --output /tmp/gpg-import.asc
gpg --import /tmp/gpg-import.asc
rm -f /tmp/gpg-import.asc
echo "GPG key imported successfully"
