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
source "$WORKSPACE/build/steps.sh"

# Error handling
trap 'error "Build failed at line $LINENO: $BASH_COMMAND"' ERR

################################################################################
# Main
################################################################################

main() {
    SECONDS=0

    init_build
    init_logging
    validate_env
    send_start_msg
    prepare_dirs
    fetch_sources
    setup_toolchain
    prepare_build
    build_kernel

    # Build package name
    VARIANT="$(is_true "$KSU" && echo "KSU" || echo "VNL")"
    is_true "$SUSFS" && VARIANT+="-SUSFS"
    is_true "$LXC" && VARIANT+="-LXC"
    PACKAGE_NAME="$KERNEL_NAME-$KERNEL_VERSION-$VARIANT"

    # Build flashable package
    package_anykernel "$PACKAGE_NAME"
    package_bootimg "$PACKAGE_NAME"

    # Github Actions metadata
    write_metadata "$PACKAGE_NAME"

    local build_time="$SECONDS"

    step 13 "Finalize build"
    if is_true "$TG_NOTIFY"; then
        telegram_notify "$build_time" "$PACKAGE_NAME"
    else
        local min=$((build_time / 60))
        local sec=$((build_time % 60))
        success "Build success in ${min}m ${sec}s"
    fi
}

main "$@"
