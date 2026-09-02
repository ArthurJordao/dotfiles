{{- /* Download and verify one Paper jar. Used only by paper-upgrade. */ -}}
# Fetch a build to a destination, verifying the sha256 the API reported. Guards
# a corrupt or truncated download, not a compromised API.
paper_fetch() { # sha256 filename dest
    local want="$1" name="$2" dest="$3" got
    curl -fsSL --retry 2 --max-time 300 -o "$dest" \
        "https://fill-data.papermc.io/v1/objects/$want/$name" || return 1
    got=$(sha256sum "$dest" | cut -d' ' -f1)
    if [ "$got" != "$want" ]; then
        echo "  sha256 mismatch: wanted $want, got $got" >&2
        rm -f "$dest"
        return 1
    fi
}
