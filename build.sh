#!/usr/bin/env bash
#
# Personal ESK Kernel build script
#
set -Ee

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
    IFS=':@' read -r host repo branch <<< "$source"
    git clone -q --depth=1 --single-branch --no-tags \
        "https://${host}/${repo}" -b "${branch}" "${dest}"
}

################################################################################
# Telegram helpers
################################################################################

TG_NOTIFY="$(norm_bool "${TG_NOTIFY:-true}")"

# Generate random build tags for Telegram
BUILD_TAG="kernel_$(hexdump -v -e '/1 "%02x"' -n4 /dev/urandom)"
info "Build tag generated: $BUILD_TAG"

# Telegram python utils path
TG_PY="$WORKSPACE/py/tg.py"

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
*$(escape_md_v2 "$KERNEL_NAME Kernel CI")*

*Tags*: \#$(escape_md_v2 "$BUILD_TAG") \#error

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
# KernelSU variant: NONE | RKSU | NEXT | SUKI
KSU="${KSU:-NONE}"
# Include SuSFS?
SUSFS="$(norm_bool "${SUSFS:-false}")"
# Apply LXC patch?
LXC="$(norm_bool "${LXC:-false}")"
# Include BBG?
BBG="$(norm_bool "${BBG:-false}")"

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

# Set timezone
sudo timedatectl set-timezone "$TIMEZONE" || export TZ="$TIMEZONE"

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
    local cfg="$KERNEL_OUT/.config"
    if [[ -f $cfg ]]; then
        "$KERNEL/scripts/config" --file "$cfg" "$@"
    else
        "$KERNEL/scripts/config" --file "$KERNEL/arch/arm64/configs/$KERNEL_DEFCONFIG" "$@"
    fi
}

regenerate_defconfig() {
    make "${MAKE_ARGS[@]}" -s olddefconfig
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
    regenerate_defconfig
}

################################################################################
# Build steps
################################################################################

init_logging() {
    exec > >(tee >(sed -u -r 's/\033\[[0-9;]*[A-Za-z]//g' > "$LOGFILE")) 2>&1
}

validate_env() {
    info "Validating environment variables..."
    : "${GH_TOKEN:?Required GitHub PAT missing: GH_TOKEN}"
    if is_true "$TG_NOTIFY"; then
        : "${TG_BOT_TOKEN:?Required Telegram Bot Token missing: TG_BOT_TOKEN}"
        : "${TG_CHAT_ID:?Required chat ID missing: TG_CHAT_ID}"
    fi

    # For the python telegram util
    export TG_BOT_TOKEN
    export TG_CHAT_ID
}

send_start_msg() {
    local ksu_included="true"
    [[ $KSU == "NONE" ]] && ksu_included="false"

    local start_msg
    start_msg=$(
        cat << EOF
*$(escape_md_v2 "$KERNEL_NAME Kernel Build Started!")*

*Tags*: \#$(escape_md_v2 "$BUILD_TAG")

*Build info*
├ Builder: $(escape_md_v2 "$KBUILD_BUILD_USER@$KBUILD_BUILD_HOST")
├ Defconfig: $(escape_md_v2 "$KERNEL_DEFCONFIG")
└ Jobs: $(escape_md_v2 "$JOBS")

*Build options*
├ KernelSU: $(escape_md_v2 "$(parse_bool "$ksu_included") | $KSU")
├ SuSFS: $(parse_bool "$SUSFS")
├ BBG: $(parse_bool "$BBG")
└ LXC: $(parse_bool "$LXC")
EOF
    )
    telegram_send_msg "$start_msg"
}

prepare_dirs() {
    RESET_DIR_LIST=(
        "$KERNEL" "$ANYKERNEL" "$BUILD_TOOLS"
        "$MKBOOTIMG" "$OUT_DIR" "$BOOT_IMAGE"
        "$WORKSPACE/susfs" "$WORKSPACE/wild_patches"
    )
    info "Resetting directories: ${RESET_DIR_LIST[*]}"
    for dir in "${RESET_DIR_LIST[@]}"; do
        reset_dir "$dir"
    done
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
    info "Fetching AOSP Clang toolchain"
    local clang_url
    clang_url=$(curl -fsSL "https://api.github.com/repos/bachnxuan/aosp_clang_mirror/releases/latest" \
        -H "Authorization: Bearer $GH_TOKEN" \
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

    export PATH="${CLANG_BIN}:$PATH"

    COMPILER_STRING="$("$CLANG_BIN/clang" -v 2>&1 | head -n 1 | sed 's/(https..*//')"
    KBUILD_BUILD_TIMESTAMP="$(date +"%a %d %b %H:%M")"
    export KBUILD_BUILD_TIMESTAMP
    export KBUILD_BUILD_USER
    export KBUILD_BUILD_HOST
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

    cd "$KERNEL"
    config --enable CONFIG_KSU_SUSFS
    config --disable CONFIG_KSU_SUSFS_SPOOF_UNAME

    success "SuSFS applied!"
}

prebuild_kernel() {
    cd "$KERNEL"

    # Defconfig existence check
    DEFCONFIG_FILE="$KERNEL/arch/arm64/configs/$KERNEL_DEFCONFIG"
    [[ -f $DEFCONFIG_FILE ]] || error "Defconfig not found: $KERNEL_DEFCONFIG"

    # KernelSU
    local ksu_included="true"
    [[ $KSU == "NONE" ]] && ksu_included="false"

    if is_true "$ksu_included"; then
        info "Setup KernelSU"
        case "$KSU" in
            RKSU) install_ksu rsuntk/KernelSU "$(ksu_branch "susfs-rksu-master" "main")" ;;
            NEXT) install_ksu pershoot/KernelSU-Next "$(ksu_branch "dev-susfs" "dev")" ;;
            SUKI) install_ksu SukiSU-Ultra/SukiSU-Ultra "$(ksu_branch "builtin" "main")" ;;
        esac
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

    # BBG
    if is_true "$BBG"; then
        info "Setup Baseband Guard (BBG) LSM"
        wget -qO- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash > /dev/null 2>&1
        sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/bpf/bpf,baseband_guard/ } }' security/Kconfig
        config --enable CONFIG_BBG
        success "Added BBG"
    fi
}

build_kernel() {
    cd "$KERNEL"

    SECONDS=0

    info "Generate defconfig: $KERNEL_DEFCONFIG"
    make "${MAKE_ARGS[@]}" "$KERNEL_DEFCONFIG" > /dev/null 2>&1
    success "Defconfig generated"

    clang_lto "$CLANG_LTO"

    make "${MAKE_ARGS[@]}" Image
    success "Kernel built successfully"

    KERNEL_VERSION=$(make -s kernelversion | cut -d- -f1)
}

kpm_patcher() {
    if [[ $KSU == "SUKI" ]]; then
        info "Patching KPM for SukiSU variant..."
        tmp="$(mktemp -d)" && cd "$tmp"
        cp -p "$KERNEL_OUT/arch/arm64/boot/Image" "$tmp"/

        KPM_PATCHER="https://github.com/SukiSU-Ultra/SukiSU_patch/raw/refs/heads/main/kpm/patch_linux"
        curl -fsSL "$KPM_PATCHER" -o patch_linux

        chmod +x ./patch_linux
        ./patch_linux > /dev/null 2>&1

        [[ -f oImage ]] || error "patch_linux failed to produce patched Image"
        mv oImage "$ANYKERNEL/Image"

        # Clean-up
        rm -rf ./patch_linux
        cd "$ANYKERNEL"
        rm -rf "$tmp"
        success "Patched KPM for SukiSU variant"
    else
        cp -p "$KERNEL_OUT/arch/arm64/boot/Image" "$ANYKERNEL"/
    fi
}

package_anykernel() {
    local package_name="$1"

    info "Packaging AnyKernel3 zip..."
    pushd "$ANYKERNEL" > /dev/null

    # Patch KPM for SukiSU variant
    # kpm_patcher() will copy the Image to AnyKernel folder
    kpm_patcher

    info "Compressing kernel image..."
    zstd -19 -T0 --no-progress -o Image.zst Image > /dev/null 2>&1
    rm -f ./Image
    sha256sum Image.zst > Image.zst.sha256

    info "[UPX] Compressing AnyKernel3 static binaries..."
    local UPX_LIST=(
        tools/zstd
        tools/fec
        tools/httools_static
        tools/lptools_static
        tools/magiskboot
        tools/magiskpolicy
        tools/snapshotupdater_static
    )
    for binary in "${UPX_LIST[@]}"; do
        local file="$ANYKERNEL/$binary"
        [[ -f $file ]] || {
            warn "[UPX] Binary not found: $binary"
            continue
        }
        if upx -9 --lzma --no-progress "$file" > /dev/null 2>&1; then
            success "[UPX] Compressed: $(basename "$binary")"
        else
            warn "[UPX] Failed: $(basename "$binary")"
        fi
    done

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
        --os_patch_level "2099-12" \
        && "$BUILD_TOOLS/linux-x86/bin/avbtool" add_hash_footer \
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
build_date=$KBUILD_BUILD_TIMESTAMP
package_name=$package_name
susfs_version=$SUSFS_VERSION
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
*$(escape_md_v2 "$KERNEL_NAME Build Successfully!")*

*Tags*: \#$(escape_md_v2 "$BUILD_TAG") \#$(escape_md_v2 "$additional_tag")

*Build*
├ Builder: $(escape_md_v2 "$KBUILD_BUILD_USER@$KBUILD_BUILD_HOST")
├ Build time: $(escape_md_v2 "${minutes}m ${seconds}s")
└ Build date: $(escape_md_v2 "$KBUILD_BUILD_TIMESTAMP")

*Kernel*
├ Linux version: $(escape_md_v2 "$KERNEL_VERSION")
└ Compiler: $(escape_md_v2 "$COMPILER_STRING")

*Options*
├ KernelSU: $(escape_md_v2 "$KSU")
├ SuSFS: $(is_true "$SUSFS" && escape_md_v2 "$SUSFS_VERSION" || echo "Disabled")
├ BBG: $(parse_bool "$BBG")
└ LXC: $(parse_bool "$LXC")

*Artifact*
├ Name: $(escape_md_v2 "$(basename "$final_package")")
└ Size: $(escape_md_v2 "$(du -h "$final_package" | cut -f1)")
EOF
    )

    telegram_upload_file "$final_package" "$result_caption"
}

telegram_notify() {
    local build_time="$SECONDS"

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
    init_logging
    validate_env
    send_start_msg
    prepare_dirs
    fetch_sources
    setup_toolchain
    prebuild_kernel
    build_kernel

    # Build package name
    VARIANT="$KSU"
    is_true "$SUSFS" && VARIANT+="-SUSFS"
    is_true "$LXC" && VARIANT+="-LXC"
    is_true "$BBG" && VARIANT+="-BBG"
    PACKAGE_NAME="$KERNEL_NAME-$KERNEL_VERSION-$VARIANT"

    # Build flashable package
    package_anykernel "$PACKAGE_NAME"
    package_bootimg "$PACKAGE_NAME"

    # Github Actions metadata
    write_metadata "$PACKAGE_NAME"

    if is_true "$TG_NOTIFY"; then
        telegram_notify
    fi
}

main "$@"
