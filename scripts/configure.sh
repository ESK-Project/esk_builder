# shellcheck shell=bash
# shellcheck disable=SC2164,SC2153,SC2034

config() {
    "$KERNEL/scripts/config" --file "$KERNEL/arch/arm64/configs/$KERNEL_DEFCONFIG" "$@"
}

clang_lto() {
    config --enable CONFIG_LTO_CLANG
    case "$1" in
        thin)
            config --enable CONFIG_LTO_CLANG_THIN
            config --disable CONFIG_LTO_CLANG_FULL
            ;;
        full)
            config --enable CONFIG_LTO_CLANG_FULL
            config --disable CONFIG_LTO_CLANG_THIN
            ;;
        *)
            warn "Unknown LTO mode, using thin"
            config --enable CONFIG_LTO_CLANG_THIN
            config --disable CONFIG_LTO_CLANG_FULL
            ;;
    esac
}

install_ksu() {
    info "Install KernelSU: $KSU_SETUP_URL ($KSU_REF)"
    curl -fsSL "$KSU_SETUP_URL" | bash -s -- "$KSU_REF"
}

apply_susfs() {
    info "Apply SuSFS kernel-side patches"

    local susfs_dir="$SUSFS_DIR"
    local susfs_patches="$susfs_dir/kernel_patches"

    SUSFS_COMMIT="$(py_cli source sync "$SUSFS_URL" "$SUSFS_REF" "$susfs_dir")" || return $?
    export SUSFS_COMMIT
    cp -R "$susfs_patches"/fs/* ./fs
    cp -R "$susfs_patches"/include/* ./include

    patch -s -p1 --fuzz=3 --no-backup-if-mismatch < "$susfs_patches"/50_add_susfs_in_gki-android*-*.patch

    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')

    config --enable CONFIG_KSU_SUSFS

    success "SuSFS applied!"
}

prepare_build() {
    step "Prepare build"

    cd "$KERNEL"

    local defconfig_file="$KERNEL/arch/arm64/configs/$KERNEL_DEFCONFIG"
    if [[ ! -f $defconfig_file ]]; then
        error "Defconfig not found: $KERNEL_DEFCONFIG"
    fi

    if is_true "$KSU"; then
        info "Setup KernelSU"
        install_ksu
        KSU_COMMIT="$(git -C "$KERNEL/KernelSU" rev-parse HEAD)"
        export KSU_COMMIT
        config --enable CONFIG_KSU
        success "KernelSU added"
    fi

    if is_true "$SUSFS"; then
        apply_susfs
    else
        config --disable CONFIG_KSU_SUSFS
    fi

    if is_true "$STOCK_CONFIG"; then
        info "Apply stock config patch"
        patch -s -p1 --fuzz=3 --no-backup-if-mismatch < "$KERNEL_PATCHES/stock_config.patch"
    fi

    clang_lto "$CLANG_LTO"
}
