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
RELEASE_REPO="ESK-Project/esk-releases"
RELEASE_BRANCH="main"

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
KERNEL_REPO="github.com:ESK-Project/android_kernel_xiaomi_mt6895@16"
ANYKERNEL_REPO="github.com:ESK-Project/AnyKernel3@android12-5.10"
BUILD_TOOLS_REPO="android.googlesource.com:kernel/prebuilts/build-tools@main-kernel-build-2024"
MKBOOTIMG_REPO="android.googlesource.com:platform/system/tools/mkbootimg@main-kernel-build-2024"
SUSFS_REPO="gitlab.com:simonpunk/susfs4ksu@gki-android12-5.10"

# Other sources
GKI_URL="https://dl.google.com/android/gki/gki-certified-boot-android12-5.10-2025-09_r1.zip"

################################################################################
# Paths
################################################################################
KERNEL="$WORKSPACE/kernel"
ANYKERNEL="$WORKSPACE/anykernel3"
BUILD_TOOLS="$WORKSPACE/build-tools"
MKBOOTIMG="$WORKSPACE/mkbootimg"
CLANG="$WORKSPACE/clang"
CLANG_BIN="$CLANG/bin"
OUT_DIR="$WORKSPACE/out"
BOOT_IMAGE="$WORKSPACE/boot_image"
SIGN_KEY="$WORKSPACE/key"
BOOT_SIGN_KEY="$SIGN_KEY/boot_sign_key.pem"
KERNEL_PATCHES="$WORKSPACE/kernel_patches"
KERNEL_OUT="$KERNEL/out"
SUSFS_DIR="$WORKSPACE/susfs"
GITHUB_ENV_FILE="$WORKSPACE/github.env"
LOGFILE="$WORKSPACE/build.log"
