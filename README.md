# esk builder

esk builder builds Linux kernel packages for two targets:

- `device` builds the phone kernel configured by the current builder branch.
- `generic` builds the generic Android Generic Kernel Image (GKI) target.

The build downloads the selected kernel source and required tools, applies the enabled patches, compiles the kernel, and writes packages to `out/`.

AnyKernel3 is the flashable zip layout used to package the compiled kernel for both targets.

## choose a target

| target | use it for | configuration | main output |
| ------ | ---------- | ------------- | ----------- |
| `device` | The device supported by the current builder branch | The branch-specific device block in `config.sh` | An AnyKernel3 zip with the device modules |
| `generic` | The separate generic GKI build | The `generic` case in `config.sh` | An AnyKernel3 zip and raw, gzip, and LZ4 boot images |

`device` is the build target name. The native device codename is the value of `DEVICE_NAME` in `config.sh`; it identifies the configured device but is not a valid build target. Use `device` or `generic` in commands, never the codename.

The checked-out builder branch controls the device identity, kernel and AnyKernel3 repositories, source branch, defconfig (kernel build configuration) overlay, release repository, and supported device features. Check the first block of `config.sh` before a device build instead of relying on values copied from another branch.

`just build` uses the default target, which is `device`. Use `just generic` only when you want the separate generic GKI build.

## requirements

This is a Linux-only Bash and Python project. Clone or check out the builder branch for the device you want, then run every command below from the repository root.

The first build needs network access. It downloads the kernel source, AnyKernel3, Android build tools, `mkbootimg`, an AOSP Clang toolchain, and `libfakestat`. A generic build also downloads a certified GKI archive for its boot image template.

Ubuntu 24.04 or newer and Debian 13 or newer:

```bash
sudo apt update
sudo apt install \
  aria2 bc bison bsdextrautils build-essential ccache curl flex git gzip just \
  kmod libfaketime llvm lz4 patch python3 shellcheck shfmt tar unzip xz-utils \
  zip zstd
```

Fedora:

```bash
sudo dnf install \
  aria2 bc bison ccache curl flex gcc git gzip just kmod libfaketime llvm lz4 \
  make patch python3 ShellCheck shfmt tar unzip util-linux xz zip zstd
```

Install [`uv`](https://docs.astral.sh/uv/getting-started/installation/) if it is not already available:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Restart the shell if the installer asks you to update `PATH`, then verify the two project commands:

```bash
just --version
uv --version
```

## quick start

Set up the Python 3.14 helper environment and run the default device build:

```bash
uv python install 3.14
uv sync --project py --locked --no-dev
just build
```

The first two commands create `py/.venv` with the runtime dependencies used by the Bash build. `just build` then runs `build.sh` with the branch-configured `device` target. Build packages appear in `out/`; `build.log` and `github.json` appear at the repository root.

To build the generic target instead:

```bash
just generic
```

> [!WARNING]
> Treat `kernel/`, `anykernel3/`, `build-tools/`, `mkbootimg/`, and `susfs/` as build-managed checkouts. A build cleans and resets existing source repositories, and it recreates `anykernel3/`, `out/`, and `boot_image/`. Do not keep source changes or untracked files in those directories. `RESET_SOURCES=true` deletes and reclones the managed source directories before continuing.

## build commands

List the available commands:

```bash
just --list
```

Build the current `BUILD_TARGET`, which defaults to `device`:

```bash
just build
```

Build the branch-configured device explicitly:

```bash
just device
```

Build generic GKI:

```bash
just generic
```

Pass build settings after the recipe name:

```bash
just device KSU=true SUSFS=true LXC=false
```

The recipes pass these values to `build.sh` as environment variables.

## configuration

The default settings live in `config.sh`. Override the supported settings for one command as shown above, or export them before running `just build`.

| variable | purpose | accepted values | default |
| -------- | ------- | --------------- | ------- |
| `BUILD_TARGET` | Select the build target | `device`, `generic` | `device` |
| `KSU` | Add KernelSU | Boolean | `false` |
| `SUSFS` | Add SuSFS to a KernelSU build | Boolean | `false` |
| `LXC` | Apply the Linux Containers (LXC) patch | Boolean | `false` |
| `STOCK_CONFIG` | Apply the stock configuration patch | `auto`, `true`, `false` | `auto`: device resolves to `false`, generic resolves to `true` |
| `BRANCH_OVERRIDE` | Override the selected target's kernel source branch | Branch name | Device value from `config.sh`; generic uses `main` |
| `JOBS` | Set parallel `make` jobs | Integer | `nproc --all` |
| `CCACHE_SIZE` | Set the compiler cache size | A `ccache` size such as `2G` | `2G` |
| `RESET_SOURCES` | Delete and reclone managed source directories before the build | Boolean | `false` locally, `true` in GitHub Actions |
| `TG_NOTIFY` | Send Telegram build messages and packages | Boolean | `false` locally; `true` when unset in GitHub Actions |
| `IS_RELEASE` | Use release package naming without the kernel commit suffix | Boolean | `false` |
| `GH_TOKEN` | Authenticate GitHub API requests for release assets | Token string | Unset |
| `TG_BOT_TOKEN` | Authenticate the Telegram bot | Token string | Unset |
| `TG_CHAT_ID` | Select the Telegram destination | Chat ID | Unset |

Boolean values accept `true/false`, `t/f`, `yes/no`, `y/n`, `on/off`, and `1/0`. Only `STOCK_CONFIG` accepts `auto`. Invalid values stop the build with an error.

Feature rules:

- `KSU=true` runs the KernelSU setup script from `ESK-Project/ReSukiSU@main`.
- `SUSFS=true` requires `KSU=true` and applies the configured SuSFS patches.
- `LXC=true` is valid only for `device`, and only when that branch sets `DEVICE_LXC_SUPPORTED=true` in `config.sh`.
- `STOCK_CONFIG=auto` follows the target defaults shown in the table.
- `BRANCH_OVERRIDE` changes only the selected kernel source branch. It does not switch the builder branch or change `DEVICE_NAME`.
- `TG_NOTIFY=true` requires both `TG_BOT_TOKEN` and `TG_CHAT_ID`.
- The release workflow passes `TG_NOTIFY=false`; other GitHub Actions builds use their workflow input.
- `GH_TOKEN` is optional for local builds. Without it, GitHub API requests can be rate-limited. GitHub Actions requires the token when the needed release assets are not already cached.

Common configuration errors are reported before compilation. If a build rejects a codename as an unknown target, use `device`. If it rejects SuSFS, enable KernelSU too. If it rejects LXC, select a branch whose device configuration supports LXC or disable it.

## output

- generic telegram success notifications upload one grouped message containing the AnyKernel3 zip plus a boot-image zip

Each build clears `out/` before packaging. `<package>` has the form `${KERNEL_NAME}-${KERNEL_VERSION}-${VARIANT}`. Local builds append `-${KERNEL_COMMIT}`; release builds do not.

`VNL` means KernelSU is disabled. `KSU` means it is enabled. Enabled SuSFS and LXC features add `-SUSFS` and `-LXC` to the variant.

| path | target | description |
| ---- | ------ | ----------- |
| `out/<package>-AnyKernel3.zip` | Both | Flashable AnyKernel3 package containing the compiled kernel |
| `out/module.tar.xz` | Device | Staged `vendor_boot` and `vendor_dlkm` modules, also copied into the AnyKernel3 package |
| `out/<package>-boot-raw.img` | Generic | Boot image containing the raw kernel image |
| `out/<package>-boot-gz.img` | Generic | Boot image containing the gzip-compressed kernel image |
| `out/<package>-boot-lz4.img` | Generic | Boot image containing the LZ4-compressed kernel image |
| `github.json` | Both | Release metadata, including the kernel commit, toolchain, package name, output directory, and release repository |
| `build.log` | Both | Build log |
| `work/` | Both | Kernel compilation output used to create the packages |

## checks and cleanup

For local development, install the Python development dependencies instead of the runtime-only environment:

```bash
uv sync --project py --locked
```

Check formatting without changing files:

```bash
just fmt-check
```

Run all shell formatting, shell syntax, ShellCheck, Ruff, and Python type checks:

```bash
just check
```

`just --list` also shows the individual `bash-check`, `lint`, `py-lint`, and `py-check` recipes.

Format tracked shell scripts in place:

```bash
just fmt
```

Remove `out/`, `work/`, `staged/`, `boot_image/`, `build.log`, and `github.json`. This does not remove downloaded source or tool directories:

```bash
just clean
```

## structure

- `build.sh`: top-level build flow and validation
- `config.sh`: branch-owned device settings, generic target settings, defaults, repositories, and paths
- `build/`: source setup, patching, toolchain setup, and kernel compilation
- `ci/`: module handling, packaging, metadata, and Telegram notifications
- `py/`: uv-managed Python 3.14 helper CLI for API and JSON work
- `modules/`: branch-owned `modules.load` files used by device packaging
- `kernel_patches/`: optional stock configuration and LXC patches
- `.github/matrix/`: release feature combinations for each target
- `.github/workflows/`: checks, manual builds, and release workflows
