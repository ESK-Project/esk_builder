# shellcheck shell=bash
# shellcheck disable=SC2034

#
# ESK Kernel builder configuration
#

################################################################################
# Project Identity
################################################################################
KERNEL_NAME="ESK"
KERNEL_DEFCONFIG="gki_defconfig"

# Kbuild identity
KBUILD_BUILD_USER="builder"
KBUILD_BUILD_HOST="esk"

# Used for timestamps in logs
TIMEZONE="Asia/Ho_Chi_Minh"

# Where release artifacts are published
RELEASE_BRANCH="main"

################################################################################
# Build target
################################################################################
BUILD_TARGET="${BUILD_TARGET:-xaga}"

################################################################################
# Build options
################################################################################
# Clang LTO mode: thin | full
CLANG_LTO="thin"

# Parallel build jobs (override: JOBS=16 ./build.sh)
JOBS="${JOBS:-$(nproc --all)}"

################################################################################
# Source
################################################################################
# Format: <host>:<owner/repo>@<ref>
ANYKERNEL_REPO="github.com:ESK-Project/AnyKernel3@android12-5.10"
BUILD_TOOLS_REPO="android.googlesource.com:kernel/prebuilts/build-tools@main-kernel-build-2024"
MKBOOTIMG_REPO="android.googlesource.com:platform/system/tools/mkbootimg@main-kernel-build-2024"
SUSFS_REPO="gitlab.com:simonpunk/susfs4ksu@gki-android12-5.10"

# Other sources
GKI_URL="https://dl.google.com/android/gki/gki-certified-boot-android12-5.10-2025-09_r1.zip"
LIBFAKESTAT_URL="https://github.com/cctv18/libfakestat/releases/download/libfakestat-build-251027213612/libfakestat.tar.gz"

case "$BUILD_TARGET" in
    xaga)
        KERNEL_REPO="github.com:ESK-Project/android_kernel_xiaomi_mt6895@16.2"
        RELEASE_REPO="ESK-Project/esk-releases"
        BOOT_MODE="single"
        ;;
    generic)
        KERNEL_REPO="github.com:ESK-Project/android12-5.10-gki@main"
        RELEASE_REPO="ESK-Project/gki-releases"
        BOOT_MODE="multi"
        ;;
    *)
        echo "Unknown build target: $BUILD_TARGET" >&2
        exit 1
        ;;
esac

################################################################################
# Paths
################################################################################
# Work dirs
KERNEL="$WORKSPACE/kernel"
ANYKERNEL="$WORKSPACE/anykernel3"
BUILD_TOOLS="$WORKSPACE/build-tools"
MKBOOTIMG="$WORKSPACE/mkbootimg"
CLANG="$WORKSPACE/clang"
KERNEL_PATCHES="$WORKSPACE/kernel_patches"
SUSFS_DIR="$WORKSPACE/susfs"
LIBFAKESTAT_DIR="$WORKSPACE/libfakestat"

# Output stuff
OUT_DIR="$WORKSPACE/out"
BOOT_IMAGE="$WORKSPACE/boot_image"
LOGFILE="$WORKSPACE/build.log"
SIGN_KEY="$WORKSPACE/key"

# Helper paths
CLANG_BIN="$CLANG/bin"
BOOT_SIGN_KEY="$SIGN_KEY/boot_sign_key.pem"
KERNEL_OUT="$KERNEL/out"
LIBFAKESTAT="$LIBFAKESTAT_DIR/libfakestat.so"
