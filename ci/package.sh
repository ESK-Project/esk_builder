# shellcheck shell=bash
# shellcheck disable=SC2164,SC2153,SC2034

################################################################################
# Packaging
################################################################################

prepare_package() {
    local -a debs files
    local file

    step "Prepare package"

    shopt -s nullglob
    debs=("$WORKSPACE"/*.deb)
    shopt -u nullglob

    ((${#debs[@]} > 0)) || error "No deb packages were generated"

    cp -p "${debs[@]}" "$OUT_DIR/"

    PACKAGE_NAME="$KERNEL_NAME-$KERNEL_VERSION-deb"
    PACKAGE_FILE="$PACKAGE_NAME.tar.xz"

    for file in "${debs[@]}"; do
        files+=("$(basename "$file")")
    done

    tar -C "$OUT_DIR" -cvpf - "${files[@]}" | xz -9e -T0 > "$OUT_DIR/$PACKAGE_FILE"

    success "Deb packages prepared"
}

write_metadata() {
    step "Write metadata"

    META_PY="$WORKSPACE/py/meta.py"
    META_FILE="$WORKSPACE/github.json"

    local package_name="$1"

    python3 "$META_PY" \
        "$META_FILE" \
        "$KERNEL_VERSION" "$KERNEL_NAME" "$COMPILER_STRING" \
        "$package_name" "$KERNEL_NAME" "$OUT_DIR" \
        "$RELEASE_REPO" "$RELEASE_BRANCH"
}

notify_success() {
    local final_package="$1"
    local build_time="$2"
    local minutes=$((build_time / 60))
    local seconds=$((build_time % 60))

    local result_caption
    result_caption=$(
        cat << EOF
✅ *$(escape_md_v2 "$KERNEL_NAME Build Successfully!")*

🏷️ \#$(escape_md_v2 "$BUILD_TAG")
$(tg_run_line)
*Time:* $(escape_md_v2 "${minutes}m ${seconds}s")
*Kernel:* $(escape_md_v2 "$KERNEL_VERSION")
*Compiler:* $(escape_md_v2 "$COMPILER_STRING")
*Artifact:* $(escape_md_v2 "$(basename "$final_package")")
EOF
    )

    telegram_upload_file "$final_package" "$result_caption"
}

telegram_notify() {
    local build_time="$1"
    local artifact_package

    artifact_package="$OUT_DIR/$PACKAGE_FILE"
    [[ -f $artifact_package ]] || error "Package not found"
    notify_success "$artifact_package" "$build_time"
}
