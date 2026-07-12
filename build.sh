#!/usr/bin/env bash
# shellcheck disable=SC1091

#
# Personal ESK Kernel build script
#

set -Eeuo pipefail

# Workspace
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$WORKSPACE/config.sh"
source "$WORKSPACE/build/all.sh"
source "$WORKSPACE/ci/all.sh"

# Error handling
trap 'error "Build failed at line $LINENO: $BASH_COMMAND"' ERR

################################################################################
# Main
################################################################################

count() {
    ((++STEP))
    "$@"
}

validate_env() {
    local stage="$1"

    case "$stage" in
        github)
            # before fetching github release assets
            if [[ -z ${GH_TOKEN:-} ]]; then
                if [[ -x "$CLANG_BIN/clang" && -f "$LIBFAKESTAT" ]]; then
                    :
                elif is_ci; then
                    error "Required Github PAT missing: GH_TOKEN"
                else
                    warn "GH_TOKEN isn't set, requests may be rate-limited."
                fi
            fi
            ;;
        telegram)
            # before sending telegram updates
            if is_true "$TG_NOTIFY"; then
                : "${TG_BOT_TOKEN:?Required Telegram Bot Token missing: TG_BOT_TOKEN}"
                : "${TG_CHAT_ID:?Required chat ID missing: TG_CHAT_ID}"
                export TG_BOT_TOKEN
                export TG_CHAT_ID
            fi
            ;;
        config)
            # before build prep
            if is_true "$SUSFS" && ! is_true "$KSU"; then
                error "Cannot use SUSFS without KernelSU"
            fi

            if is_true "$LXC" && [[ $BUILD_TARGET != "xaga" ]]; then
                error "LXC is not supported for $BUILD_TARGET target"
            fi
            ;;
        *)
            fatal "Unknown environment validation stage: $stage"
            ;;
    esac
}

validate_deps() {
    local stage="$1"

    case "$stage" in
        base)
            # before the build starts
            require_cmds \
                aria2c bash ccache chmod cp curl date find git head hexdump make mkdir \
                python3 rm sed sha256sum sort tar tee uv zip zstd
            ;;
        patching)
            # before applying patches
            require_cmds patch
            ;;
        modules)
            # before plato module packaging
            require_cmds depmod llvm-strip xz
            ;;
        bootimg)
            # before generic boot image packaging
            require_cmds gzip lz4 unzip
            ;;
        *)
            fatal "Unknown dependency validation stage: $stage"
            ;;
    esac
}

main() {
    SECONDS=0
    STEP=0

    count init_build
    count init_logging
    count send_start_msg
    count prepare_dirs
    count fetch_sources
    count setup_toolchain
    count prepare_build
    count build_kernel
    if [[ "$BUILD_TARGET" == "plato" ]]; then
        count build_module
    fi

    prepare_package_name

    # Build flashable package
    count package_anykernel "$PACKAGE_NAME"
    count package_bootimg "$PACKAGE_NAME"

    # Github Actions metadata
    count write_metadata "$PACKAGE_NAME"

    local build_time="$SECONDS"
    count finalize_build "$build_time" "$PACKAGE_NAME"
}

main "$@"
