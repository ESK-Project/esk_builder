# shellcheck shell=bash

################################################################################
# GitHub metadata helpers
################################################################################
GITHUB_PY="$WORKSPACE/py/github.py"
GITHUB_JSON_FILE="$WORKSPACE/github.json"

github_write_metadata() {
    local package_name="$1"
    local anykernel_zip="$package_name-AnyKernel3.zip"
    local boot_image="$package_name-boot.img"

    python3 "$GITHUB_PY" \
        "$GITHUB_JSON_FILE" \
        "$KERNEL_VERSION" "$KERNEL_NAME" "$COMPILER_STRING" \
        "$package_name" "$VARIANT" "$KERNEL_NAME" "$OUT_DIR" \
        "$RELEASE_REPO" "$RELEASE_BRANCH" "$anykernel_zip" "$boot_image"
}
