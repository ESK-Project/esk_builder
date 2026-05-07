# rpi esk builder

build rpi 4b kernel

## structure

- build.sh: main entry point
- config.sh: defaults, repos, paths, and build settings
- build/: setup and compile kernel
- ci/: packaging, metadata, and telegram helpers
- py/: small python helpers
- .github/workflows/: ci workflows

## requirements

ubuntu/debian:

```bash
sudo apt install aria2 bc bison build-essential ccache curl debhelper dpkg-dev fakeroot flex gcc-aarch64-linux-gnu git jq just libelf-dev libfaketime libssl-dev make python3-requests tar xz-utils zip zstd
```

fedora:

```bash
sudo dnf install aria2 bc bison ccache curl elfutils-libelf-devel fakeroot gcc-aarch64-linux-gnu git jq just libfaketime make openssl-devel python3-requests tar xz zip zstd
```

## run

```bash
just build
```

format script:

```bash
just fmt
```

run checks:

```bash
just check
```

clean build:

```bash
just clean
```

## inputs

| env var         | description                                   | type |
| --------------- | --------------------------------------------- | ---- |
| BRANCH_OVERRIDE | use a different kernel branch                 | str  |
| KERNEL_DEFCONFIG | kernel defconfig, default `bcm2711_defconfig` | str  |
| CROSS_COMPILE   | cross prefix, default `aarch64-linux-gnu-`    | str  |
| JOBS            | set make job count                            | int  |
| RESET_SOURCES   | re-clone sources before building              | bool |
| GH_TOKEN        | github token for clang download in ci         | str  |
| TG_NOTIFY       | send telegram updates                         | bool |
| TG_BOT_TOKEN    | telegram bot token, needed when TG_NOTIFY=true | str  |
| TG_CHAT_ID      | telegram chat id, needed when TG_NOTIFY=true  | str  |

- bool accepts true/false, t/f, yes/no, y/n, on/off, 1/0
- TG_NOTIFY=true needs TG_BOT_TOKEN and TG_CHAT_ID

## output

| file                               | description               |
| ---------------------------------- | ------------------------- |
| work/                              | kernel out                |
| out/*.deb                          | generated deb packages    |
| out/\<package>.tar.xz              | collected deb archive     |
| github.json                        | release metadata          |
| build.log                          | build log                 |
