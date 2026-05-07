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
    info "Validating environment variables..."

    if [[ -z ${GH_TOKEN:-} ]]; then
        if [[ -x "$CLANG_BIN/clang" ]]; then
            :
        elif is_ci; then
            error "Required Github PAT missing: GH_TOKEN"
        else
            warn "GH_TOKEN isn't set, requests may be rate-limited."
        fi
    fi

    # Telegram checks
    if is_true "$TG_NOTIFY"; then
        : "${TG_BOT_TOKEN:?Required Telegram Bot Token missing: TG_BOT_TOKEN}"
        : "${TG_CHAT_ID:?Required chat ID missing: TG_CHAT_ID}"
        export TG_BOT_TOKEN
        export TG_CHAT_ID
    fi
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
    count build_kernel

    count prepare_package
    count write_metadata "$PACKAGE_NAME"

    local build_time="$SECONDS"
    count finalize_build "$build_time" "$PACKAGE_NAME"
}

main "$@"
