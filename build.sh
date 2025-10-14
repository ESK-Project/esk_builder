#!/usr/bin/env bash
#
# Kernel build script
#

set -Ee

### General helpers ################################################################

# ANSI colors constants
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Escape a string for Telegram MarkdownV2
escape_md_v2() {
    local s=$*
    s=${s//\\/\\\\}; s=${s//_/\\_};  s=${s//\*/\\*}; s=${s//\[/\\[}; s=${s//\]/\\]}
    s=${s//\(/\\(}; s=${s//\)/\\)}; s=${s//~/\\~}; s=${s//\`/\\\`}; s=${s//>/\\>}
    s=${s//#/\\#};  s=${s//+/\\+};  s=${s//-/\\-}; s=${s//= /\\=}; s=${s//=/\\=}; s=${s//|/\\|}
    s=${s//\{/\\\{}; s=${s//\}/\\\}}; s=${s//\./\\.}; s=${s//\!/\\!}
    echo "$s"
}

# Logging functions
info() { echo -e "${BLUE}[$(date '+%F %T')] [INFO]${NC} $*"; }
success() { echo -e "${GREEN}[$(date '+%F %T')] [SUCCESS]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%F %T')] [WARN]${NC} $*"; }

# Send a text message via Telegram Bot API
telegram_send_msg() {
    local resp err
    resp=$(curl -sX POST https://api.telegram.org/bot"${TG_BOT_TOKEN}"/sendMessage \
        -d chat_id="${TG_CHAT_ID}" \
        -d parse_mode="MarkdownV2" \
        -d disable_web_page_preview=true \
        -d text="$1")

    if ! echo "$resp" | jq -e '.ok == true' > /dev/null; then
        err=$(echo "$resp" | jq -r '.description')
        echo -e "${RED}[$(date '+%F %T')] [ERROR] telegram_send_msg(): failed to send message: ${err:-Unknown error} $*" >&2
        exit 1
    fi
}

# Upload a document with caption via Telegram Bot API
telegram_upload_file() {
    local resp err
    
    resp=$(curl -sX POST -F document=@"$1" https://api.telegram.org/bot"${TG_BOT_TOKEN}"/sendDocument \
        -F "chat_id=${TG_CHAT_ID}" \
        -F "parse_mode=MarkdownV2" \
        -F "caption=$2")

    if ! echo "$resp" | jq -e '.ok == true' > /dev/null; then
        err=$(echo "$resp" | jq -r '.description')
        echo -e "${RED}[$(date '+%F %T')] [ERROR] telegram_upload_file(): failed to upload file: ${err:-Unknown error}" >&2
        exit 1
    fi
}

# Unified error handler
error() {
    echo -e "${RED}[$(date '+%F %T')] [ERROR]${NC} $*" >&2

    local msg
    msg=$(
        cat << EOF
*$(escape_md_v2 "$KERNEL_NAME Kernel CI")*
$(escape_md_v2 "ERROR: $*")
EOF
    )
    telegram_send_msg "$msg"
    telegram_upload_file "$LOGFILE" "Build log"
    exit 1
}

### Configuration ##################################################################

# --- General
KERNEL_NAME="ESK"
KERNEL_DEFCONFIG="gki_defconfig"
KBUILD_BUILD_USER="builder"
KBUILD_BUILD_HOST="esk"
TIMEZONE="Asia/Ho_Chi_Minh"

# --- Kernel flavour
_norm_bool() {
    local v=$1
    case "${v,,}" in
        1 | y | yes | t | true | on) echo "true" ;;
        0 | n | no | f | false | off) echo "false" ;;
        *) echo "false" ;;
    esac
}
# KernelSU variant: NONE | KSU | NEXT | SUKI
KSU="${KSU:-NONE}"
# Include SuSFS?
SUSFS="$(_norm_bool "${SUSFS:-false}")"
# Apply LXC patch?
LXC="$(_norm_bool "${LXC:-false}")"

# --- Compiler
# Clang LTO mode: thin | full
CLANG_LTO="thin"
# Parallel build jobs
JOBS="$(nproc --all)"

# --- Paths
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_PATCHES="$WORKSPACE/kernel_patches"
CLANG="$WORKSPACE/clang"
OUT_DIR="$WORKSPACE/out"
LOGFILE="$WORKSPACE/build.log"

# --- Sources (host:owner/repo@ref)
KERNEL_REPO="github.com:ESK-Project/android_kernel_xiaomi_mt6895@16"
KERNEL_DEST="$WORKSPACE/kernel"
ANYKERNEL_REPO="github.com:ESK-Project/AnyKernel3@android12-5.10"
ANYKERNEL_DEST="$WORKSPACE/anykernel3"
KERNEL_OUT="$KERNEL_DEST/out"
CLANG_BIN="$CLANG/bin"

# --- Make arguments
MAKE_ARGS=(
    -j"$JOBS" O="$KERNEL_OUT" ARCH="arm64"
    CC="ccache clang" CROSS_COMPILE="aarch64-linux-gnu-"
    LLVM="1" LD="$CLANG_BIN/ld.lld"
)

trap 'error "Build failed at line $LINENO: $BASH_COMMAND"' ERR

### Utilities ######################################################################

# Run KernelSU setup.sh from a repo/ref
install_ksu() {
    local repo="$1"
    local ref="$2" # branch or tag
    local url
    url="https://raw.githubusercontent.com/$repo/$ref/kernel/setup.sh"
    info "Install KernelSU: $repo@$ref"
    curl -LSs "$url" | bash -s "$ref"
}

# Recreate a directory
reset_dir() {
    local path="$1"
    if [[ -d $path ]]; then
        rm -rf -- "$path"
    fi
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

### Prepare ########################################################################

# Stream stderr/stdout to both terminal and file
exec > >(tee "$LOGFILE") 2>&1

# Require tokens up-front
info "Validating environment variables..."
: "${GH_TOKEN:?Required GitHub PAT missing: GH_TOKEN}"
: "${TG_BOT_TOKEN:?Required Telegram Bot Token missing: TG_BOT_TOKEN}"
: "${TG_CHAT_ID:?Required chat ID missing: TG_CHAT_ID}"

# Validate KernelSU variant
KSU="${KSU^^}"
case "$KSU" in
    NONE | KSU | NEXT | SUKI) ;;
    *) error "Invalid KSU='$KSU' (expected: NONE|KSU|NEXT|SUKI)" ;;
esac
ksu_included=true
[[ $KSU == "NONE" ]] && ksu_included=false

# Set timezone
sudo timedatectl set-timezone "$TIMEZONE" || export TZ="$TIMEZONE"

# Notify Telegram
start_msg=$(
  cat << EOF
*$(escape_md_v2 "$KERNEL_NAME Kernel Build Started!")*

*Kernel*: $(escape_md_v2 "$KERNEL_NAME")
*Defconfig*: $(escape_md_v2 "$KERNEL_DEFCONFIG")
*Builder*: $(escape_md_v2 "$KBUILD_BUILD_USER@$KBUILD_BUILD_HOST")
*Compiler*: $(escape_md_v2 "$KBUILD_COMPILER_STRING")
*KSU*: $(escape_md_v2 "$KSU")
*SuSFS*: $(escape_md_v2 "$SUSFS" )
*LXC*: $(escape_md_v2 "$LXC")
*Jobs*: $(escape_md_v2 "$JOBS")
EOF
)

telegram_send_msg "$start_msg"

### Prepare environment ############################################################

RESET_DIR_LIST=("$KERNEL_DEST" "$ANYKERNEL_DEST" "$OUT_DIR")
info "Reset directories: ${RESET_DIR_LIST[*]}"
for dir in "${RESET_DIR_LIST[@]}"; do
    reset_dir "$dir"
done

info "Clone kernel source: $KERNEL_REPO -> $KERNEL_DEST"
git_clone "$KERNEL_REPO" "$KERNEL_DEST"

info "Clone AnyKernel3: $ANYKERNEL_REPO -> $ANYKERNEL_DEST"
git_clone "$ANYKERNEL_REPO" "$ANYKERNEL_DEST"

info "Fetch AOSP Clang toolchain"
clang_url=$(curl -s "https://api.github.com/repos/bachnxuan/aosp_clang_mirror/releases/latest" \
    | grep "browser_download_url" \
    | grep ".tar.gz" \
    | cut -d '"' -f 4)
mkdir -p "$CLANG"
aria2c -c -x16 -s16 -k4M --file-allocation=falloc \
    --console-log-level=error --summary-interval=0 --download-result=hide -q \
    -d "$WORKSPACE" -o "clang-archive" "$clang_url"
tar -xzf "$WORKSPACE/clang-archive" -C "$CLANG"
rm -rf "$WORKSPACE/clang-archive"

export PATH="${CLANG_BIN}:$PATH"

KBUILD_COMPILER_STRING=$("$CLANG_BIN/clang" -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')
KBUILD_BUILD_TIMESTAMP=$(date)
export KBUILD_COMPILER_STRING
export KBUILD_BUILD_TIMESTAMP
export KBUILD_BUILD_USER
export KBUILD_BUILD_HOST

cd "$KERNEL_DEST"
KERNEL_VERSION=$(make -s kernelversion)
DEFCONFIG_FILE=$(find ./arch/arm64/configs -name "$KERNEL_DEFCONFIG")

### Kernel helpers #################################################################

# Wrapper for scripts/config (prefer existing .config, use $DEFCONFIG_FILE if not found)
config() {
    local cfg="$KERNEL_OUT/.config"
    if [[ -f $cfg ]]; then
        "$KERNEL_DEST/scripts/config" --file "$cfg" "$@"
    else
        "$KERNEL_DEST/scripts/config" --file "$DEFCONFIG_FILE" "$@"
    fi
}

# Regenerate defconfig
regenerate_defconfig() {
    make "${MAKE_ARGS[@]}" olddefconfig
}

# Modify Clang LTO mode and regenerate config
clang_lto() {
    config --enable CONFIG_LTO_CLANG
    case "$1" in
        "thin")
            config --enable CONFIG_LTO_CLANG_THIN
            config --disable CONFIG_LTO_CLANG_FULL
            ;;
        "full")
            config --enable CONFIG_LTO_CLANG_FULL
            config --disable CONFIG_LTO_CLANG_THIN
            ;;
        *)
            warn "Unknown Clang LTO mode, falling back to Thin LTO"
            config --enable CONFIG_LTO_CLANG_THIN
            config --disable CONFIG_LTO_CLANG_FULL
            ;;
    esac
    regenerate_defconfig
}

# Convenient wrapper for patch
kernel_patch() {
  patch -p1 --forward --fuzz=3 --no-backup-if-mismatch
}

### Pre-build ######################################################################

# KernelSU setup
if [[ $ksu_included == true ]]; then
    info "Setup KernelSU"
    case "$KSU" in
        "NEXT") install_ksu KernelSU-Next/KernelSU-Next next ;;
        "SUKI") install_ksu SukiSU-Ultra/SukiSU-Ultra "$(if [[ $SUSFS == "true" ]]; then echo "susfs-main"; else echo "nongki"; fi)" ;;
    esac

    info "Apply KernelSU manual hook patch"
    if [[ $KSU == "SUKI" ]]; then
        kernel_patch < "$KERNEL_PATCHES/suki/manual_hooks.patch"
        config --disable CONFIG_KSU_SUSFS_SUS_SU
    elif [[ $KSU == "NEXT" ]]; then
        kernel_patch < "$KERNEL_PATCHES/next/manual_hooks.patch"
        config --disable CONFIG_KSU_SUSFS_SUS_SU
    fi

    config --enable CONFIG_KSU
    config --enable CONFIG_KSU_TRACEPOINT_HOOK
    config --enable CONFIG_KSU_MANUAL_HOOK
    config --disable CONFIG_KSU_KPROBES_HOOK
    config --enable CONFIG_KPM
    config --disable CONFIG_KSU_MANUAL_SU
    success "KernelSU configured"
fi

# SuSFS setup
if [[ $SUSFS == "true" ]]; then
    info "Apply SuSFS kernel-side patches"
    SUSFS_DIR="$WORKSPACE/susfs"
    SUSFS_PATCHES="$SUSFS_DIR/kernel_patches"
    SUSFS_BRANCH=gki-android12-5.10
    git_clone "gitlab.com:simonpunk/susfs4ksu@$SUSFS_BRANCH" "$SUSFS_DIR"
    cp -R "$SUSFS_PATCHES"/fs/* ./fs
    cp -R "$SUSFS_PATCHES"/include/* ./include
    patch -p1 < "$SUSFS_PATCHES"/50_add_susfs_in_gki-android*-*.patch
    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')

    if [[ $KSU == "NEXT" ]]; then
        info "Apply SuSFS patches to KernelSU (NEXT)"
        WILD_PATCHES="$WORKSPACE/wild_patches"
        SUSFS_FIX_PATCHES="$WILD_PATCHES/next/susfs_fix_patches/$SUSFS_VERSION"
        git_clone "github.com:WildKernels/kernel_patches@main" "$WILD_PATCHES"
        if [ ! -d "$SUSFS_FIX_PATCHES" ]; then
            error "SuSFS fix patches are unavailable for SuSFS $SUSFS_VERSION"
        fi
        cd KernelSU-Next
        kernel_patch < "$SUSFS_PATCHES/KernelSU/10_enable_susfs_for_ksu.patch" || true
        for patch in "$SUSFS_FIX_PATCHES"/*.patch; do
            kernel_patch < "$patch"
        done
        cd "$OLDPWD"
    fi
    config --enable CONFIG_KSU_SUSFS
    success "SuSFS applied"
else
    config --disable CONFIG_KSU_SUSFS
fi

# LXC support
if [[ $LXC == "true" ]]; then
    info "Apply LXC patch"
    pkernel_patch < "$KERNEL_PATCHES/lxc_support.patch"
    success "LXC patch applied"
fi

# Baseband Guard (BBG) LSM (for KernelSU variants)
if [[ $ksu_included == true ]]; then
    info "Setup Baseband Guard (BBG) LSM for KernelSU"
    wget -O- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash
    sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/bpf/bpf,baseband_guard/ } }' security/Kconfig
    config --enable CONFIG_BBG
fi

### Build ##########################################################################

info "Generate defconfig: $KERNEL_DEFCONFIG"
make "${MAKE_ARGS[@]}" "$KERNEL_DEFCONFIG"

info "Build kernel: Image"
clang_lto "$CLANG_LTO"
make "${MAKE_ARGS[@]}" Image
success "Kernel built successfully"

### Post-build #####################################################################

info "Packaging AnyKernel3 zip..."
cd "$ANYKERNEL_DEST"
cp -p "${KERNEL_OUT}/arch/arm64/boot/Image" "$ANYKERNEL_DEST"/

if [[ $KSU == "SUKI" ]]; then
    info "Patching KPM for SukiSU variant..."

    LATEST_SUKISU_PATCH=$(curl -s "https://api.github.com/repos/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/latest" | grep "browser_download_url" | grep "patch_linux" | cut -d '"' -f 4)
    curl -Ls "$LATEST_SUKISU_PATCH" -o patch_linux
    chmod a+x ./patch_linux
    
    sudo ./patch_linux
    mv oImage Image

    rm -rf ./patch_linux
    success "Patched KPM for SukiSU variant successfully!"
fi

info "Compressing kernel image..."
7z a -t7z -m0=lzma2 -mx=9 -md=64m -mfb=128 -mmt=on Image.7z ./Image
rm -rf ./Image
success "Compressed kernel image!"

VARIANT="$KSU"
[[ $SUSFS == "true" ]] && VARIANT+="-SUSFS"
[[ $LXC == "true" ]] && VARIANT+="-LXC"
PACKAGE_NAME="$KERNEL_NAME-$KERNEL_VERSION-$VARIANT-$(date '+%F')"
zip -r9 "$WORKSPACE/$PACKAGE_NAME.zip" ./*
cd "$OLDPWD"

info "Writing build metadata to github.env"
cat > "$WORKSPACE/github.env" << EOF
package_name=$PACKAGE_NAME
variant=$VARIANT
name=$KERNEL_NAME
out_dir=$WORKSPACE
EOF

result_caption=$(
  cat << EOF
*$(escape_md_v2 "$KERNEL_NAME Build Successfully!")*

*Builder*: $(escape_md_v2 "$KBUILD_BUILD_USER@$KBUILD_BUILD_HOST")
*Kernel*: $(escape_md_v2 "$KERNEL_NAME")

*Build info*
• Linux: $(escape_md_v2 "$KERNEL_VERSION")
• Date: $(escape_md_v2 "$KBUILD_BUILD_TIMESTAMP")
• KernelSU: $(escape_md_v2 "$KSU")
• SuSFS: $( [[ "$SUSFS" == "true" ]] && escape_md_v2 "$SUSFS_VERSION" || echo "None" )
• Compiler: $(escape_md_v2 "$KBUILD_COMPILER_STRING")

*Artifact*
• Name: $(escape_md_v2 "$PACKAGE_NAME.zip")
• Size: $(escape_md_v2 "$(du -h "$WORKSPACE/$PACKAGE_NAME.zip" | cut -f1)")
• SHA256: $(escape_md_v2 "$(sha256sum "$WORKSPACE/$PACKAGE_NAME.zip" | awk '{print $1}')")
EOF
)

telegram_upload_file "$WORKSPACE/$PACKAGE_NAME.zip" "$result_caption"

success "Build succeeded"
