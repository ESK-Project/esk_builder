# shellcheck shell=bash
# shellcheck disable=SC2164,SC2153

################################################################################
# Build preparation
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

    # ccache setup
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

init_logging() {
    # Clean logfile before writing
    : > "$LOGFILE"

    exec > >(tee -a "$LOGFILE") 2>&1
    step "Init logging"
}

validate_env() {
    step "Validate environment"
    info "Validating environment variables..."
    if [[ -z ${GH_TOKEN:-} ]]; then
        if [[ -x "$CLANG_BIN/clang" ]]; then
            :
        elif is_ci; then
            error "Required Github PAT missing: GH_TOKEN"
        else
            warn "GH_TOKEN not set. Github requests may be rate-limited."
        fi
    fi

    if is_true "$TG_NOTIFY"; then
        : "${TG_BOT_TOKEN:?Required Telegram Bot Token missing: TG_BOT_TOKEN}"
        : "${TG_CHAT_ID:?Required chat ID missing: TG_CHAT_ID}"
    fi

    # Python telegram utils
    if is_true "$TG_NOTIFY"; then
        export TG_BOT_TOKEN
        export TG_CHAT_ID
    fi

    # Config checks
    if is_true "$SUSFS" && ! is_true "$KSU"; then
        error "Cannot use SUSFS without KernelSU"
    fi

    if is_true "$LXC" && [[ $BUILD_TARGET != "xaga" ]]; then
        error "LXC is not supported for $BUILD_TARGET target"
    fi
}

send_start_msg() {
    step "Send start message"

    local start_msg
    start_msg=$(
        cat << EOF
🚧 *$(escape_md_v2 "$KERNEL_NAME Kernel Build Started!")*

🏷️ \#$(escape_md_v2 "$BUILD_TAG")
$(tg_run_line)
*Target:* $(escape_md_v2 "$BUILD_TARGET")
*Defconfig:* $(escape_md_v2 "$KERNEL_DEFCONFIG")
*Features:* KSU $(parse_bool "$KSU"), SuSFS $(parse_bool "$SUSFS"), LXC $(parse_bool "$LXC"), Stock config $(parse_bool "$STOCK_CONFIG")
EOF
    )
    telegram_send_msg "$start_msg"
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

apply_susfs() {
    info "Apply SuSFS kernel-side patches"

    local susfs_dir="$SUSFS_DIR"
    local susfs_patches="$susfs_dir/kernel_patches"

    git_clone "$SUSFS_REPO" "$susfs_dir"
    cp -R "$susfs_patches"/fs/* ./fs
    cp -R "$susfs_patches"/include/* ./include

    patch -s -p1 --fuzz=3 --no-backup-if-mismatch < "$susfs_patches"/50_add_susfs_in_gki-android*-*.patch
    
    # will be use later for metadata/telegram
    # shellcheck disable=SC2034
    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')

    config --enable CONFIG_KSU_SUSFS
    config --enable CONFIG_KSU_SUSFS_SUS_PATH
    config --enable CONFIG_KSU_SUSFS_SUS_KSTAT
    config --enable CONFIG_KSU_SUSFS_OPEN_REDIRECT

    success "SuSFS applied!"
}

prepare_build() {
    step "Prepare build"

    cd "$KERNEL"

    # Defconfig existence check
    local defconfig_file="$KERNEL/arch/arm64/configs/$KERNEL_DEFCONFIG"
    [[ -f $defconfig_file ]] || error "Defconfig not found: $KERNEL_DEFCONFIG"

    if is_true "$KSU"; then
        info "Setup KernelSU"
        install_ksu "ESK-Project/ReSukiSU" "main"
        config --enable CONFIG_KSU
        success "KernelSU added"
    fi

    # SuSFS
    if is_true "$SUSFS"; then
        apply_susfs
    else
        config --disable CONFIG_KSU_SUSFS
    fi

    # LXC
    if is_true "$LXC"; then
        info "Apply LXC patch"
        patch -s -p1 --fuzz=3 --no-backup-if-mismatch < "$KERNEL_PATCHES/lxc_support.patch"
    fi

    if is_true "$STOCK_CONFIG"; then
        info "Apply stock config patch"
        patch -s -p1 --fuzz=3 --no-backup-if-mismatch < "$KERNEL_PATCHES/stock_config.patch"
    fi

    # Config Clang LTO
    clang_lto "$CLANG_LTO"
}

build_kernel() {
    step "Build kernel"

    cd "$KERNEL"

    prune_bad_artifacts "$KERNEL_OUT"

    if [[ "$BUILD_TARGET" == xaga ]]; then
        info "Merging defconfig"
        local configs="arch/arm64/configs"
        KCONFIG_CONFIG="$configs/gki_defconfig" scripts/kconfig/merge_config.sh -m -r "$configs/gki_defconfig" "$configs/vendor/xiaomi_mt6895.config" "$configs/vendor/xaga.config"
    fi

    info "Generate defconfig: $KERNEL_DEFCONFIG"
    make "${MAKE_ARGS[@]}" "$KERNEL_DEFCONFIG"

    info "Building Image and modules..."
    make "${MAKE_ARGS[@]}" Image modules
    success "Kernel built successfully"

    if [[ "$BUILD_TARGET" == xaga ]]; then
        info "Installing kernel modules..."
        make "${MAKE_ARGS[@]}" INSTALL_MOD_PATH="$KERNEL_OUT"/modules modules_install
    fi
    
    ccache --show-stats

    # will be use later for metadata/telegram
    # shellcheck disable=SC2034
    KERNEL_VERSION=$(make -s kernelversion | cut -d- -f1)
}
