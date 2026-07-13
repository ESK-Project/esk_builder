# shellcheck shell=bash

################################################################################
# CI helpers
################################################################################

source "$WORKSPACE/logging.sh"

error() {
    trap - ERR
    printf '%b\n' "${RED}[$(date '+%F %T')] [ERROR]${NC} $*" >&2

    if is_true "${TG_NOTIFY:-false}"; then
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
    fi

    exit 1
}

tg_run_line() {
    if is_ci; then
        printf '🔗 [Workflow run](%s)\n' "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
    else
        printf '🔗 Workflow run: Not available\n'
    fi
}

telegram_send_msg() {
    is_true "${TG_NOTIFY:-false}" || return 0
    printf '%s' "$*" | py_cli tg msg
}

telegram_upload_file() {
    is_true "${TG_NOTIFY:-false}" || return 0

    local file="$1"
    shift # For the caption
    printf '%s' "$*" | py_cli tg doc "$file"
}

telegram_upload_gallery() {
    is_true "${TG_NOTIFY:-false}" || return 0

    printf '%s' "$1" | py_cli tg gallery "${@:2}"
}

init_logging() {
    # Clean logfile before writing
    : > "$LOGFILE"

    exec > >(tee -a "$LOGFILE") 2>&1
    step "Init logging"
}

send_start_msg() {
    step "Send start message"

    # Needed before sending Telegram updates.
    validate_env telegram

    local start_msg
    start_msg=$(
        cat << EOF
🚧 *$(escape_md_v2 "$KERNEL_NAME Kernel Build Started!")*

🏷️ \#$(escape_md_v2 "$BUILD_TAG")
$(tg_run_line)
*Target:* $(escape_md_v2 "$BUILD_TARGET")
*Defconfig:* $(escape_md_v2 "$KERNEL_DEFCONFIG")
*Features:* KSU $(parse_bool "$KSU"), SuSFS $(parse_bool "$SUSFS"), LXC $(parse_bool "$LXC"), Stock config $(parse_bool "$STOCK_CONFIG")
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
