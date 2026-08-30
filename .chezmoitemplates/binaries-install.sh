{{- /* Fetching and installing, used only by install-packages.sh. */ -}}
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

# Substitute {version} and {arch} in a tag or asset pattern.
bin_expand() { # pattern version
    printf '%s' "$1" | sed -e "s/{version}/$2/g" -e "s/{arch}/$(bin_arch)/g"
}

# Fetch and install one binary at its pinned version.
bin_install() { # name repo version install tag asset restart
    local name="$1" repo="$2" version="$3" kind="$4" tag="$5" asset="$6" restart="$7"
    local url tmp rc=0

    tag=$(bin_expand "$tag" "$version")
    asset=$(bin_expand "$asset" "$version")
    url="https://github.com/$repo/releases/download/$tag/$asset"

    tmp=$(mktemp -d)
    if ! curl -fsSL --retry 2 -o "$tmp/$asset" "$url"; then
        echo "  $name: download failed -- $url" >&2
        rm -rf "$tmp"
        return 1
    fi

    case "$kind" in
        deb)
            sudo dpkg -i "$tmp/$asset" || rc=1
            ;;
        tarball)
            if tar -xzf "$tmp/$asset" -C "$tmp" "$name"; then
                sudo install -m755 "$tmp/$name" "/usr/bin/$name" || rc=1
            else
                echo "  $name: $asset contains no file named $name" >&2
                rc=1
            fi
            ;;
        *)
            echo "  $name: no installer for kind '$kind'" >&2
            rc=1
            ;;
    esac
    rm -rf "$tmp"

    # Without this the old process keeps running and nothing says so.
    if [ "$rc" -eq 0 ] && [ -n "$restart" ]; then
        sh -c "$restart" || echo "  $name: installed, but '$restart' failed" >&2
    fi
    return "$rc"
}
