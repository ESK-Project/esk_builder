# esk builder

builds esk kernel packages for xaga and generic.

pulls sources and tools, applies optional patches, then builds and packages the kernel.

## quick start

install the system packages, set up the python helper env, then run a build:

```bash
uv python install 3.14
uv sync --project py --locked
just build
```

for a target-specific build:

```bash
just xaga
just generic
```

## structure

- build.sh: main entry point
- config.sh: defaults, repos, paths, and target settings
- build/: setup, source fetching, patching, and kernel compile steps
- ci/: packaging, metadata, modules, and telegram helpers
- py/: uv-managed python helper cli
- modules/: `modules.load` files for xaga module packaging
- kernel_patches/: optional kernel patches
- .github/workflows/: ci and release workflows

## build flow

```text
just build / just xaga / just generic
        |
        v
build.sh
        |
        v
config.sh loads defaults, target settings, paths, and repos
        |
        v
build/ prepares tools, sources, patches, and kernel build
        |
        v
ci/ packages images, modules, metadata, and release files
        |
        v
out/ contains flashable zips and boot images
```

`build.log` and `github.json` are written at the repo root.

## requirements

ubuntu/debian:

```bash
sudo apt install aria2 bc bison build-essential ccache curl flex git jq libfaketime lz4 python3 shellcheck shfmt tar upx uv wget zip zstd just
```

fedora:

```bash
sudo dnf install aria2 bc bison ccache curl flex git jq libfaketime lz4 make python3 ShellCheck shfmt tar upx uv wget zip zstd just
```

## uv setup

the python helpers live in `py/` and use python 3.14.

for local checks and development:

```bash
uv python install 3.14
uv sync --project py --locked
```

for runtime or release use without dev tools:

```bash
uv python install 3.14
uv sync --project py --locked --no-dev
```

`uv sync --project py --locked` installs the helper env with dev dependencies like ruff and basedpyright.

`uv sync --project py --locked --no-dev` keeps only the runtime dependencies used by the build and release helpers.

## build

list available commands:

```bash
just --list
```

build with the default target:

```bash
just build
```

build xaga:

```bash
just xaga
```

build generic:

```bash
just generic
```

example:

```bash
just xaga KSU=true SUSFS=true LXC=false
```

## checks

format shell scripts:

```bash
just fmt
```

run all checks:

```bash
just check
```

run the python type check:

```bash
just py-check
```

clean generated outputs:

```bash
just clean
```

## inputs

| env var         | purpose                                      | accepted values                  | default                           |
| --------------- | -------------------------------------------- | -------------------------------- | --------------------------------- |
| BUILD_TARGET    | select the build target                      | `xaga`, `generic`                | `xaga`                            |
| KSU             | enable KernelSU setup and config             | boolean                          | `false`                           |
| SUSFS           | apply SuSFS patches and config               | boolean                          | `false`                           |
| LXC             | apply the LXC patch                          | boolean                          | `false`                           |
| STOCK_CONFIG    | apply the stock config patch                 | `auto`, `true`, `false`          | `xaga: false`, `generic: true`    |
| BRANCH_OVERRIDE | override the target kernel branch            | branch name                      | `xaga: 16.2-rebase`, `generic: main` |
| JOBS            | set the make job count                       | integer                          | `nproc --all`                     |
| RESET_SOURCES   | reset and re-clone source/tool dirs before build | boolean                      | `false` locally, `true` in ci     |
| TG_NOTIFY       | send telegram updates                        | boolean                          | `false` locally, `true` in ci     |
| IS_RELEASE      | flag the build as a release build            | boolean                          | `false`                           |
| GH_TOKEN        | github token for release asset fetching      | token string                     | unset                             |
| TG_BOT_TOKEN    | telegram bot token                           | token string                     | unset                             |
| TG_CHAT_ID      | telegram chat id                             | chat id                          | unset                             |

notes:

- boolean values accept `true/false`, `t/f`, `yes/no`, `y/n`, `on/off`, and `1/0`
- only `STOCK_CONFIG` accepts `auto`; other boolean-like inputs fail clearly
- `STOCK_CONFIG=auto` resolves to `false` for xaga and `true` for generic
- `SUSFS` needs `KSU=true`
- `LXC` only works with `BUILD_TARGET=xaga`
- `TG_NOTIFY=true` needs `TG_BOT_TOKEN` and `TG_CHAT_ID`
- `GH_TOKEN` is optional, but helps when fetching latest release assets
- generic telegram success notifications upload one grouped message containing the AnyKernel3 zip plus a boot-image zip

## output

| file                          | description                             |
| ----------------------------- | --------------------------------------- |
| work/                         | kernel build output directory           |
| out/\<package>-AnyKernel3.zip | flashable AnyKernel3 package            |
| out/\<package>-boot-raw.img   | generic raw boot image                  |
| out/\<package>-boot-gz.img    | generic gzip boot image                 |
| out/\<package>-boot-lz4.img   | generic lz4 boot image                  |
| github.json                   | release metadata written by the python helper, including the kernel commit |
| build.log                     | build log                               |

where `<package>` has the format `${KERNEL_NAME}-${KERNEL_VERSION}-${VARIANT}` (with `-${KERNEL_COMMIT}` appended when `IS_RELEASE` is not `true`).
