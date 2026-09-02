{{- /* Instance -> pinned Minecraft version, plus the installed-build reader.
       Shared by paper-check and paper-upgrade. */ -}}
# name|version, one line per instance declaring a `paper` pin.
PAPER_PINS=$(cat <<'PAPERPINEOF'
{{ range .minecraft.instances }}{{ if hasKey . "paper" }}{{ .name }}|{{ .paper.version }}
{{ end }}{{ end -}}
PAPERPINEOF
)

# Build installed for an instance, read off the paper.jar symlink.
#   <number>    managed, that build
#   unmanaged   a plain file -- the build is unrecoverable, adopt it
#   (empty)     no jar, or a dangling symlink
# Prefix-stripping, not a regex. The version must be quoted inside ${..} or its
# dots glob-match any character. A symlink naming a different version fails the
# strip and compares unequal, which is drift.
paper_installed() { # instance version
    local jar="$HOME/minecraft/$1/paper.jar" base
    [ -e "$jar" ] || return 0
    [ -L "$jar" ] || { printf 'unmanaged'; return 0; }
    base=$(basename "$(readlink "$jar")")
    base=${base#paper-"$2"-}
    printf '%s' "${base%.jar}"
}
