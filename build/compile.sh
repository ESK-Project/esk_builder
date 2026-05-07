# shellcheck shell=bash
# shellcheck disable=SC2164,SC2153,SC2034

################################################################################
# Build compilation
################################################################################

build_kernel() {
    local defconfig_file="$KERNEL/arch/$ARCH/configs/$KERNEL_DEFCONFIG"

    step "Build kernel"

    cd "$KERNEL"
    [[ -f $defconfig_file ]] || error "Defconfig not found: $KERNEL_DEFCONFIG"

    prune_bad_artifacts "$KERNEL_OUT"

    clang_lto "$CLANG_LTO"

    info "Generate defconfig: $KERNEL_DEFCONFIG"
    make "${MAKE_ARGS[@]}" "$KERNEL_DEFCONFIG"

    KERNEL_VERSION=$(make -s "${MAKE_ARGS[@]}" kernelrelease)

    info "Building deb packages..."
    make "${MAKE_ARGS[@]}" bindeb-pkg
    success "Kernel built successfully"

    ccache --show-stats
}
