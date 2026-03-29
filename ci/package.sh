# shellcheck shell=bash
# shellcheck disable=SC2164,SC2153,SC2034

################################################################################
# Packaging
################################################################################

prepare_package_name() {
    VARIANT="$(is_true "$KSU" && echo "KSU" || echo "VNL")"
    is_true "$SUSFS" && VARIANT+="-SUSFS"
    is_true "$LXC" && VARIANT+="-LXC"
    PACKAGE_NAME="$KERNEL_NAME-$KERNEL_VERSION-$VARIANT"
}

package_anykernel() {
    step "Package AnyKernel3"

    local package_name="$1"
    local package_path="$OUT_DIR/$package_name-AnyKernel3.zip"

    pushd "$AK3" >/dev/null
    cp -p "$KERNEL_OUT/arch/arm64/boot/Image" .

    info "Compressing kernel image using zstd..."
    zstd -19 -T0 --no-progress -o Image.zst Image >/dev/null 2>&1
    rm -f ./Image
    sha256sum Image.zst >Image.zst.sha256

    rm -f "$package_path"
    zip -r9q -T -X -y -n .zst "$package_path" . -x '.git/*' '*.log'

    popd >/dev/null
    success "AnyKernel3 packaged"
}

package_bootimg() {
    make_boot() {
        "$MKBOOTIMG/mkbootimg.py" \
            --header_version "4" \
            --kernel "$1" \
            --output "$2" \
            --ramdisk out/ramdisk \
            --os_version "12.0.0" \
            --os_patch_level "2099-12"
        "$BUILD_TOOLS/linux-x86/bin/avbtool" add_hash_footer \
            --partition_name boot \
            --partition_size "$partition_size" \
            --image "$2" \
            --algorithm SHA256_RSA4096 \
            --key "$BOOT_SIGN_KEY"
    }

    step "Package boot image"

    local package_name="$1"
    local partition_size=$((64 * 1024 * 1024))

    pushd "$BOOT_IMAGE" >/dev/null

    curl -fsSLo gki-kernel.zip "$GKI_URL"
    unzip gki-kernel.zip >/dev/null 2>&1 && rm gki-kernel.zip

    "$MKBOOTIMG/unpack_bootimg.py" --boot_img="boot-5.10.img"
    cp -p "$KERNEL_OUT/arch/arm64/boot/Image" ./Image

    if [[ $BOOT_MODE == "multi" ]]; then
        gzip -n -k -f -9 Image
        lz4 -f -l --favor-decSpeed Image Image.lz4

        make_boot "Image" "boot-raw.img"
        make_boot "Image.gz" "boot-gz.img"
        make_boot "Image.lz4" "boot-lz4.img"

        cp "$BOOT_IMAGE/boot-raw.img" "$OUT_DIR/$package_name-boot-raw.img"
        cp "$BOOT_IMAGE/boot-gz.img" "$OUT_DIR/$package_name-boot-gz.img"
        cp "$BOOT_IMAGE/boot-lz4.img" "$OUT_DIR/$package_name-boot-lz4.img"

        popd >/dev/null
        return
    fi

    gzip -n -f -9 Image
    make_boot "Image.gz" "boot.img"
    cp "$BOOT_IMAGE/boot.img" "$OUT_DIR/$package_name-boot.img"

    popd >/dev/null
}

write_metadata() {
    step "Write metadata"

    META_PY="$WORKSPACE/py/meta.py"
    META_FILE="$WORKSPACE/github.json"

    local package_name="$1"

    python3 "$META_PY" \
        "$META_FILE" \
        "$KERNEL_VERSION" "$KERNEL_NAME" "$COMPILER_STRING" \
        "$package_name" "$VARIANT" "$KERNEL_NAME" "$OUT_DIR" \
        "$RELEASE_REPO" "$RELEASE_BRANCH"
}

notify_success() {
    local final_package="$1"
    local build_time="$2"
    # For indicating package type (boot image, anykernel3)
    local additional_tag="$3"

    local minutes=$((build_time / 60))
    local seconds=$((build_time % 60))

    local result_caption
    result_caption=$(
        cat <<EOF
✅ *$(escape_md_v2 "$KERNEL_NAME Build Successfully!")*

🏷️ \#$(escape_md_v2 "$BUILD_TAG") \#$(escape_md_v2 "$additional_tag")
$(tg_run_line)
*Target:* $(escape_md_v2 "$BUILD_TARGET")
*Time:* $(escape_md_v2 "${minutes}m ${seconds}s")
*Kernel:* $(escape_md_v2 "$KERNEL_VERSION")
*Compiler:* $(escape_md_v2 "$COMPILER_STRING")
*Features:* KSU $(parse_bool "$KSU"), SuSFS $(is_true "$SUSFS" && escape_md_v2 "$SUSFS_VERSION" || echo "Disabled"), LXC $(parse_bool "$LXC"), Stock config $(parse_bool "$STOCK_CONFIG")
EOF
    )

    telegram_upload_file "$final_package" "$result_caption"
}

telegram_notify() {
    local build_time="$1"
    local package_name="$2"

    # AnyKernel3
    local ak3_package="$OUT_DIR/$package_name-AnyKernel3.zip"
    notify_success "$ak3_package" "$build_time" "anykernel3"

    # Boot image
    pushd "$OUT_DIR" >/dev/null
    zip -9q -T "$package_name-boot.zip" "$package_name"-boot*.img
    popd >/dev/null

    notify_success "$OUT_DIR/$package_name-boot.zip" "$build_time" "boot_image"
    rm -f "$OUT_DIR/$package_name-boot.zip"
}
