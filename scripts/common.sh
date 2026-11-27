# shellcheck shell=bash
# shellcheck disable=SC2164,SC2153,SC2034

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { printf '%b\n' "${BLUE}[$(date '+%F %T')] [INFO]${NC} $*"; }
success() { printf '%b\n' "${GREEN}[$(date '+%F %T')] [SUCCESS]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[$(date '+%F %T')] [WARN]${NC} $*"; }
step() {
    local message="$1"
    printf '%b\n' "${BOLD}[$(date '+%F %T')] [STEP ${STEP}] ${message}${NC}"
}

fatal() {
    printf '%b\n' "${RED}[$(date '+%F %T')] [ERROR]${NC} $*" >&2
    return 1
}

require_cmds() {
    local cmd
    local missing_cmds=()

    for cmd in "$@"; do
        if command -v "$cmd" > /dev/null 2>&1; then
            continue
        fi
        missing_cmds+=("$cmd")
    done

    if ((${#missing_cmds[@]} != 0)); then
        fatal "Missing required command(s): ${missing_cmds[*]}"
    fi
}

py_cli() {
    uv run --project "$WORKSPACE" esk "$@"
}

is_true() {
    [[ $1 == true ]]
}

is_ci() {
    [[ ${GITHUB_ACTIONS:-} == "true" ]]
}

reset_dir() {
    local path="$1"
    if [[ -d $path ]]; then
        rm -rf -- "$path"
    fi
    mkdir -p -- "$path"
}

init_logging() {
    : > "$LOGFILE"
    exec > >(tee -a "$LOGFILE") 2>&1
    step "Init logging"
}

error() {
    local status=$?
    trap - ERR
    stop_telegram_progress
    printf '[ERROR] %s\n' "$*" >&2
    if is_true "${TG_NOTIFY:-false}"; then
        printf '%s' "$*" | py_cli tg notify error --seconds "$SECONDS" 2> /dev/null || warn "Telegram notification failed"
    fi
    ((status != 0)) || status=1
    exit "$status"
}

telegram_progress() {
    is_true "$TG_NOTIFY" || return 0
    py_cli tg notify "$1" --seconds "$SECONDS" 2> /dev/null || warn "Telegram notification failed"
}

telegram_heartbeat() {
    local sleep_pid=""

    trap 'if [[ -n $sleep_pid ]]; then
        kill "$sleep_pid" 2> /dev/null || true
        wait "$sleep_pid" 2> /dev/null || true
    fi
    exit 0' TERM

    while true; do
        sleep 60 &
        sleep_pid=$!
        wait "$sleep_pid" || break
        sleep_pid=""

        # Bash defers TERM handling until the foreground notification returns.
        telegram_progress "$1"
    done
}

stop_telegram_progress() {
    if [[ -n ${TG_PROGRESS_PID:-} ]]; then
        kill "$TG_PROGRESS_PID" 2> /dev/null || true
        wait "$TG_PROGRESS_PID" 2> /dev/null || true
        unset TG_PROGRESS_PID
    fi
}

finalize_build() {
    local build_time="$1"
    success "Build success in $((build_time / 60))m $((build_time % 60))s"
    is_true "$TG_NOTIFY" || return 0
    py_cli tg notify success --seconds "$build_time" 2> /dev/null || warn "Telegram notification failed"
}
