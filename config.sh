# shellcheck shell=bash
# shellcheck disable=SC2034

#
# ESK Raspberry Pi 4B kernel builder configuration
#

################################################################################
# Project Identity
################################################################################
KERNEL_NAME="ESK-RPi"
KERNEL_DEFCONFIG="${KERNEL_DEFCONFIG:-bcm2711_defconfig}"

# Kbuild identity
KBUILD_BUILD_USER="builder"
KBUILD_BUILD_HOST="esk"

# Used for timestamps in logs
TIMEZONE="Asia/Ho_Chi_Minh"

# Where release artifacts are published
RELEASE_BRANCH="main"
ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

################################################################################
# Build options
################################################################################
# Clang LTO mode: thin | full
CLANG_LTO="thin"

# Parallel build jobs (override: JOBS=16 ./build.sh)
JOBS="${JOBS:-$(nproc --all)}"

# ccache size
CCACHE_SIZE="${CCACHE_SIZE:-2G}"

################################################################################
# Source
################################################################################
# Format: <host>:<owner/repo>@<ref>
KERNEL_REPO="github.com:ESK-Project/rpi-linux@${BRANCH_OVERRIDE:-rpi-6.12.y}"
RELEASE_REPO="ESK-Project/esk-rpi-releases"
LIBFAKESTAT_URL="https://github.com/cctv18/libfakestat/releases/download/libfakestat-build-260416190945/libfakestat.tar.gz"

################################################################################
# Paths
################################################################################
# Work dirs
KERNEL="$WORKSPACE/kernel"
CLANG="$WORKSPACE/clang"
LIBFAKESTAT_DIR="$WORKSPACE/libfakestat"
CLANG_BIN="$CLANG/bin"

# Output stuff
KERNEL_OUT="$WORKSPACE/work"
OUT_DIR="$WORKSPACE/out"
LOGFILE="$WORKSPACE/build.log"

# Helper paths
LIBFAKESTAT="$LIBFAKESTAT_DIR/libfakestat.so"
