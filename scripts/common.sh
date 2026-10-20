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
