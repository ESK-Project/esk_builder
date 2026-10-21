# shellcheck shell=bash
# shellcheck disable=SC2164,SC2153,SC2034

prune_bad_artifacts() {
    local build_dir="$1"

    [[ -d $build_dir ]] || return 0

    find "$build_dir" -type f -size 0 \
        \( -name '*.o' -o -name '*.a' -o -name '*.ko' -o -name '*.symversions' \) \
        -print -delete
}

build_kernel() {
    step "Build kernel"

    cd "$KERNEL"

    prune_bad_artifacts "$KERNEL_OUT"

    info "Merging defconfig"
    local config_dir="$KERNEL/arch/arm64/configs" overlay
    local overlays=()
    while IFS= read -r overlay; do
        [[ -z $overlay ]] || overlays+=("$config_dir/$overlay")
    done <<< "$DEFCONFIG_OVERLAYS"
    if ((${#overlays[@]})); then
        KCONFIG_CONFIG="$config_dir/$KERNEL_DEFCONFIG" scripts/kconfig/merge_config.sh -m -r \
            "$config_dir/$KERNEL_DEFCONFIG" "${overlays[@]}"
    fi

    info "Generate defconfig: $KERNEL_DEFCONFIG"
    make "${MAKE_ARGS[@]}" "$KERNEL_DEFCONFIG"

    info "Building Image and modules..."
    local started=$SECONDS
    make "${MAKE_ARGS[@]}" Image modules
    COMPILE_SECONDS=$((SECONDS - started))
    export COMPILE_SECONDS
    touch "$OUT_DIR/compiled"
    if is_true "$CCACHE_ENABLED"; then
        ccache --show-log-stats | tee "$OUT_DIR/ccache-stats.txt"
    fi
    success "Kernel built successfully"

    # Stale release directories would mix modules in the package.
    reset_dir "$INSTALLED_MODULES"
    make "${MAKE_ARGS[@]}" INSTALL_MOD_PATH="$INSTALLED_MODULES" modules_install
    KERNEL_RELEASE="$(make -s LLVM=1 O="$KERNEL_OUT" ARCH=arm64 kernelrelease)"
    export KERNEL_RELEASE
    KERNEL_VERSION="$(make -s LLVM=1 kernelversion | cut -d- -f1)"
    export KERNEL_VERSION
}
