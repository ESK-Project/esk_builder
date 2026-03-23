#!/usr/bin/env bash
# shellcheck disable=SC1091

#
# Personal ESK Kernel build script
#

set -Eeuo pipefail

# Workspace
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$WORKSPACE/config.sh"
source "$WORKSPACE/build/utils.sh"
source "$WORKSPACE/build/telegram.sh"
source "$WORKSPACE/build/compile.sh"
source "$WORKSPACE/build/module.sh"
source "$WORKSPACE/build/package.sh"

# Error handling
trap 'error "Build failed at line $LINENO: $BASH_COMMAND"' ERR

################################################################################
# Main
################################################################################

count() {
    ((++STEP))
    "$@"
}

main() {
    SECONDS=0
    STEP=0

    count init_build
    count init_logging
    count validate_env
    count send_start_msg
    count prepare_dirs
    count fetch_sources
    count setup_toolchain
    count prepare_build
    count build_kernel
    if [[ "$BUILD_TARGET" == "xaga" ]]; then
        count stage
        count vendor_dlkm
        count vendor_boot
    fi

    # Build package name
    VARIANT="$(is_true "$KSU" && echo "KSU" || echo "VNL")"
    is_true "$SUSFS" && VARIANT+="-SUSFS"
    is_true "$LXC" && VARIANT+="-LXC"
    PACKAGE_NAME="$KERNEL_NAME-$KERNEL_VERSION-$VARIANT"

    # Build flashable package
    count package_anykernel "$PACKAGE_NAME"
    count package_bootimg "$PACKAGE_NAME"

    # Github Actions metadata
    count write_metadata "$PACKAGE_NAME"

    local build_time="$SECONDS"

    ((STEP++))
    step "Finalize build"
    if is_true "$TG_NOTIFY"; then
        telegram_notify "$build_time" "$PACKAGE_NAME"
    else
        local min=$((build_time / 60))
        local sec=$((build_time % 60))
        success "Build success in ${min}m ${sec}s"
    fi
}

main "$@"
