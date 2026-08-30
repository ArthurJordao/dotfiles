{{- /* Placeholder substitution, needed by anything that installs or builds. */ -}}
# Debian's name for the machine, which is what upstream assets are named after.
bin_arch() {
    if command -v dpkg >/dev/null 2>&1; then
        dpkg --print-architecture
        return
    fi
    case "$(uname -m)" in
        x86_64) echo amd64 ;;
        aarch64 | arm64) echo arm64 ;;
        *) uname -m ;;
    esac
}

# Substitute {version} and {arch} in a tag, asset or build command.
bin_expand() { # pattern version
    printf '%s' "$1" | sed -e "s/{version}/$2/g" -e "s/{arch}/$(bin_arch)/g"
}
