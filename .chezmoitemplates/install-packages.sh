{{- /* Shared by run_onchange_10-install-packages.sh.tmpl and
       dot_local/scripts/executable_install-packages.tmpl.
       Callers add the shebang. Set PROMPT=1 to ask before installing.
       Linux only: .local/scripts/install-packages is not deployed on darwin,
       so the brew path lives inline in the run_onchange script instead. */ -}}
{{- $roles := (index .hosts .hostname).roles -}}
{{- $id := (index .chezmoi.osRelease "id" | default "") -}}
{{- $like := (index .chezmoi.osRelease "idLike" | default "") -}}
{{- $family := "" -}}
{{- if or (eq $id "arch") (eq $id "cachyos") (contains "arch" $like) -}}
{{-   $family = "arch" -}}
{{- else if or (eq $id "debian") (eq $id "ubuntu") (contains "debian" $like) -}}
{{-   $family = "debian" -}}
{{- end -}}
set -euo pipefail
{{ if eq $family "" -}}
echo "Unsupported distro: id={{ $id }} id_like={{ $like }}" >&2
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

# The delta drives the prompt only. It is allowed to be slightly
# over-inclusive -- a package satisfied by another's `provides` shows as
# missing -- because --needed remains the real guard against reinstalling.
MISSING="$(comm -13 <(printf '%s\n' "$INSTALLED" | sort -u) \
                    <(printf '%s\n' "$DECLARED"  | sort -u))"

if [ -z "$MISSING" ]; then
    exit 0
fi

echo "Declared but not installed (family={{ $family }}):"
printf '%s\n' "$MISSING" | sed 's/^/  /'

if [ "${PROMPT:-0}" = "1" ]; then
    if [ ! -t 0 ]; then
        echo "Not a terminal -- skipping. Run 'just packages' to install." >&2
        exit 0
    fi
    printf 'Install these now? [y/N] '
    read -r reply
    case "$reply" in
        [yY]*) ;;
        *) echo "Skipped. Run 'just packages' when ready."; exit 0 ;;
    esac
fi

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
sudo apt-get update
xargs -a "$LIST" sudo apt-get install -y
{{ end -}}
{{ end -}}
