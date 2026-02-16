# shellcheck shell=bash

################################################################################
# Telegram helpers
################################################################################
# Telegram python utils path
TG_PY="$WORKSPACE/py/tg.py"

tg_run_line() {
    if is_ci; then
        printf '🔗 [Workflow run](%s)\n' "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
    else
        printf '🔗 Workflow run: Not available\n'
    fi
}

telegram_send_msg() {
    is_true "$TG_NOTIFY" || return 0
    printf '%s' "$*" | python3 "$TG_PY" msg
}

telegram_upload_file() {
    is_true "$TG_NOTIFY" || return 0

    local file="$1"
    shift # For the caption
    printf '%s' "$*" | python3 "$TG_PY" doc "$file"
}
