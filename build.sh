#!/usr/bin/env bash
#
# Personal ESK Kernel build script
#

set -Ee

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
    local s=$*
    s=${s//\\/\\\\}
    s=${s//_/\\_}
    s=${s//\*/\\*}
    s=${s//\[/\\[}
    s=${s//\]/\\]}
    s=${s//\(/\\(}
    s=${s//\)/\\)}
    s=${s//~/\\~}
    s=${s//\`/\\\`}
    s=${s//>/\\>}
    s=${s//#/\\#}
    s=${s//+/\\+}
    s=${s//-/\\-}
    s=${s//=/\\=}
    s=${s//|/\\|}
    s=${s//\{/\\\{}
    s=${s//\}/\\\}}
    s=${s//\./\\.}
    s=${s//\!/\\!}
    echo "$s"
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

parse_bool() {
    if [[ $1 == "true" ]]; then
        echo "Enabled"
    else
        echo "Disabled"
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
    IFS=':@' read -r host repo branch <<<"$source"
    git clone -q --depth=1 --single-branch --no-tags \
        "https://${host}/${repo}" -b "${branch}" "${dest}"
}

################################################################################
# Telegram helpers
################################################################################

TG_NOTIFY="$(norm_bool "${TG_NOTIFY:-true}")"

telegram_send_msg() {
    local text=$1
    local resp err

    [[ $TG_NOTIFY == false ]] && return 0

    resp=$(curl -sX POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d parse_mode="MarkdownV2" \
        -d disable_web_page_preview=true \
        -d text="$text")

    if ! echo "$resp" | jq -e '.ok == true' >/dev/null; then
        err=$(echo "$resp" | jq -r '.description')
        echo -e "${RED}[$(date '+%F %T')] [ERROR] telegram_send_msg(): ${err:-Unknown error}" >&2
    fi
}

telegram_upload_file() {
    local file="$1"
    local caption="$2"
    local resp err

    [[ $TG_NOTIFY == false ]] && return 0

    resp=$(curl -sX POST -F document=@"$file" \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F "chat_id=${TG_CHAT_ID}" \
        -F "parse_mode=MarkdownV2" \
        -F "caption=$caption")

    if ! echo "$resp" | jq -e '.ok == true' >/dev/null; then
        err=$(echo "$resp" | jq -r '.description')
        echo -e "${RED}[$(date '+%F %T')] [ERROR] telegram_upload_file(): ${err:-Unknown error}" >&2
    fi
}

################################################################################
# Error handling
################################################################################

error() {
    trap - ERR
    echo -e "${RED}[$(date '+%F %T')] [ERROR]${NC} $*" >&2

    local msg
    msg=$(
        cat <<EOF
*$(escape_md_v2 "$KERNEL_NAME Kernel CI")*
$(escape_md_v2 "ERROR: $*")
EOF
    )

    telegram_send_msg "$msg"
    telegram_upload_file "$LOGFILE" "Build log"
    exit 1
}

trap 'error "Build failed at line $LINENO: $BASH_COMMAND"' ERR

################################################################################
# Build configuration
################################################################################

# General
KERNEL_NAME="ESK"
KERNEL_DEFCONFIG="gki_defconfig"
KBUILD_BUILD_USER="builder"
KBUILD_BUILD_HOST="esk"
TIMEZONE="Asia/Ho_Chi_Minh"
RELEASE_REPO="ESK-Project/esk-releases"
RELEASE_BRANCH="main"

# --- Kernel flavour
# KernelSU variant: NONE | OFFICIAL | NEXT | SUKI
KSU="${KSU:-NONE}"
# Include SuSFS?
SUSFS="$(norm_bool "${SUSFS:-false}")"
# Apply LXC patch?
LXC="$(norm_bool "${LXC:-false}")"
BBG="$(norm_bool "${BBG:-false}")"

# --- Compiler
# Clang LTO mode: thin | full
CLANG_LTO="thin"
# Parallel build jobs
JOBS="$(nproc --all)"

# --- Paths
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Generate random build tags
BUILD_TAG="kernel_$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)"

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
    # Stream to file and console
    exec > >(tee "$LOGFILE") 2>&1
}

validate_env() {
    info "Validating environment variables..."
    : "${GH_TOKEN:?Required GitHub PAT missing: GH_TOKEN}"
    if [[ "$TG_NOTIFY" == true ]]; then
        : "${TG_BOT_TOKEN:?Required Telegram Bot Token missing: TG_BOT_TOKEN}"
        : "${TG_CHAT_ID:?Required chat ID missing: TG_CHAT_ID}"
    fi
}

send_start_msg() {
    local ksu_included="true"
    [[ $KSU == "NONE" ]] && ksu_included="false"

    local start_msg
    start_msg=$(
        cat <<EOF
*$(escape_md_v2 "$KERNEL_NAME Kernel Build Started!")*

*Tags*: \#$(escape_md_v2 "$BUILD_TAG")

*Build info*
├ Builder: $(escape_md_v2 "$KBUILD_BUILD_USER@$KBUILD_BUILD_HOST")
├ Defconfig: $(escape_md_v2 "$KERNEL_DEFCONFIG")
└ Jobs: $(escape_md_v2 "$JOBS")

*Build options*
├ KernelSU: $(escape_md_v2 "$(parse_bool "$ksu_included") | $KSU")
├ SuSFS: $(parse_bool "$SUSFS")
└ LXC: $(parse_bool "$LXC")
EOF
    )
    telegram_send_msg "$start_msg"
}

prepare_dirs() {
    RESET_DIR_LIST=("$KERNEL" "$ANYKERNEL" "$BUILD_TOOLS" "$MKBOOTIMG" "$OUT_DIR" "$BOOT_IMAGE")
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
        else
            warn "Clang download attempt $attempt failed, retrying..."
            ((attempt++))
            sleep 5
        fi
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

prebuild_kernel() {
    cd "$KERNEL"

    # Defconfig existence check (for config())
    DEFCONFIG_FILE="$KERNEL/arch/arm64/configs/$KERNEL_DEFCONFIG"
    [[ -f $DEFCONFIG_FILE ]] || error "Defconfig not found: $KERNEL_DEFCONFIG"

    # KernelSU
    local ksu_included="true"
    [[ $KSU == "NONE" ]] && ksu_included="false"

    if [[ $ksu_included == "true" ]]; then
        info "Setup KernelSU"
        case "$KSU" in
            OFFICIAL) install_ksu tiann/KernelSU main ;;
            NEXT) install_ksu KernelSU-Next/KernelSU-Next next ;;
            SUKI)
                install_ksu SukiSU-Ultra/SukiSU-Ultra "$([[ $SUSFS == "true" ]] && echo "susfs-main" || echo "main")"
                ;;
        esac

        info "Configuring KernelSU"
        config --enable CONFIG_KSU

        if [[ $KSU == "SUKI" ]]; then
            patch -s -p1 --fuzz=3 --no-backup-if-mismatch <"$KERNEL_PATCHES/suki/manual_hooks.patch"
            config --enable CONFIG_KPM
            config --enable CONFIG_KSU_TRACEPOINT_HOOK
            config --enable CONFIG_HAVE_SYSCALL_TRACEPOINTS
        elif [[ $KSU == "NEXT" ]]; then
            patch -s -p1 --fuzz=3 --no-backup-if-mismatch <"$KERNEL_PATCHES/next/manual_hooks.patch"
            config --disable CONFIG_KSU_KPROBES_HOOK
        fi

        success "KernelSU added"
    fi

    # SuSFS
    if [[ $SUSFS == "true" ]]; then
        info "Apply SuSFS kernel-side patches"
        local SUSFS_DIR="$WORKSPACE/susfs"
        local SUSFS_PATCHES="$SUSFS_DIR/kernel_patches"
        local SUSFS_BRANCH=gki-android12-5.10
        git_clone "gitlab.com:simonpunk/susfs4ksu@$SUSFS_BRANCH" "$SUSFS_DIR"
        cp -R "$SUSFS_PATCHES"/fs/* ./fs
        cp -R "$SUSFS_PATCHES"/include/* ./include
        patch -s -p1 --fuzz=3 --no-backup-if-mismatch <"$SUSFS_PATCHES"/50_add_susfs_in_gki-android*-*.patch
        SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')

        if [[ $KSU == "NEXT" || $KSU == "OFFICIAL" ]]; then
            case "$KSU" in
                NEXT) cd KernelSU-Next ;;
                OFFICIAL) cd KernelSU ;;
            esac
            info "Apply KernelSU-side SuSFS patches ($KSU)"
            patch -s -p1 --no-backup-if-mismatch <"$SUSFS_PATCHES/KernelSU/10_enable_susfs_for_ksu.patch" || true
            cd "$KERNEL"
        fi

        if [[ $KSU == "NEXT" ]]; then
            info "Apply SuSFS fix patches for KernelSU Next"
            local WILD_PATCHES="$WORKSPACE/wild_patches"
            local SUSFS_FIX_PATCHES="$WILD_PATCHES/next/susfs_fix_patches/$SUSFS_VERSION"
            git_clone "github.com:WildKernels/kernel_patches@main" "$WILD_PATCHES"
            [[ -d $SUSFS_FIX_PATCHES ]] || error "SuSFS fix patches are unavailable for SuSFS $SUSFS_VERSION"
            for p in "$SUSFS_FIX_PATCHES"/*.patch; do
                patch -s -p1 --no-backup-if-mismatch <"$p"
            done
        fi

        cd "$KERNEL"
        config --enable CONFIG_KSU_SUSFS

        if [[ $KSU == "SUKI" || $KSU == "NEXT" ]]; then
            config --disable CONFIG_KSU_SUSFS_SUS_SU
        fi
        success "SuSFS applied!"
    else
        config --disable CONFIG_KSU_SUSFS
    fi

    # LXC
    if [[ $LXC == "true" ]]; then
        info "Apply LXC patch"
        patch -s -p1 --fuzz=3 --no-backup-if-mismatch <"$KERNEL_PATCHES/lxc_support.patch"
        success "LXC patch applied"
    fi

    # BBG
    if [[ $BBG == "true" ]]; then
        info "Setup Baseband Guard (BBG) LSM for KernelSU variants"
        wget -qO- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash >/dev/null 2>&1
        sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/bpf/bpf,baseband_guard/ } }' security/Kconfig
        config --enable CONFIG_BBG
        success "Added BBG"
    fi
}

build_kernel() {
    cd "$KERNEL"

    SECONDS=0

    info "Generate defconfig: $KERNEL_DEFCONFIG"
    make "${MAKE_ARGS[@]}" "$KERNEL_DEFCONFIG" >/dev/null 2>&1
    success "Defconfig generated"

    clang_lto "$CLANG_LTO"

    make "${MAKE_ARGS[@]}" Image
    success "Kernel built successfully"

    KERNEL_VERSION=$(make -s kernelversion | cut -d- -f1)
}

package_anykernel() {
    local package_name="$1"

    info "Packaging AnyKernel3 zip..."
    pushd "$ANYKERNEL" >/dev/null

    cp -p "$KERNEL_OUT/arch/arm64/boot/Image" "$ANYKERNEL"/

    info "Compressing kernel image..."
    zstd -19 -T0 --no-progress -o Image.zst Image >/dev/null 2>&1
    rm -f ./Image
    sha256sum Image.zst >Image.zst.sha256

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
        if upx -9 --lzma --no-progress "$file" >/dev/null 2>&1; then
            success "[UPX] Compressed: $(basename "$binary")"
        else
            warn "[UPX] Failed: $(basename "$binary")"
        fi
    done

    zip -r9q -T -X -y -n .zst "$OUT_DIR/$package_name-AnyKernel3.zip" . -x '.git/*' '*.log'

    popd >/dev/null
    success "AnyKernel3 packaged"
}

package_bootimg() {
    local package_name="$1"
    info "Packaging boot image..."

    pushd "$BOOT_IMAGE" >/dev/null

    cp -p "$KERNEL_OUT/arch/arm64/boot/Image" ./Image
    gzip -n -f -9 Image

    curl -fsSLo gki-kernel.zip "$GKI_URL"
    unzip gki-kernel.zip >/dev/null 2>&1 && rm gki-kernel.zip

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

    popd >/dev/null
}

write_metadata() {
    local package_name="$1"
    cat >"$WORKSPACE/github.env" <<EOF
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
        cat <<EOF
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
├ SuSFS: $([[ $SUSFS == "true" ]] && escape_md_v2 "$SUSFS_VERSION" || echo "Disabled")
├ BBG: $(parse_bool "$BBG")
└ LXC: $(parse_bool "$LXC")

*Artifact*
├ Name: $(escape_md_v2 "$(basename "$final_package")")
└ Size: $(escape_md_v2 "$(du -h "$final_package" | cut -f1)")
EOF
    )

    telegram_upload_file "$final_package" "$result_caption"
    success "Build succeeded in ${minutes}m ${seconds}s"
}

telegram_notify() {
    local build_time="$SECONDS"

    # AnyKernel3
    local ak3_package="$OUT_DIR/$PACKAGE_NAME-AnyKernel3.zip"
    notify_success "$ak3_package" "$build_time" "anykernel3"

    # Boot image
    pushd "$OUT_DIR" >/dev/null
    zip -9q -T "$PACKAGE_NAME-boot.zip" "$PACKAGE_NAME-boot.img"
    popd >/dev/null

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
    [[ $SUSFS == "true" ]] && VARIANT+="-SUSFS"
    [[ $LXC == "true" ]] && VARIANT+="-LXC"
    [[ $BBG == "true" ]] && VARIANT+="-BBG"
    PACKAGE_NAME="$KERNEL_NAME-$KERNEL_VERSION-$VARIANT"

    # Build flashable package
    package_anykernel "$PACKAGE_NAME"
    package_bootimg "$PACKAGE_NAME"

    # Github Actions metadata
    write_metadata "$PACKAGE_NAME"

    [[ $TG_NOTIFY == "true" ]] && telegram_notify
}

main "$@"
