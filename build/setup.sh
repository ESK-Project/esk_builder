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

setup_ld_preload() {
    export LIBFAKETIME
    LIBFAKETIME=$(find /usr/lib* /lib* -name libfaketimeMT.so.1 -print -quit 2> /dev/null || true)
    export LIBFAKESTAT

    [[ -f "$LIBFAKESTAT" ]] && return 0

    local archive="$WORKSPACE/libfakestat.tar.gz"
    mkdir -p "$LIBFAKESTAT_DIR"

    curl -fsSLo "$archive" "$LIBFAKESTAT_URL"
    tar -xzf "$archive" -C "$LIBFAKESTAT_DIR"
    rm -f "$archive"
}

init_build() {
    step "Init build"

    BUILD_TAG="kernel_$(hexdump -v -e '/1 "%02x"' -n4 /dev/urandom)"
    info "Build tag generated: $BUILD_TAG"

    # Kernel flavour
    KSU="$(norm_bool "${KSU:-false}")"
    SUSFS="$(norm_bool "${SUSFS:-false}")"
    LXC="$(norm_bool "${LXC:-false}")"
    STOCK_CONFIG="$(norm_default "${STOCK_CONFIG-}" "true")"

    # Compiler setup
    setup_ccache
    setup_ld_preload

    # Make arguments
    MAKE_ARGS=(
        -j"$JOBS" O="$KERNEL_OUT" ARCH="arm64"
        CC="ccache clang" CROSS_COMPILE="aarch64-linux-gnu-"
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

    for dir in "$OUT_DIR" "$BOOT_IMAGE" "$AK3" $MODULES_STAGE; do
        reset_dir "$dir"
    done

    if is_true "$RESET_SOURCES"; then
        for dir in "$KERNEL" "$BUILD_TOOLS" "$MKBOOTIMG" "$SUSFS_DIR"; do
            reset_dir "$dir"
        done
    fi
}

fetch_sources() {
    step "Fetch sources"

    info "Cloning kernel source..."
    git_clone "$KERNEL_REPO" "$KERNEL"

    info "Cloning AnyKernel3..."
    git_clone "$AK3_REPO" "$AK3"

    info "Cloning build tools..."
    git_clone "$BUILD_TOOLS_REPO" "$BUILD_TOOLS"
    git_clone "$MKBOOTIMG_REPO" "$MKBOOTIMG"
}

setup_toolchain() {
    step "Setup toolchain"

    _use_toolchain() {
        export PATH="$WORKSPACE/build:$CLANG_BIN:$PATH"
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
    clang_url=$(curl -fsSL "https://api.github.com/repos/bachnxuan/aosp_clang_mirror/releases/latest" \
        "${auth_header[@]}" \
        | grep "browser_download_url" \
        | grep ".tar.gz" \
        | cut -d '"' -f 4)

    mkdir -p "$CLANG"

    local attempt=0
    local retries=5
    local aria_opts=(
        -q -c -x16 -s16 -k8M
        --file-allocation=falloc --check-certificate=false
        -d "$WORKSPACE" -o "clang-archive" "$clang_url"
    )

    while ((attempt < retries)); do
        if aria2c "${aria_opts[@]}"; then
            success "Clang download successful!"
            break
        fi

        ((attempt++))
        warn "Clang download attempt $attempt/$retries failed, retrying..."
        ((attempt < retries)) && sleep 5
    done

    if ((attempt == retries)); then
        error "Clang download failed after $retries attempts!"
    fi

    tar -xzf "$WORKSPACE/clang-archive" -C "$CLANG"
    rm -f "$WORKSPACE/clang-archive"

    _use_toolchain
}
