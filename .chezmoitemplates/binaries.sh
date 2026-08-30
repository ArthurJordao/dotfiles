{{- /* The BINARIES table and the one helper both consumers need. Split three
       ways so neither consumer carries a function it never calls:
       binaries-net.sh is the checker's, binaries-install.sh the installer's.
       Runs nothing and sets no shell options -- the caller owns those. */ -}}
{{- $roles := (index .hosts .hostname).roles -}}
{{- $family := (index (index .hosts .hostname) "distro" | default "") -}}
{{- $fam := (index .binaries $family | default dict) -}}
{{- $groups := prepend $roles "common" -}}
# Hand-installed binaries, pinned in .chezmoidata/binaries.yaml. Rendered here
# rather than read at runtime, so a version bump changes this script's bytes.
# Fields, pipe-separated because version_cmd contains spaces:
#   name|repo|version|install|tag|asset|version_cmd|restart
BINARIES=$(cat <<'BINLIST'
{{ range $groups }}{{ if hasKey $fam . }}{{ range index $fam . }}{{ .name }}|{{ .repo }}|{{ .version }}|{{ .install }}|{{ .tag }}|{{ index . "asset" | default "" }}|{{ index . "version_cmd" | default "" }}|{{ index . "restart" | default "" }}
{{ end }}{{ end }}{{ end -}}
BINLIST
)

# The version on this host, or empty when the binary is absent. A `deb` reads
# dpkg rather than the binary: the package name is the reliable handle, and
# OliveTin's binary is neither on /usr/bin nor spelled like its package.
bin_installed() { # name install version_cmd
    case "$2" in
        deb)
            dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
            ;;
        *)
            [ -n "$3" ] || return 0
            command -v "$1" >/dev/null 2>&1 || return 0
            sh -c "$3" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true
            ;;
    esac
}
