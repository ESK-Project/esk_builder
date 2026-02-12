#!/usr/bin/env bash
#
# Personal ESK Kernel build script
#
set -Eeuo pipefail

# Workspace path
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$WORKSPACE/config.sh"

################################################################################
# Generic helpers
################################################################################

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[$(date '+%F %T')] [INFO]${NC} $*"; }
success() { echo -e "${GREEN}[$(date '+%F %T')] [SUCCESS]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%F %T')] [WARN]${NC} $*"; }

# Escape a string for Telegram MarkdownV2
escape_md_v2() {
    python3 - "$*" << 'PY'
import sys, re
s = sys.argv[1]
escaped = re.sub(r'([\\_*[\]()~`>#+\-=|{}.!])', r'\\\1', s)
print(escaped, end="")
PY
}

# Bool helpers
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

# ksu_branch <susfs_branch> <main_branch>
ksu_branch() {
    if is_true "$SUSFS"; then
        echo "$1"
    else
        echo "$2"
    fi
}

# Recreate directory
reset_dir() {
    local path="$1"
    [[ -d $path ]] && rm -rf -- "$path"
    mkdir -p -- "$path"
}

# Shallow clone host:owner/repo@branch into a destination
git_clone() {
    local source="$1"
    local dest="$2"
    local host repo branch
    [[ -d "$dest/.git" ]] && return 0
    IFS=':@' read -r host repo branch <<< "$source"
    git clone -q --depth=1 --single-branch --no-tags \
        "https://${host}/${repo}" -b "${branch}" "${dest}"
}

################################################################################
# Telegram helpers
################################################################################

# Generate random build tags for Telegram
BUILD_TAG="kernel_$(hexdump -v -e '/1 "%02x"' -n4 /dev/urandom)"
info "Build tag generated: $BUILD_TAG"

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
    shift
    printf '%s' "$*" | python3 "$TG_PY" doc "$file"
}

################################################################################
# Error handling
################################################################################

error() {
    trap - ERR
    echo -e "${RED}[$(date '+%F %T')] [ERROR]${NC} $*" >&2

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

trap 'error "Build failed at line $LINENO: $BASH_COMMAND"' ERR

################################################################################
# Build configuration
################################################################################

# --- Kernel flavour
# Kernel flavour: VNL | KSU
KSU="${KSU:-VNL}"
# Include SuSFS?
SUSFS="$(norm_bool "${SUSFS:-false}")"
# Apply LXC patch?
LXC="$(norm_bool "${LXC:-false}")"

# --- Paths
KERNEL_PATCHES="$WORKSPACE/kernel_patches"
CLANG="$WORKSPACE/clang"
CLANG_BIN="$CLANG/bin"
SIGN_KEY="$WORKSPACE/key"
OUT_DIR="$WORKSPACE/out"
LOGFILE="$WORKSPACE/build.log"
BOOT_IMAGE="$WORKSPACE/boot_image"
BOOT_SIGN_KEY="$SIGN_KEY/boot_sign_key.pem"

# --- Sources (host:owner/repo@ref)
KERNEL_REPO="github.com:ESK-Project/android_kernel_xiaomi_mt6895@16"
KERNEL="$WORKSPACE/kernel"
ANYKERNEL_REPO="github.com:ESK-Project/AnyKernel3@android12-5.10"
ANYKERNEL="$WORKSPACE/anykernel3"
GKI_URL="https://dl.google.com/android/gki/gki-certified-boot-android12-5.10-2025-09_r1.zip"
BUILD_TOOLS_REPO="android.googlesource.com:kernel/prebuilts/build-tools@main-kernel-build-2024"
BUILD_TOOLS="$WORKSPACE/build-tools"
MKBOOTIMG_REPO="android.googlesource.com:platform/system/tools/mkbootimg@main-kernel-build-2024"
MKBOOTIMG="$WORKSPACE/mkbootimg"

KERNEL_OUT="$KERNEL/out"

# --- Make arguments
MAKE_ARGS=(
    -j"$JOBS" O="$KERNEL_OUT" ARCH="arm64"
    CC="ccache clang" CROSS_COMPILE="aarch64-linux-gnu-"
    LLVM="1" LD="$CLANG_BIN/ld.lld"
)

################################################################################
# Initialize build environment
################################################################################

# Default setup
if is_ci; then
    TG_NOTIFY="$(norm_default "${TG_NOTIFY-}" "true")"
    RESET_SOURCES="$(norm_default "${RESET_SOURCES-}" "true")"
else
    TG_NOTIFY="$(norm_default "${TG_NOTIFY-}" "false")"
    RESET_SOURCES="$(norm_default "${RESET_SOURCES-}" "false")"
fi

info "Mode: $(is_ci && echo CI || echo local)"

# Set timezone
export TZ="$TIMEZONE"

# Convenient variable 
ksu_included="true"
[[ $KSU == "VNL" ]] && ksu_included="false"

################################################################################
# Feature-specific helpers
################################################################################

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
# Build steps
################################################################################

init_logging() {
    exec > >(tee -a "$LOGFILE") 2>&1
}

validate_env() {
    info "Validating environment variables..."
    if [[ -z ${GH_TOKEN:-} ]]; then
        if [[ -x "$CLANG_BIN/clang" ]]; then
            :
        elif is_ci; then
            error "Required Github PAT missing: GH_TOKEN"
        else
            warn "GH_TOKEN not set. Github requests may be rate-limited."
        fi
    fi

    if is_true "$TG_NOTIFY"; then
        : "${TG_BOT_TOKEN:?Required Telegram Bot Token missing: TG_BOT_TOKEN}"
        : "${TG_CHAT_ID:?Required chat ID missing: TG_CHAT_ID}"
    fi

    # For the python telegram util
    if is_true "$TG_NOTIFY"; then
        export TG_BOT_TOKEN
        export TG_CHAT_ID
    fi

    # Config checks
    if is_true "$SUSFS" && [[ "$KSU" == "VNL" ]]; then
        error "Cannot use SUSFS without KernelSU"
    fi
}

send_start_msg() {
    local start_msg
    start_msg=$(
        cat << EOF
🚧 *$(escape_md_v2 "$KERNEL_NAME Kernel Build Started!")*

🏷️ *Tags*: \#$(escape_md_v2 "$BUILD_TAG")
$(tg_run_line)

🧱 *Build Info*
├ Builder: $(escape_md_v2 "$KBUILD_BUILD_USER@$KBUILD_BUILD_HOST")
├ Defconfig: $(escape_md_v2 "$KERNEL_DEFCONFIG")
└ Jobs: $(escape_md_v2 "$JOBS")

⚙️ *Features*
├ KernelSU: $(parse_bool "$ksu_included")
├ SuSFS: $(parse_bool "$SUSFS")
└ LXC: $(parse_bool "$LXC")
EOF
    )
    telegram_send_msg "$start_msg"
}

prepare_dirs() {
    OUT_DIR_LIST=(
        "$OUT_DIR" "$BOOT_IMAGE" "$ANYKERNEL"
    )
    SRC_DIR_LIST=(
        "$KERNEL" "$BUILD_TOOLS"
        "$MKBOOTIMG" "$WORKSPACE/susfs"
    )

    info "Resetting output directories: $(printf '%s ' "${OUT_DIR_LIST[@]##*/}")"
    for dir in "${OUT_DIR_LIST[@]}"; do
        reset_dir "$dir"
    done

    if is_true "$RESET_SOURCES"; then
        info "Resetting source directories: $(printf '%s ' "${SRC_DIR_LIST[@]##*/}")"
        for dir in "${SRC_DIR_LIST[@]}"; do
            reset_dir "$dir"
        done
    fi
}

fetch_sources() {
    info "Cloning kernel source..."
    git_clone "$KERNEL_REPO" "$KERNEL"

    info "Cloning AnyKernel3..."
    git_clone "$ANYKERNEL_REPO" "$ANYKERNEL"

    info "Cloning build tools..."
    git_clone "$BUILD_TOOLS_REPO" "$BUILD_TOOLS"
    git_clone "$MKBOOTIMG_REPO" "$MKBOOTIMG"
}

setup_toolchain() {
    _use_toolchain() {
        export PATH="$CLANG_BIN:$PATH"
        COMPILER_STRING="$("$CLANG_BIN/clang" --version | head -n 1 | sed 's/(https..*//')"
        export KBUILD_BUILD_USER KBUILD_BUILD_HOST
    }

    if [[ -x "$CLANG_BIN/clang" ]]; then
        info "Using existing AOSP Clang toolchain"
        _use_toolchain
        return 0
    fi

    info "Fetching AOSP Clang toolchain"
    local clang_url
    local auth_header=()
    [[ -n ${GH_TOKEN:-} ]] && auth_header=(-H "Authorization: Bearer $GH_TOKEN")
    clang_url=$(curl -fsSL "https://api.github.com/repos/bachnxuan/aosp_clang_mirror/releases/latest" \
        "${auth_header[@]}" \
        | grep "browser_download_url" \
        | grep ".tar.gz" \
        | cut -d '"' -f 4)

    mkdir -p "$CLANG"

    local attempt=0
    local retries=5
    local aria_opts=(
        -q -c -x16 -s16 -k8M
        --file-allocation=falloc --check-certificate=false
        -d "$WORKSPACE" -o "clang-archive" "$clang_url"
    )

    while ((attempt < retries)); do
        if aria2c "${aria_opts[@]}"; then
            success "Clang download successful!"
            break
        fi

        ((attempt++))
        warn "Clang download attempt $attempt/$retries failed, retrying..."
        ((attempt < retries)) && sleep 5
    done

    if ((attempt == retries)); then
        error "Clang download failed after $retries attempts!"
    fi

    tar -xzf "$WORKSPACE/clang-archive" -C "$CLANG"
    rm -f "$WORKSPACE/clang-archive"

    _use_toolchain
}

apply_susfs() {
    info "Apply SuSFS kernel-side patches"

    local SUSFS_DIR="$WORKSPACE/susfs"
    local SUSFS_PATCHES="$SUSFS_DIR/kernel_patches"
    local SUSFS_BRANCH=gki-android12-5.10

    git_clone "gitlab.com:simonpunk/susfs4ksu@$SUSFS_BRANCH" "$SUSFS_DIR"
    cp -R "$SUSFS_PATCHES"/fs/* ./fs
    cp -R "$SUSFS_PATCHES"/include/* ./include

    patch -s -p1 --fuzz=3 --no-backup-if-mismatch < "$SUSFS_PATCHES"/50_add_susfs_in_gki-android*-*.patch
    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')

    config --enable CONFIG_KSU_SUSFS

    success "SuSFS applied!"
}

prepare_build() {
    cd "$KERNEL"

    # Defconfig existence check
    DEFCONFIG_FILE="$KERNEL/arch/arm64/configs/$KERNEL_DEFCONFIG"
    [[ -f $DEFCONFIG_FILE ]] || error "Defconfig not found: $KERNEL_DEFCONFIG"

    if is_true "$ksu_included"; then
        info "Setup KernelSU"
        install_ksu ESK-Project/ReSukiSU "main"
        config --enable CONFIG_KSU
        success "KernelSU added"
    fi

    # SuSFS
    if is_true "$SUSFS"; then
        apply_susfs
    else
        config --disable CONFIG_KSU_SUSFS
    fi

    # LXC
    if is_true "$LXC"; then
        info "Apply LXC patch"
        patch -s -p1 --fuzz=3 --no-backup-if-mismatch < "$KERNEL_PATCHES/lxc_support.patch"
        success "LXC patch applied"
    fi

    # Config Clang LTO
    clang_lto "$CLANG_LTO"
}

build_kernel() {
    cd "$KERNEL"

    info "Generate defconfig: $KERNEL_DEFCONFIG"
    make "${MAKE_ARGS[@]}" "$KERNEL_DEFCONFIG" > /dev/null 2>&1
    success "Defconfig generated"

    make "${MAKE_ARGS[@]}" Image
    success "Kernel built successfully"

    KERNEL_VERSION=$(make -s kernelversion | cut -d- -f1)
}

package_anykernel() {
    local package_name="$1"

    info "Packaging AnyKernel3 zip..."
    pushd "$ANYKERNEL" > /dev/null

    cp -p "$KERNEL_OUT/arch/arm64/boot/Image" "$ANYKERNEL"/

    info "Compressing kernel image..."
    zstd -19 -T0 --no-progress -o Image.zst Image > /dev/null 2>&1
    rm -f ./Image
    sha256sum Image.zst > Image.zst.sha256

    zip -r9q -T -X -y -n .zst "$OUT_DIR/$package_name-AnyKernel3.zip" . -x '.git/*' '*.log'

    popd > /dev/null
    success "AnyKernel3 packaged"
}

package_bootimg() {
    local package_name="$1"
    info "Packaging boot image..."

    pushd "$BOOT_IMAGE" > /dev/null

    cp -p "$KERNEL_OUT/arch/arm64/boot/Image" ./Image
    gzip -n -f -9 Image

    curl -fsSLo gki-kernel.zip "$GKI_URL"
    unzip gki-kernel.zip > /dev/null 2>&1 && rm gki-kernel.zip

    "$MKBOOTIMG/unpack_bootimg.py" --boot_img="boot-5.10.img"
    "$MKBOOTIMG/mkbootimg.py" \
        --header_version 4 \
        --kernel Image.gz \
        --output boot.img \
        --ramdisk out/ramdisk \
        --os_version 12.0.0 \
        --os_patch_level "2099-12"
    "$BUILD_TOOLS/linux-x86/bin/avbtool" add_hash_footer \
        --partition_name boot \
        --partition_size $((64 * 1024 * 1024)) \
        --image boot.img \
        --algorithm SHA256_RSA4096 \
        --key "$BOOT_SIGN_KEY"

    cp "$BOOT_IMAGE/boot.img" "$OUT_DIR/$package_name-boot.img"

    popd > /dev/null
}

write_metadata() {
    local package_name="$1"
    cat > "$WORKSPACE/github.env" << EOF
kernel_version=$KERNEL_VERSION
kernel_name=$KERNEL_NAME
toolchain=$COMPILER_STRING
package_name=$package_name
variant=$VARIANT
name=$KERNEL_NAME
out_dir=$OUT_DIR
release_repo=$RELEASE_REPO
release_branch=$RELEASE_BRANCH
EOF
}

notify_success() {
    local final_package="$1"
    local build_time="$2"
    # For indicating build variant (AnyKernel3, Boot Image)
    local additional_tag="$3"

    local minutes=$((build_time / 60))
    local seconds=$((build_time % 60))

    local result_caption
    result_caption=$(
        cat << EOF
✅ *$(escape_md_v2 "$KERNEL_NAME Build Successfully!")*

🏷️ *Tags*: \#$(escape_md_v2 "$BUILD_TAG") \#$(escape_md_v2 "$additional_tag")
$(tg_run_line)

🧱 *Build*
├ Builder: $(escape_md_v2 "$KBUILD_BUILD_USER@$KBUILD_BUILD_HOST")
└ Build time: $(escape_md_v2 "${minutes}m ${seconds}s")

🐧 *Kernel*
├ Linux version: $(escape_md_v2 "$KERNEL_VERSION")
└ Compiler: $(escape_md_v2 "$COMPILER_STRING")

📦 *Options*
├ KernelSU: $(parse_bool "$ksu_included")
├ SuSFS: $(is_true "$SUSFS" && escape_md_v2 "$SUSFS_VERSION" || echo "Disabled")
└ LXC: $(parse_bool "$LXC")
EOF
    )

    telegram_upload_file "$final_package" "$result_caption"
}

telegram_notify() {
    local build_time="$1"

    # AnyKernel3
    local ak3_package="$OUT_DIR/$PACKAGE_NAME-AnyKernel3.zip"
    notify_success "$ak3_package" "$build_time" "anykernel3"

    # Boot image
    pushd "$OUT_DIR" > /dev/null
    zip -9q -T "$PACKAGE_NAME-boot.zip" "$PACKAGE_NAME-boot.img"
    popd > /dev/null

    notify_success "$OUT_DIR/$PACKAGE_NAME-boot.zip" "$build_time" "boot_image"
    rm -f "$OUT_DIR/$PACKAGE_NAME-boot.zip"
}

################################################################################
# Main
################################################################################

main() {
    SECONDS=0

    init_logging
    validate_env
    send_start_msg
    prepare_dirs
    fetch_sources
    setup_toolchain
    prepare_build
    build_kernel

    # Build package name
    VARIANT="$KSU"
    is_true "$SUSFS" && VARIANT+="-SUSFS"
    is_true "$LXC" && VARIANT+="-LXC"
    PACKAGE_NAME="$KERNEL_NAME-$KERNEL_VERSION-$VARIANT"

    # Build flashable package
    package_anykernel "$PACKAGE_NAME"
    package_bootimg "$PACKAGE_NAME"

    # Github Actions metadata
    write_metadata "$PACKAGE_NAME"

    local build_time="$SECONDS"

    if is_true "$TG_NOTIFY"; then
        telegram_notify "$build_time"
    else
        local min=$((build_time / 60))
        local sec=$((build_time % 60))
        success "Build success in ${min}m ${sec}s"
    fi
}

main "$@"
