#!/usr/bin/env bash
# shellcheck disable=SC1091
set -Eeuo pipefail

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$WORKSPACE/scripts/common.sh"
source "$WORKSPACE/scripts/sources.sh"
source "$WORKSPACE/scripts/toolchain.sh"
source "$WORKSPACE/scripts/configure.sh"
source "$WORKSPACE/scripts/compile.sh"
source "$WORKSPACE/scripts/modules.sh"
source "$WORKSPACE/scripts/package.sh"
source "$WORKSPACE/scripts/notify.sh"

count() {
    ((++STEP))
    "$@"
}

validate_env() {
    if is_true "$TG_NOTIFY"; then
        : "${TG_BOT_TOKEN:?TG_BOT_TOKEN is required when notifications are enabled}"
        : "${TG_CHAT_ID:?TG_CHAT_ID is required when notifications are enabled}"
    fi
}

validate_deps() {
    require_cmds bash make git curl aria2c patch zip zstd tar xz depmod \
        llvm-strip bc bison flex hexdump python3 uv sha256sum
    if is_true "$CCACHE_ENABLED"; then
        require_cmds ccache
    fi
    LIBFAKETIME="$(find /usr/lib /lib -name libfaketimeMT.so.1 -print -quit 2> /dev/null)"
    [[ -f $LIBFAKETIME ]] || fatal "libfaketimeMT.so.1 is missing; install libfaketime"
    export LIBFAKETIME
}

prepare_output() {
    reset_dir "$OUT_DIR"
}

init_build() {
    step "Init build"
    BUILD_TAG="kernel_$(hexdump -v -e '/1 "%02x"' -n4 /dev/urandom)"
    export BUILD_TAG KBUILD_BUILD_USER KBUILD_BUILD_HOST
    BUILDER_COMMIT="$(git -C "$WORKSPACE" rev-parse HEAD)"
    export BUILDER_COMMIT
    MAKE_ARGS=(-j"$JOBS" O="$KERNEL_OUT" ARCH=arm64
        CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 LD="$WRAPPER_DIR/ld.lld")
}

prepare_dirs() {
    step "Prepare directories"
    reset_dir "$STAGING"
    if is_true "$RESET_SOURCES"; then
        reset_dir "$SOURCE_DIR"
    fi
    mkdir -p "$SOURCE_DIR" "$KERNEL_OUT" "$MOD_FLAT" "$MOD_STAGE"
}

main() {
    : "${TARGET_NAME:?Use the Python CLI: uv run esk build}"
    SECONDS=0 STEP=0
    validate_deps
    validate_env
    count prepare_output
    count init_logging
    trap 'error "Build failed at line $LINENO: $BASH_COMMAND"' ERR
    count init_build
    count prepare_dirs
    count send_start_msg
    count fetch_sources
    count setup_toolchain
    count setup_ld_preload
    count setup_ccache
    count prepare_build
    count build_kernel
    count build_module
    prepare_package_name
    count package_anykernel "$PACKAGE_NAME"
    count write_metadata
    count finalize_build "$SECONDS" "$PACKAGE_NAME"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
