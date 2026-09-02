{{- /* PaperMC Fill v3 build lookup. v2 is sunset and answers
       {"ok":false,"error":"sunset"}. Shared by paper-check and paper-upgrade. */ -}}
# Latest stable build for a Minecraft version: "<build> <sha256> <filename>".
# Empty when the API is unreachable or the version does not exist.
paper_latest() { # version
    curl -fsSL --max-time 15 \
        "https://fill.papermc.io/v3/projects/paper/versions/$1/builds/latest" 2>/dev/null |
    python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    dl = d["downloads"]["server:default"]
    print(d["id"], dl["checksums"]["sha256"], dl["name"])
except Exception:
    sys.exit(1)
' 2>/dev/null || true
}
