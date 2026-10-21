# shellcheck shell=bash
# shellcheck disable=SC2164,SC2153,SC2034

################################################################################
# Packaging
################################################################################

prepare_package_name() {
    export VARIANT="${PRESET^^}"
    export PACKAGE_NAME="$KERNEL_NAME-$TARGET_NAME-$KERNEL_VERSION-$VARIANT-${KERNEL_COMMIT:0:12}"
}

package_anykernel() {
    step "Package AnyKernel3"

    local package_name="$1"
    local package_path="$OUT_DIR/$package_name-AnyKernel3.zip"

    pushd "$AK3" > /dev/null
    cp -p "$KERNEL_OUT/arch/arm64/boot/Image" .

    info "Compressing kernel image using zstd..."
    zstd -19 -T0 --no-progress -o Image.zst Image > /dev/null 2>&1
    rm -f ./Image
    sha256sum Image.zst > Image.zst.sha256

    info "Cleaning up AK3..."
    find . -type f -name 'placeholder' -delete
    find . -mindepth 1 -depth -type d -empty -delete

    rm -f "$package_path"
    zip -r9q -T -X -y -n .zst "$package_path" . -x '.git/*' '*.log' '.github/*' 'README.md'

    popd > /dev/null
    success "AnyKernel3 packaged"
}

write_metadata() {
    step "Write metadata"
    py_cli meta write "$META_FILE"
}
