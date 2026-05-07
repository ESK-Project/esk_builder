# shellcheck shell=bash
# shellcheck disable=SC2164,SC2153,SC2034

################################################################################
# Build setup
################################################################################

setup_ccache() {
    export CCACHE_DIR="${CCACHE_DIR:-$WORKSPACE/.ccache}"
    export CCACHE_BASEDIR="$WORKSPACE"
    export CCACHE_COMPILERCHECK="content"
    export CCACHE_NOHASHDIR=true
    export CCACHE_SLOPPINESS="file_stat_matches,include_file_ctime,include_file_mtime,pch_defines,file_macro,time_macro"

    mkdir -p "$CCACHE_DIR"
    ccache --max-size "$CCACHE_SIZE"

    ccache --zero-stats
    ccache --show-config
}

gen_wrapper() {
    local tool="$1"
    local fake_time="2026-03-14 12:00:00"

    cat > "$WORKSPACE/build/$tool" << EOF
#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE="\$(cd -- "\$(dirname -- "\${BASH_SOURCE[0]}")/.." && pwd)"

export LD_PRELOAD="\$LIBFAKESTAT \$LIBFAKETIME"
export FAKESTAT="$fake_time"
export FAKETIME="@$fake_time"

exec "\$WORKSPACE/clang/bin/$tool" "\$@"
EOF

    chmod +x "$WORKSPACE/build/$tool"
}

setup_ld_preload() {
    export LIBFAKETIME
    LIBFAKETIME=$(find /usr/lib* /lib* -name libfaketimeMT.so.1 -print -quit 2> /dev/null || true)
    export LIBFAKESTAT

    if [[ ! -f "$LIBFAKESTAT" ]]; then
        local archive="$WORKSPACE/libfakestat.tar.gz"
        mkdir -p "$LIBFAKESTAT_DIR"

        curl -fsSLo "$archive" "$LIBFAKESTAT_URL"
        tar -xzf "$archive" -C "$LIBFAKESTAT_DIR"
        rm -f "$archive"
    fi

    [[ -f "$WORKSPACE/build/clang" ]] || gen_wrapper clang
    [[ -f "$WORKSPACE/build/ld.lld" ]] || gen_wrapper ld.lld
}

init_build() {
    step "Init build"

    BUILD_TAG="kernel_$(hexdump -v -e '/1 "%02x"' -n4 /dev/urandom)"
    info "Build tag generated: $BUILD_TAG"

    # Compiler setup
    setup_ccache
    setup_ld_preload

    # Make arguments
    MAKE_ARGS=(
        -j"$JOBS" O="$KERNEL_OUT" ARCH="$ARCH"
        CROSS_COMPILE="$CROSS_COMPILE"
        CC="ccache clang" HOSTCC="ccache clang"
        LOCALVERSION="-esk-rpi"
        LLVM="1" LD="ld.lld"
    )

    # Environment default setting
    TG_NOTIFY="$(norm_default "${TG_NOTIFY-}" "false")"
    RESET_SOURCES="$(norm_default "${RESET_SOURCES-}" "false")"

    if is_ci; then
        TG_NOTIFY="$(norm_default "${TG_NOTIFY-}" "true")"
        RESET_SOURCES="$(norm_default "${RESET_SOURCES-}" "true")"
    fi

    info "Building in $(is_ci && echo CI || echo local)"

    # Set timezone
    export TZ="$TIMEZONE"
}

prepare_dirs() {
    step "Prepare directories"

    reset_dir "$OUT_DIR"

    if is_true "$RESET_SOURCES"; then
        reset_dir "$KERNEL"
    fi

    find "$WORKSPACE" -maxdepth 1 -type f -name '*.deb' -delete
}

fetch_sources() {
    step "Fetch sources"

    info "Cloning kernel source..."
    git_clone "$KERNEL_REPO" "$KERNEL"
}

setup_toolchain() {
    step "Setup toolchain"

    _use_toolchain() {
        [[ -x "$CLANG_BIN/clang" ]] || error "clang not found in toolchain: $CLANG_BIN/clang"
        [[ -x "$CLANG_BIN/ld.lld" ]] || error "ld.lld not found in toolchain: $CLANG_BIN/ld.lld"

        export PATH="$CLANG_BIN:$PATH"
        "$CLANG_BIN/clang" --version > /dev/null
        "$CLANG_BIN/ld.lld" --version > /dev/null

        COMPILER_STRING="$("$CLANG_BIN/clang" --version | head -n 1 | sed 's/(https..*//')"
        export KBUILD_BUILD_USER KBUILD_BUILD_HOST
    }

    if [[ -x "$CLANG_BIN/clang" ]]; then
        info "Using existing AOSP Clang toolchain"
        _use_toolchain
        return 0
    fi

    info "Fetching AOSP Clang toolchain"
    local clang_url
    local auth_header=()
    [[ -n ${GH_TOKEN:-} ]] && auth_header=(-H "Authorization: Bearer $GH_TOKEN")
    clang_url=$(curl -fsSL \
        "${auth_header[@]}" \
        "https://api.github.com/repos/bachnxuan/aosp_clang_mirror/releases/latest" \
        | grep "browser_download_url" \
        | grep ".tar.gz" \
        | cut -d '"' -f 4)

    mkdir -p "$CLANG"

    local aria_opts=(
        -q -c -x16 -s16 -k8M -m 5 --retry-wait=5
        --file-allocation=falloc --check-certificate=false
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
