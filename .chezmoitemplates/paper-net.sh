{{- /* PaperMC Fill v3 build lookup. v2 is sunset and answers
       {"ok":false,"error":"sunset"}. Shared by paper-check and paper-upgrade. */ -}}
# Memoised per version: instances usually share one pinned version, and asking
# twice for the same answer is what makes a rate-limited API report itself as
# unreachable. Only successes are cached, so a transient failure retries.
declare -A _paper_latest_cache

# Latest stable build for a Minecraft version: "<build> <sha256> <filename>".
# Empty when the API is unreachable or the version does not exist.
paper_latest() { # version
    local v="$1" out
    if [ -n "${_paper_latest_cache[$v]:-}" ]; then
        printf '%s\n' "${_paper_latest_cache[$v]}"
        return 0
    fi
    out=$(curl -fsSL --retry 2 --max-time 15 \
        "https://fill.papermc.io/v3/projects/paper/versions/$v/builds/latest" 2>/dev/null |
    python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    dl = d["downloads"]["server:default"]
    print(d["id"], dl["checksums"]["sha256"], dl["name"])
except Exception:
    sys.exit(1)
' 2>/dev/null) || out=""
    [ -n "$out" ] && _paper_latest_cache[$v]="$out"
    printf '%s\n' "$out"
}
