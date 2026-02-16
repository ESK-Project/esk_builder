# shellcheck shell=bash

################################################################################
# Utility functions
################################################################################

# Logging
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
    local index="$1"
    local message="$2"
    local total=13
    printf '%b\n' "${BOLD}[$(date '+%F %T')] [STEP ${index}/${total}] ${message}${NC}"
}

# Escape text for MarkdownV2
escape_md_v2() {
    python3 - "$*" << 'PY'
import re
import sys

s = sys.argv[1]
escaped = re.sub(r'([\\_*[\]()~`>#+\-=|{}.!])', r'\\\1', s)
print(escaped, end="")
PY
}

# Boolean helpers
norm_bool() {
    local value=$1
    case "${value,,}" in
        1 | y | yes | t | true | on) echo "true" ;;
        0 | n | no | f | false | off) echo "false" ;;
        *) echo "false" ;;
    esac
}

is_true() {
    [[ $1 == true ]]
}

parse_bool() {
    if is_true "$1"; then
        echo "Enabled"
    else
        echo "Disabled"
    fi
}

# Normalize bool from input value, defaulting if empty
norm_default() {
    local value="${1:-$2}"
    norm_bool "$value"
}

# Check if script is running in Github Action
is_ci() {
    [[ ${GITHUB_ACTIONS:-} == "true" ]]
}

# Recreate directory
reset_dir() {
    local path="$1"
    [[ -d $path ]] && rm -rf -- "$path"
    mkdir -p -- "$path"
}

# Shallow clone repository into a destination
git_clone() {
    local source="$1"
    local dest="$2"
    local host repo branch
    [[ -d "$dest/.git" ]] && return 0
    IFS=':@' read -r host repo branch <<< "$source"
    git clone -q --depth=1 --single-branch --no-tags \
        "https://${host}/${repo}" -b "${branch}" "${dest}"
}

# Setup KernelSU
install_ksu() {
    local repo="$1"
    local ref="$2"
    info "Install KernelSU: $repo@$ref"
    curl -fsSL "https://raw.githubusercontent.com/$repo/$ref/kernel/setup.sh" | bash -s "$ref"
}

# Wrapper for scripts/config
config() {
    "$KERNEL/scripts/config" --file "$KERNEL/arch/arm64/configs/$KERNEL_DEFCONFIG" "$@"
}

clang_lto() {
    config --enable CONFIG_LTO_CLANG
    case "$1" in
        thin)
            config --enable CONFIG_LTO_CLANG_THIN
            config --disable CONFIG_LTO_CLANG_FULL
            ;;
        full)
            config --enable CONFIG_LTO_CLANG_FULL
            config --disable CONFIG_LTO_CLANG_THIN
            ;;
        *)
            warn "Unknown LTO mode, using thin"
            config --enable CONFIG_LTO_CLANG_THIN
            config --disable CONFIG_LTO_CLANG_FULL
            ;;
    esac
}

################################################################################
# Error handling
################################################################################

error() {
    trap - ERR
    printf '%b\n' "${RED}[$(date '+%F %T')] [ERROR]${NC} $*" >&2

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
