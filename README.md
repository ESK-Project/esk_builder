# esk_builder

builds esk kernel packages for xaga and generic.

pulls sources and tools, applies optional patches, then builds and packages the kernel.

## structure

- build.sh: main entry point
- config.sh: defaults, repos, paths, and target settings
- build/: setup, patching, and compile kernel
- ci/: packaging, metadata, modules, and telegram helpers
- py/: small python helpers
- modules/: module lists used during packaging
- kernel_patches/: local patch files
- .github/workflows/: ci and release workflows

## requirements

ubuntu/debian:

```bash
sudo apt install bc bison ccache curl flex git tar wget aria2 jq zip zstd upx build-essential python3-requests libfaketime lz4
````

fedora:

```bash
sudo dnf install bc bison ccache curl flex git tar wget aria2 jq zip zstd upx make gcc gcc-c++ python3-requests libfaketime lz4
```

## run

```bash
./build.sh
```

example:

```bash
BUILD_TARGET=xaga KSU=true SUSFS=true LXC=false ./build.sh
```

## inputs

| env var         | description                                    |
| --------------- | ---------------------------------------------- |
| BUILD_TARGET    | build target, either xaga or generic           |
| KSU             | enable kernelsu                                |
| SUSFS           | enable susfs                                   |
| LXC             | apply the lxc patch, xaga only                 |
| STOCK_CONFIG    | apply the stock config patch                   |
| BRANCH_OVERRIDE | use a different kernel branch                  |
| JOBS            | set make job count                             |
| RESET_SOURCES   | re-clone sources and tools before building     |
| TG_NOTIFY       | send telegram updates                          |
| GH_TOKEN        | optional, helps when fetching clang            |
| TG_BOT_TOKEN    | telegram bot token, needed when TG_NOTIFY=true |
| TG_CHAT_ID      | telegram chat id, needed when TG_NOTIFY=true   |

notes:

- SUSFS needs KSU=true
- LXC only works with BUILD_TARGET=xaga
- TG_NOTIFY=true needs TG_BOT_TOKEN and TG_CHAT_ID

## output

all files go to out/.

| file                          | description             |
| ----------------------------- | ----------------------- |
| out/\<package>-AnyKernel3.zip | flashable package       |
| out/\<package>-boot.img       | xaga boot image         |
| out/\<package>-boot-raw.img   | generic raw boot image  |
| out/\<package>-boot-gz.img    | generic gzip boot image |
| out/\<package>-boot-lz4.img   | generic lz4 boot image  |
| github.json                   | release metadata        |
| build.log                     | build log               |
