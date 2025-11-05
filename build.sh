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

# Bool parsing utils
norm_bool() {
    local value=$1;
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
        echo "Disabled";
    fi
}

# Telegram Notify toggle
TG_NOTIFY="$(norm_bool "${TG_NOTIFY:-true}")"

# Logging functions
info() { echo -e "${BLUE}[$(date '+%F %T')] [INFO]${NC} $*"; }
success() { echo -e "${GREEN}[$(date '+%F %T')] [SUCCESS]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%F %T')] [WARN]${NC} $*"; }

# Send a text message via Telegram Bot API
telegram_send_msg() {
    local resp err

    if [[ $TG_NOTIFY == false ]]; then
        return 0
    fi

    resp=$(curl -sX POST https://api.telegram.org/bot"${TG_BOT_TOKEN}"/sendMessage \
        -d chat_id="${TG_CHAT_ID}" \
        -d parse_mode="MarkdownV2" \
        -d disable_web_page_preview=true \
        -d text="$1")

    if ! echo "$resp" | jq -e '.ok == true' > /dev/null; then
        err=$(echo "$resp" | jq -r '.description')
        echo -e "${RED}[$(date '+%F %T')] [ERROR] telegram_send_msg(): failed to send message: ${err:-Unknown error} $*" >&2
    fi
}

# Upload a document with caption via Telegram Bot API
telegram_upload_file() {
    local resp err

    if [[ $TG_NOTIFY == false ]]; then
        return 0
    fi

    resp=$(curl -sX POST -F document=@"$1" https://api.telegram.org/bot"${TG_BOT_TOKEN}"/sendDocument \
        -F "chat_id=${TG_CHAT_ID}" \
        -F "parse_mode=MarkdownV2" \
        -F "caption=$2")

    if ! echo "$resp" | jq -e '.ok == true' > /dev/null; then
        err=$(echo "$resp" | jq -r '.description')
        echo -e "${RED}[$(date '+%F %T')] [ERROR] telegram_upload_file(): failed to upload file: ${err:-Unknown error}" >&2
    fi
}

# Unified error handler
error() {
    trap - ERR # Disable the ERR trap to prevent recursion
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
RELEASE_REPO="ESK-Project/esk-releases"
RELEASE_BRANCH="main"

# --- Kernel flavour
# KernelSU variant: NONE | OFFICIAL | NEXT | SUKI
KSU="${KSU:-NONE}"
# Include SuSFS?
SUSFS="$(norm_bool "${SUSFS:-false}")"
# Apply LXC patch?
LXC="$(norm_bool "${LXC:-false}")"
# Include BBG?
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

# Run KernelSU setup.sh from repo/ref
install_ksu() {
    local repo="$1"
    local ref="$2" # branch or tag
    local url
    url="https://raw.githubusercontent.com/$repo/$ref/kernel/setup.sh"
    info "Install KernelSU: $repo@$ref"
    curl -fsSL "$url" | bash -s "$ref"
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

info "Validating environment variables..."
: "${GH_TOKEN:?Required GitHub PAT missing: GH_TOKEN}"
if [[ "$TG_NOTIFY" == true ]]; then
    : "${TG_BOT_TOKEN:?Required Telegram Bot Token missing: TG_BOT_TOKEN}"
    : "${TG_CHAT_ID:?Required chat ID missing: TG_CHAT_ID}"
fi

# Validate KernelSU variant
KSU="${KSU^^}"
case "$KSU" in
    NONE | OFFICIAL | NEXT | SUKI | KOW) ;;
    *) error "Invalid KSU='$KSU' (expected: NONE|OFFICIAL|NEXT|SUKI|KOW)" ;;
esac
ksu_included="true"
[[ $KSU == "NONE" ]] && ksu_included="false"

# Set timezone
sudo timedatectl set-timezone "$TIMEZONE" || export TZ="$TIMEZONE"

# Notify Telegram
start_msg=$(
    cat << EOF
*$(escape_md_v2 "$KERNEL_NAME Kernel Build Started!")*

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

info "Fetching AOSP Clang toolchain"
clang_url=$(curl -fsSL "https://api.github.com/repos/bachnxuan/aosp_clang_mirror/releases/latest" \
    -H "Authorization: Bearer $GH_TOKEN" \
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

COMPILER_STRING=$("$CLANG_BIN/clang" -v 2>&1 | head -n 1 | sed 's/(https..*//')
export KBUILD_BUILD_TIMESTAMP
export KBUILD_BUILD_USER
export KBUILD_BUILD_HOST

cd "$KERNEL_DEST"
KERNEL_VERSION=$(make -s kernelversion | cut -d- -f1)

DEFCONFIG_DIR="$KERNEL_DEST/arch/arm64/configs"
DEFCONFIG_FILE="$DEFCONFIG_DIR/$KERNEL_DEFCONFIG"
if [ ! -f "$DEFCONFIG_FILE" ]; then
    DEFCONFIG_FILE="$(find "$DEFCONFIG_DIR" -type f -name "$KERNEL_DEFCONFIG" -print -quit)"
    [ -n "$DEFCONFIG_FILE" ] || error "Defconfig not found: $KERNEL_DEFCONFIG"
fi

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
    make "${MAKE_ARGS[@]}" -s olddefconfig
}

# Modify Clang LTO mode
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

### Pre-build ######################################################################

# KernelSU setup
if [[ $ksu_included == "true" ]]; then
    info "Setup KernelSU"
    case "$KSU" in
        "OFFICIAL") install_ksu tiann/KernelSU main ;;
        "NEXT") install_ksu KernelSU-Next/KernelSU-Next next ;;
        "SUKI") install_ksu SukiSU-Ultra/SukiSU-Ultra "$(if [[ $SUSFS == "true" ]]; then echo "susfs-main"; else echo "main"; fi)" ;;
        "KOW") install_ksu KOWX712/KernelSU staging ;;
    esac

    info "Apply KernelSU manual hook patch"
    if [[ $KSU == "SUKI" ]]; then
        patch -s -p1 --fuzz=3 --no-backup-if-mismatch < "$KERNEL_PATCHES/suki/manual_hooks.patch"
        config --disable CONFIG_KSU_SUSFS_SUS_SU
    elif [[ $KSU == "NEXT" ]]; then
        patch -s -p1 --fuzz=3 --no-backup-if-mismatch < "$KERNEL_PATCHES/next/manual_hooks.patch"
        config --disable CONFIG_KSU_SUSFS_SUS_SU
    fi

    config --enable CONFIG_KSU
    config --enable CONFIG_KSU_TRACEPOINT_HOOK
    config --enable CONFIG_KSU_MANUAL_HOOK
    config --disable CONFIG_KSU_KPROBES_HOOK
    config --enable CONFIG_KPM
    config --enable CONFIG_KSU_MANUAL_SU
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
    patch -s -p1 --no-backup-if-mismatch < "$SUSFS_PATCHES"/50_add_susfs_in_gki-android*-*.patch
    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')

    if [[ $KSU == "NEXT" || $KSU == "OFFICIAL" ]]; then
        case "$KSU" in
            "NEXT") cd KernelSU-Next ;;
            "OFFICIAL") cd KernelSU ;;
        esac
        info "Apply KernelSU-side SuSFS patches ($KSU)"
        patch -s -p1 --no-backup-if-mismatch < "$SUSFS_PATCHES/KernelSU/10_enable_susfs_for_ksu.patch" || true
    fi

    if [[ $KSU == "NEXT" ]]; then
        info "Apply SuSFS fix patches for KernelSU Next"
        WILD_PATCHES="$WORKSPACE/wild_patches"
        SUSFS_FIX_PATCHES="$WILD_PATCHES/next/susfs_fix_patches/$SUSFS_VERSION"
        git_clone "github.com:WildKernels/kernel_patches@main" "$WILD_PATCHES"
        if [ ! -d "$SUSFS_FIX_PATCHES" ]; then
            error "SuSFS fix patches are unavailable for SuSFS $SUSFS_VERSION"
        fi
        for patch in "$SUSFS_FIX_PATCHES"/*.patch; do
            patch -s -p1 --no-backup-if-mismatch < "$patch"
        done
    fi

    cd "$KERNEL_DEST"
    config --enable CONFIG_KSU_SUSFS
    success "SuSFS applied!"
else
    config --disable CONFIG_KSU_SUSFS
fi

# LXC support
if [[ $LXC == "true" ]]; then
    info "Apply LXC patch"
    patch -s -p1 --fuzz=3 --no-backup-if-mismatch < "$KERNEL_PATCHES/lxc_support.patch"
    success "LXC patch applied"
fi

# Baseband Guard (BBG) LSM
if [ "$BBG" == "true" ]; then
    info "Setup Baseband Guard (BBG) LSM for KernelSU variants"
    wget -qO- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash > /dev/null 2>&1
    sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/bpf/bpf,baseband_guard/ } }' security/Kconfig
    config --enable CONFIG_BBG
    success "Added BBG"
fi

### Build ##########################################################################

# Bash built-in time counter, starts from this line
SECONDS=0

info "Generate defconfig: $KERNEL_DEFCONFIG"
make "${MAKE_ARGS[@]}" "$KERNEL_DEFCONFIG" > /dev/null 2>&1
success "Defconfig generated"

clang_lto "$CLANG_LTO"
make "${MAKE_ARGS[@]}" Image
success "Kernel built successfully"

### Post-build #####################################################################

info "Packaging AnyKernel3 zip..."
cd "$ANYKERNEL_DEST"

if [[ $KSU == "SUKI" ]]; then
    info "Patching KPM for SukiSU variant..."

    tmpdir="$(mktemp -d)"
    cd "$tmpdir"
    cp -p "$KERNEL_OUT/arch/arm64/boot/Image" "$tmpdir"/

    LATEST_SUKISU_PATCH=$(curl -fsSL "https://api.github.com/repos/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/latest" \
        -H "Authorization: Bearer $GH_TOKEN" \
        | grep "browser_download_url" | grep "patch_linux" | cut -d '"' -f 4)

    [[ -n $LATEST_SUKISU_PATCH ]] || error "Could not find patch_linux in the latest release"

    curl -fsSL "$LATEST_SUKISU_PATCH" -o patch_linux
    chmod +x ./patch_linux

    ./patch_linux > /dev/null 2>&1
    [[ -f oImage ]] || error "patch_linux failed to produce patched Image"
    mv oImage "$ANYKERNEL_DEST/Image"

    rm -rf ./patch_linux
    cd "$ANYKERNEL_DEST"
    rm -rf "$tmpdir"

    success "Patched KPM for SukiSU variant"
else
    cp -p "$KERNEL_OUT/arch/arm64/boot/Image" "$ANYKERNEL_DEST"/
fi

info "Compressing kernel image..."
zstd -19 -T0 --no-progress -o Image.zst Image > /dev/null 2>&1
rm -rf ./Image

# Generate sha256 hash for Image.zst
sha256sum Image.zst > Image.zst.sha256

info "Compressing static binaries with upx..."
UPX_LIST=(
    tools/zstd
    tools/fec
    tools/httools_static
    tools/lptools_static
    tools/magiskboot
    tools/magiskpolicy
    tools/snapshotupdater_static
)

for binary in "${UPX_LIST[@]}"; do
    file="$ANYKERNEL_DEST/$binary"

    [[ -f $file ]] || continue

    if upx -9 --lzma --no-progress "$file" > /dev/null 2>&1; then
        success "[UPX] Compressed: $(basename "$binary")"
    else
        warn "[UPX] Failed: $(basename "$binary")"
    fi
done

VARIANT="$KSU"
[[ $SUSFS == "true" ]] && VARIANT+="-SUSFS"
[[ $LXC == "true" ]] && VARIANT+="-LXC"
PACKAGE_NAME="$KERNEL_NAME-$KERNEL_VERSION-$VARIANT"
zip -r9q -T -X -y -n .zst "$OUT_DIR/$PACKAGE_NAME.zip" . -x '.git/*' '*.log'
cd "$WORKSPACE"

info "Writing build metadata to github.env"
cat > "$WORKSPACE/github.env" << EOF
kernel_version=$KERNEL_VERSION
kernel_name=$KERNEL_NAME
toolchain=$COMPILER_STRING
build_date=$KBUILD_BUILD_TIMESTAMP
package_name=$PACKAGE_NAME
susfs_version=$SUSFS_VERSION
variant=$VARIANT
name=$KERNEL_NAME
out_dir=$OUT_DIR
release_repo=$RELEASE_REPO
release_branch=$RELEASE_BRANCH
EOF

build_time="$SECONDS"
minutes=$((build_time / 60))
seconds=$((build_time % 60))

result_caption=$(
    cat << EOF
*$(escape_md_v2 "$KERNEL_NAME Build Successfully!")*

*Build*
├ Builder: $(escape_md_v2 "$KBUILD_BUILD_USER@$KBUILD_BUILD_HOST")
├ Build time: $(escape_md_v2 "${minutes}m ${seconds}s")
└ Build date: $(escape_md_v2 "$KBUILD_BUILD_TIMESTAMP")

*Kernel*
├ Linux version: $(escape_md_v2 "$KERNEL_VERSION")
└ Compiler: $(escape_md_v2 "$COMPILER_STRING")

*Options*
├ KernelSU: $(escape_md_v2 "$KSU")
├ SuSFS: $([[ $SUSFS == "true" ]] && escape_md_v2 "$SUSFS_VERSION" || echo "None")
└ LXC: $(escape_md_v2 "$(parse_bool "$LXC")")

*Artifact*
├ Name: $(escape_md_v2 "$PACKAGE_NAME.zip")
└ Size: $(escape_md_v2 "$(du -h "$WORKSPACE/$PACKAGE_NAME.zip" | cut -f1)")
EOF
)

telegram_upload_file "$OUT_DIR/$PACKAGE_NAME.zip" "$result_caption"

success "Build succeeded in ${minutes}m ${seconds}s"
