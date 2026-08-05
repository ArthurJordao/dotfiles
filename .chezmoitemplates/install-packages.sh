{{- /* Shared body for installing this host's declared packages.
       Consumed by BOTH run_onchange_install-packages-linux.sh.tmpl (automatic, on
       change) and dot_local/scripts/executable_install-packages.tmpl (manual, via
       `just packages`). Keep the logic here so the two can never drift.
       Callers supply their own `#!/bin/bash` line. */ -}}
{{- $roles := (index .hosts .hostname).roles -}}
{{- /* Use `index`, not dot-lookup: chezmoi runs templates with missingkey=error,
       so .chezmoi.osRelease.idLike ERRORS on a distro whose os-release omits
       ID_LIKE (plain Arch does), and `| default` never gets a chance to help. */ -}}
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
{{- /* Package names are read at RUNTIME from the group files, so without these
       fingerprints the rendered script would be byte-identical after editing a
       list, run_onchange_ would not re-fire, and the new package would silently
       never install. Guarded by `stat` because roles with no packages have no
       group file and `include` errors on a missing path. */ -}}
# package-list fingerprints (make run_onchange_ re-fire when a list changes):
{{- range $g := (prepend $roles "common") -}}
{{-   $rel := printf "packages/%s/%s.txt" $family $g -}}
{{-   if stat (joinPath $.chezmoi.sourceDir $rel) }}
#   {{ $rel }}: {{ include $rel | sha256sum }}
{{-   end -}}
{{- end }}

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
# Deliberately `-S`, not `-Syu`: refreshing the DB without a full upgrade creates
# partial-upgrade breakage, and doing a full unattended upgrade on every apply is
# not something this script should decide for a host running live services.
# `just upgrade` is the place that does -Syu first, then calls this.
if ! paru -S --needed --noconfirm - < "$LIST"; then
    cat >&2 <<'HINT'

Package install failed. If the output showed 404s while downloading, the pacman
database is stale — it references package versions the mirrors have dropped.
Fix it with a full upgrade, then retry:

    just upgrade

HINT
    exit 1
fi
{{ else -}}
sudo apt-get update
xargs -a "$LIST" sudo apt-get install -y
{{ end -}}
{{ end -}}
