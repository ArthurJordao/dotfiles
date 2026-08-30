{{- /* The local compile, used only by binaries-build. */ -}}
# Compile one binary here and install the result.
bin_build() { # name version build toolchain restart
    local name="$1" version="$2" build="$3" toolchain="$4" restart="$5"
    local gobin tmp rc=0

    # Debian's versioned Go packages install under /usr/lib/go-<X.Y>/bin and
    # provide no /usr/bin/go, so the toolchain must go on PATH explicitly.
    gobin="/usr/lib/go-$(printf '%s' "$toolchain" | sed -e 's/^golang-//' -e 's/-go$//')/bin"
    if [ ! -x "$gobin/go" ]; then
        echo "  $name: no Go at $gobin -- is $toolchain installed?" >&2
        return 1
    fi

    build=$(bin_expand "$build" "$version")
    tmp=$(mktemp -d)
    if (cd "$tmp" && PATH="$gobin:$PATH" sh -c "$build" >&2) && [ -f "$tmp/$name" ]; then
        sudo install -m755 "$tmp/$name" "/usr/bin/$name" || rc=1
    else
        echo "  $name: build produced no $name" >&2
        rc=1
    fi
    rm -rf "$tmp"

    # Without this the old process keeps running and nothing says so.
    if [ "$rc" -eq 0 ] && [ -n "$restart" ]; then
        sh -c "$restart" || echo "  $name: installed, but '$restart' failed" >&2
    fi
    return "$rc"
}
