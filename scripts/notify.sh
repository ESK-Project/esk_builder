# shellcheck shell=bash
# shellcheck disable=SC2164,SC2153,SC2034

error() {
    local status=$?
    trap - ERR
    printf '[ERROR] %s\n' "$*" >&2
    if is_true "${TG_NOTIFY:-false}"; then
        printf '%s' "$*" | py_cli tg notify error || true
    fi
    ((status != 0)) || status=1
    exit "$status"
}

send_start_msg() {
    is_true "$TG_NOTIFY" || return 0
    py_cli tg notify start
}

finalize_build() {
    local build_time="$1"
    success "Build success in $((build_time / 60))m $((build_time % 60))s"
    is_true "$TG_NOTIFY" || return 0
    py_cli tg notify success --seconds "$build_time"
}
