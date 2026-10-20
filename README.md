# esk builder

Linux kernel builder for **xaga**, with three presets:

| Preset | KernelSU | SuSFS |
| --- | --- | --- |
| `vnl` (default) | No | No |
| `ksu` | Yes | No |
| `ksu-susfs` | Yes | Yes |

Python handles the CLI, configuration, APIs, and metadata. Bash runs the build steps and kernel commands. Local builds and GitHub Actions use the same CLI.

## Setup

Run these commands from the repository root on Ubuntu 24.04:

```bash
sudo apt update
sudo apt install aria2 bc bison bsdextrautils build-essential ccache curl flex git \
  kmod libfaketime llvm patch tar xz-utils zip zstd
```

Install [uv](https://docs.astral.sh/uv/getting-started/installation/), then run:

```bash
uv python install 3.14
uv sync --locked --no-dev
uv run esk targets
uv run esk build xaga --dry-run
uv run esk build xaga
```

The builder downloads the kernel source, AnyKernel3, Clang, and libfakestat. KernelSU and SuSFS presets also download their feature sources. Builds run without root privileges.

## Build

```bash
uv run esk build xaga --preset ksu
uv run esk build xaga --preset ksu-susfs --jobs 8
uv run esk build xaga --kernel-ref my-branch --stock-config false
uv run esk build xaga --no-ccache
uv run esk build xaga --reset-sources
```

Omitting the target uses `default_target` from `builder.toml`. `--dry-run` prints the resolved settings and managed paths without downloading, deleting, or compiling anything.

Run builds through the Python CLI. `build.sh` is its internal backend.

### Telegram notifications

Set `TG_BOT_TOKEN` and `TG_CHAT_ID` in your environment, then add `--notify` to send build notifications and the completed AnyKernel3 package.

Notifications default to off. When enabled, a notification failure stops the command. Completed packages remain available in the output directory.

Set `GH_TOKEN` for authenticated GitHub asset lookups and higher API rate limits. Supply tokens through the environment.

## Configuration

| File | Settings |
| --- | --- |
| `builder.toml` | Project identity, tool and feature providers, defaults, ccache |
| `targets/xaga.toml` | Kernel and AnyKernel3 URLs and refs, defconfig overlays, module-load directory, stock-config default |
| `targets/xaga/modules.load*` | Device module-load lists |
| `presets.toml` | KernelSU/SuSFS combinations |

Settings take precedence in this order:

```text
CLI options > preset > target > project defaults
```

Lists replace earlier lists. The preset controls KernelSU and SuSFS.

`--stock-config auto` reads the target's `stock_config_default`, which is `false` for xaga. Pass `true` or `false` to override it.

### Forks and other devices

Edit the project identity, provider defaults, and target URLs, refs, and assets for your fork. Kernel refs accept branches, tags, or commit IDs.

To add a similar device, create `targets/<name>.toml` and its load lists. Devices with different packaging requirements also need changes to the Bash scripts.

## Outputs and cleanup

Build outputs go to `out/<target>/<preset>/`. Each build replaces that directory.

| File | Contents |
| --- | --- |
| `<name>-<target>-<version>-<variant>-<commit>-AnyKernel3.zip` | AnyKernel3 package |
| `module.tar.xz` | `vendor_boot/` and `vendor_dlkm/`, also included in the AnyKernel3 package |
| `build.json` | Build options, source revisions, compiler identity, artifact SHA-256 hashes |
| `build.log` | Build log |
| `ccache-stats.txt` and `ccache.log` | Compiler-cache statistics and log |

> Builds reset and clean their managed source checkouts. Keep your own edits outside `sources/`. After changing a source URL, pass `--reset-sources` to replace the old checkout. Run builds sequentially within one checkout.

| Directory | Contents |
| --- | --- |
| `sources/<target>/` | Source checkouts |
| `work/<target>/` | Incremental compiler outputs |
| `staging/<target>/` | Installed and staged modules |
| `out/<target>/<preset>/` | Packages, metadata, logs |
| `tools/` | Toolchain, libraries, generated launchers |
| `.ccache/` | Shared compiler cache |

```bash
uv run esk clean xaga
uv run esk clean xaga --sources
```

`clean` removes the target's work, staging, and outputs. Add `--sources` to remove its source checkouts too. Tools and ccache stay available for later builds.

## Compiler cache

All three presets share one local cache with a default size of `2G`.

Use `--ccache-size` to change the size. Set `ccache_dir` in `builder.toml` to change the default location, or pass `--ccache-dir PATH` for one build.

Check `ccache-stats.txt` and `ccache.log` in the output directory for build-specific statistics. To view the shared cache's statistics, run:

```bash
ccache --dir .ccache --show-stats
```

## GitHub Actions

Run `build.yml` manually or call it as a reusable workflow. It accepts a target, preset, kernel-ref override, stock-config choice, and Telegram notification setting.

Each run builds one preset and uploads packages, metadata, and logs as an Actions artifact. Add repository secrets for the API and notification services you enable.

The workflow restores compiler caches from the same preset first, then the same target. Each run saves its own snapshot.

## Development

Install `just`, `shellcheck`, `shfmt`, `ccache`, and `gcc`, then run:

```bash
uv sync --locked
just check
```

Individual checks are available through `fmt-check`, `bash-check`, `lint`, `py-lint`, `py-check`, and `test`.

`just fmt` formats tracked shell scripts. `just build xaga --preset ksu` and `just clean xaga` forward their arguments to the CLI.

### Code layout

```text
build.sh             # Entry point, initialization, build order
scripts/
  common.sh          # Logging and shared helpers
  sources.sh         # Source checkout setup and revisions
  toolchain.sh       # Clang, preload launchers, ccache
  configure.sh       # KernelSU, SuSFS, stock config, LTO
  compile.sh         # Kernel and module compilation/install
  modules.sh         # vendor_boot/vendor_dlkm staging
  package.sh         # AnyKernel3 archive and metadata
  notify.sh          # Build/error notifications
esk/                 # Python CLI, configuration, Git/API helpers
tests/               # Unit and fixture tests
pyproject.toml       # Package, dependencies, check settings
uv.lock              # Locked Python dependencies
```

Edit `main()` in `build.sh` to change the build order, or the corresponding script to change a stage. `esk/config.py` resolves settings before starting the Bash backend.
