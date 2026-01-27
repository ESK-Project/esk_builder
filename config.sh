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

# Used for timestamps in logs/messages
TIMEZONE="Asia/Ho_Chi_Minh"

# Where release artifacts are published
RELEASE_REPO="ESK-Project/esk-releases"
RELEASE_BRANCH="main"

################################################################################
# Build knobs
################################################################################
# Clang LTO mode: thin | full
CLANG_LTO="thin"

# Parallel build jobs (override: JOBS=16 ./build.sh)
JOBS="${JOBS:-$(nproc --all)}"
