# shellcheck shell=bash
# shellcheck disable=SC2164,SC2153,SC2034

github_release_asset_url() {
    local api_url="$1"
    local pattern="$2"
    py_cli release asset-url "$pattern" --api-url "$api_url"
}

setup_toolchain() {
    step "Setup toolchain"

    _use_toolchain() {
        export PATH="$CLANG_BIN:$PATH"
        COMPILER_STRING="$("$CLANG_BIN/clang" --version | head -n 1 | sed 's/(https..*//')"
        export COMPILER_STRING
        export KBUILD_BUILD_USER KBUILD_BUILD_HOST
    }

    if [[ -x "$CLANG_BIN/clang" ]]; then
        info "Using existing AOSP Clang toolchain"
        _use_toolchain
        return 0
    fi

    info "Fetching AOSP Clang toolchain"
    local clang_url
    clang_url=$(
        github_release_asset_url \
            "$CLANG_RELEASE_API" \
            "clang-r*.tar.gz"
    )

    mkdir -p "$CLANG"

    local aria_opts=(
        -q -c -x16 -s16 -k8M -m 5 --retry-wait=5
        --file-allocation=falloc
        -d "$WORKSPACE" -o "clang-archive" "$clang_url"
    )

    if aria2c "${aria_opts[@]}"; then
        success "Clang download successful!"
    else
        error "Clang download failed."
    fi

    tar -xzf "$WORKSPACE/clang-archive" -C "$CLANG"
    rm -f "$WORKSPACE/clang-archive"

    _use_toolchain
}

# Fixed-time values are embedded in this hashed launcher.
# shellcheck disable=SC2016
gen_wrapper() {
    mkdir -p "$WRAPPER_DIR"
    # Fixed time is part of the hashed launcher; ccache itself sees normal stat/time.
    printf '#!/usr/bin/env bash\nset -Eeuo pipefail\nexport LD_PRELOAD="$LIBFAKESTAT $LIBFAKETIME"\nexport FAKESTAT=%q\nexport FAKETIME=%q\nexec "$@"\n' \
        "$FAKE_TIME" "@$FAKE_TIME" > "$WRAPPER_DIR/esk-compiler-env"
    local tool
    for tool in clang ld.lld; do
        printf '#!/usr/bin/env bash\nset -Eeuo pipefail\nexec "$WRAPPER_DIR/esk-compiler-env" "$CLANG_BIN/%s" "$@"\n' \
            "$tool" > "$WRAPPER_DIR/$tool"
    done
    chmod +x "$WRAPPER_DIR/esk-compiler-env" "$WRAPPER_DIR/clang" "$WRAPPER_DIR/ld.lld"
}

setup_ld_preload() {
    export LIBFAKETIME LIBFAKESTAT
    if [[ ! -f "$LIBFAKESTAT" ]]; then
        local archive="$LIBFAKESTAT_DIR/archive.tar.gz" url
        mkdir -p "$LIBFAKESTAT_DIR"
        url=$(github_release_asset_url "$LIBFAKESTAT_RELEASE_API" "libfakestat.tar.gz")
        curl -fsSLo "$archive" "$url"
        tar -xzf "$archive" -C "$LIBFAKESTAT_DIR"
        rm -f "$archive"
    fi
    gen_wrapper
}

setup_ccache() {
    export PATH="$WRAPPER_DIR:$CLANG_BIN:$PATH"
    export CCACHE_BASEDIR="$WORKSPACE" CCACHE_COMPILERCHECK=content
    export CCACHE_SLOPPINESS="" CCACHE_HASHDIR=true CCACHE_COMPRESS=true
    unset CCACHE_NOHASHDIR
    export CCACHE_PREFIX=esk-compiler-env CCACHE_PREFIX_CPP=esk-compiler-env
    export CCACHE_EXTRAFILES="$WRAPPER_DIR/esk-compiler-env:$LIBFAKESTAT:$LIBFAKETIME"
    if is_true "$CCACHE_ENABLED"; then
        unset CCACHE_DISABLE
        mkdir -p "$CCACHE_DIR"
        : > "$CCACHE_STATSLOG"
        ccache --max-size "$CCACHE_SIZE"
        local compiler
        printf -v compiler '%q' "$CLANG_BIN/clang"
        MAKE_ARGS+=("CC=ccache $compiler")
        ccache --show-config
    else
        MAKE_ARGS+=("CC=$WRAPPER_DIR/clang")
    fi
}
