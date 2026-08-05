{{- /* Shared by run_once_10-install-packages.sh.tmpl and
       dot_local/scripts/executable_install-packages.tmpl. Callers add the shebang. */ -}}
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
{{ else -}}
PKGDIR="{{ .chezmoi.sourceDir }}/packages/{{ $family }}"
PKG_GROUPS=(common{{ range $roles }} {{ . }}{{ end }})

LIST="$(mktemp)"
trap 'rm -f "$LIST"' EXIT

for g in "${PKG_GROUPS[@]}"; do
    [ -f "$PKGDIR/$g.txt" ] && cat "$PKGDIR/$g.txt" >> "$LIST"
done

sort -u -o "$LIST" "$LIST"

if [ ! -s "$LIST" ]; then
    echo "No packages selected for groups: ${PKG_GROUPS[*]}" >&2
    exit 0
fi

echo "Installing $(wc -l < "$LIST") packages for family={{ $family }} groups=${PKG_GROUPS[*]}"
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
