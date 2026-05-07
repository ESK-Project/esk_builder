# shellcheck shell=bash

################################################################################
# CI helpers
################################################################################

init_logging() {
    # Clean logfile before writing
    : > "$LOGFILE"

    exec > >(tee -a "$LOGFILE") 2>&1
    step "Init logging"
}

send_start_msg() {
    step "Send start message"

    local start_msg
    start_msg=$(
        cat << EOF
🚧 *$(escape_md_v2 "$KERNEL_NAME Kernel Build Started!")*

🏷️ \#$(escape_md_v2 "$BUILD_TAG")
$(tg_run_line)
*Defconfig:* $(escape_md_v2 "$KERNEL_DEFCONFIG")
*Arch:* $(escape_md_v2 "$ARCH")
*Cross compile:* $(escape_md_v2 "$CROSS_COMPILE")
EOF
    )
    telegram_send_msg "$start_msg"
}

finalize_build() {
    local build_time="$1"
    local package_name="$2"

    step "Finalize build"
    if is_true "$TG_NOTIFY"; then
        telegram_notify "$build_time" "$package_name"
    else
        local min=$((build_time / 60))
        local sec=$((build_time % 60))
        success "Build success in ${min}m ${sec}s"
    fi
}

error() {
    trap - ERR
    printf '%b\n' "${RED}[$(date '+%F %T')] [ERROR]${NC} $*" >&2

    is_true "${TG_NOTIFY:-false}" || exit 1

    local msg
    msg=$(
        cat << EOF
❌ *$(escape_md_v2 "$KERNEL_NAME Kernel CI")*

🏷️ *Tags*: \#$(escape_md_v2 "$BUILD_TAG") \#error
$(tg_run_line)

$(escape_md_v2 "ERROR: $*")
EOF
    )

    telegram_upload_file "$LOGFILE" "$msg"
    exit 1
}
