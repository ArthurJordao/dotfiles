{{- /* Shared by run_onchange_after_10-install-packages.sh.tmpl and
       dot_local/scripts/executable_install-packages.tmpl.
       Callers add the shebang (bash: bin_install uses `local`).
       Set PROMPT=1 to ask before installing.
       Linux only: .local/scripts/install-packages is not deployed on darwin,
       so the brew path lives inline in the run_onchange script instead. */ -}}
{{- $roles := (index .hosts .hostname).roles -}}
{{- /* `index`, not `.distro`: a darwin host has no such key, and a bare field
       lookup errors under missingkey=error where index yields nil. */ -}}
{{- $family := (index (index .hosts .hostname) "distro" | default "") -}}
set -euo pipefail
{{ if eq $family "" -}}
echo "No 'distro' declared for {{ .hostname }} in .chezmoidata/hosts.yaml" >&2
exit 1
{{ else if not (hasKey .packages $family) -}}
echo "No packages declared for family {{ $family }} in .chezmoidata/packages.yaml" >&2
exit 1
{{ else -}}
{{- $fam := index .packages $family -}}
{{- $groups := prepend $roles "common" -}}

DECLARED=$(cat <<'PKGLIST'
{{ range $groups }}{{ if hasKey $fam . }}{{ range index $fam . }}{{ . }}
{{ end }}{{ end }}{{ end -}}
PKGLIST
)

if [ -z "$DECLARED" ]; then
    echo "No packages declared for groups: {{ $groups | join " " }}" >&2
    exit 0
fi

{{ if eq $family "arch" -}}
INSTALLED="$(pacman -Qq)"
{{ else -}}
INSTALLED="$(dpkg-query -W -f='${Package}\n')"
{{ end -}}

# The delta drives the prompt only, so it may be slightly over-inclusive (a
# package satisfied by another's `provides`). --needed is the real guard.
MISSING="$(comm -13 <(printf '%s\n' "$INSTALLED" | sort -u) \
                    <(printf '%s\n' "$DECLARED"  | sort -u))"

# PyPI tools with no distro package, declared under `pipx` rather than in a
# role group. Kept out of DECLARED: they are not apt/pacman names, so the comm
# delta above must never see them.
PIPX_MISSING=""   # one tool per line, like the BIN_* accumulators below
{{- range (index $fam "pipx" | default list) }}
command -v {{ . | quote }} >/dev/null 2>&1 || PIPX_MISSING="${PIPX_MISSING}{{ . }}
"
{{- end }}

{{ template "binaries.sh" . }}
{{ template "binaries-expand.sh" . }}
{{ template "binaries-install.sh" . }}

# Binaries split three ways: what this script can fetch, what takes minutes and
# so belongs to `just binaries-build`, and what it can only report. All three
# are silent when the pin matches what is installed.
BIN_OUTDATED=""   # name|repo|version|install|tag|asset|restart
BIN_BUILD=""      # one "name have -> want" line
BIN_MANUAL=""     # one "name have -> want" line
while IFS='|' read -r bname brepo bversion bkind btag basset bvercmd brestart _ _; do
    [ -n "$bname" ] || continue
    bhave=$(bin_installed "$bname" "$bkind" "$bvercmd")
    [ "$bhave" = "$bversion" ] && continue
    case "$bkind" in
        manual)
            BIN_MANUAL="${BIN_MANUAL}${bname} ${bhave:-absent} -> ${bversion}
" ;;
        local-build)
            BIN_BUILD="${BIN_BUILD}${bname} ${bhave:-absent} -> ${bversion}
" ;;
        *)
            BIN_OUTDATED="${BIN_OUTDATED}${bname}|${brepo}|${bversion}|${bkind}|${btag}|${basset}|${brestart}
" ;;
    esac
done <<BINEOF
$BINARIES
BINEOF

if [ -z "$MISSING" ] && [ -z "$PIPX_MISSING" ] && [ -z "$BIN_OUTDATED" ] && [ -z "$BIN_BUILD" ] && [ -z "$BIN_MANUAL" ]; then
    exit 0
fi

if [ -n "$MISSING" ]; then
    echo "Declared but not installed (family={{ $family }}):"
    printf '%s\n' "$MISSING" | sed 's/^/  /'
fi
if [ -n "$PIPX_MISSING" ]; then
    echo "Declared via pipx but not installed:"
    printf '%s' "$PIPX_MISSING" | sed 's/^/  /'
fi
if [ -n "$BIN_OUTDATED" ]; then
    echo "Binaries not at their pinned version:"
    printf '%s' "$BIN_OUTDATED" | while IFS='|' read -r bname _ bversion _; do
        [ -n "$bname" ] && echo "  $bname -> $bversion"
    done
fi
if [ -n "$BIN_BUILD" ]; then
    echo "Binaries needing a rebuild -- run 'just binaries-build' (takes minutes):"
    printf '%s' "$BIN_BUILD" | sed 's/^/  /'
fi
if [ -n "$BIN_MANUAL" ]; then
    echo "Pinned but built by hand -- rebuild these yourself (docs/unmanaged.md):"
    printf '%s' "$BIN_MANUAL" | sed 's/^/  /'
fi

# A build or a manual binary on its own leaves nothing for this script to do.
if [ -z "$MISSING" ] && [ -z "$PIPX_MISSING" ] && [ -z "$BIN_OUTDATED" ]; then
    exit 0
fi

if [ "${PROMPT:-0}" = "1" ]; then
    if [ ! -t 0 ]; then
        echo "Not a terminal -- skipping. Run 'just packages' (or ~/.local/scripts/install-packages on a first apply) to install." >&2
        exit 0
    fi
    printf 'Install these now? [y/N] '
    read -r reply || reply=n
    case "$reply" in
        [yY]*) ;;
        *) echo "Skipped. Run 'just packages' (or ~/.local/scripts/install-packages on a first apply) when ready."; exit 0 ;;
    esac
fi

if [ -n "$MISSING" ]; then
    LIST="$(mktemp)"
    trap 'rm -f "$LIST"' EXIT
    printf '%s\n' "$MISSING" > "$LIST"
{{ if eq $family "arch" -}}
    if ! paru -S --needed --noconfirm - < "$LIST"; then
        cat >&2 <<'HINT'

Package install failed. 404s while downloading mean a stale pacman database.
Fix with a full upgrade, which also re-runs this:

    just upgrade

HINT
        exit 1
    fi
{{ else -}}
    # Tailscale is not in Debian's archive; add its repo before installing.
    if grep -qx tailscale "$LIST" && [ ! -f /etc/apt/sources.list.d/tailscale.list ]; then
        codename="$(awk -F= '/^VERSION_CODENAME=/{print $2}' /etc/os-release)"
        curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.noarmor.gpg" \
            | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
        curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.tailscale-keyring.list" \
            | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
    fi
    # cloudflared is not in Debian's archive either.
    if grep -qx cloudflared "$LIST" && [ ! -f /etc/apt/sources.list.d/cloudflared.list ]; then
        curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
            | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
        echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" \
            | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
    fi
    sudo apt-get update
    xargs -a "$LIST" sudo apt-get install -y
{{ end -}}
fi

while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    echo "Installing $tool with pipx"
    # ~/.local/bin must be on PATH for the tool to be found afterwards;
    # `pipx ensurepath` is what fixes that, and it is not this script's job.
    pipx install "$tool" || echo "  $tool: pipx install failed" >&2
done <<PIPXEOF
$PIPX_MISSING
PIPXEOF

while IFS='|' read -r bname brepo bversion bkind btag basset brestart; do
    [ -n "$bname" ] || continue
    echo "Installing $bname $bversion from $brepo"
    bin_install "$bname" "$brepo" "$bversion" "$bkind" "$btag" "$basset" "$brestart"
done <<BINEOF
$BIN_OUTDATED
BINEOF
{{ end -}}
