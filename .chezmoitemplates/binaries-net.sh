{{- /* The upstream lookup, used only by binaries-check. */ -}}
# The newest release upstream, or empty if GitHub cannot be reached.
# Unauthenticated, which is 60 requests an hour per IP -- ample for a daily
# check over a handful of repos.
bin_latest() { # repo
    curl -fsSL --max-time 10 "https://api.github.com/repos/$1/releases/latest" 2>/dev/null |
        grep -oE '"tag_name": *"[^"]*"' | head -1 |
        sed -e 's/.*"tag_name": *"//' -e 's/"$//' -e 's/^v//' || true
}
