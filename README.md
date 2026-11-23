# ESK builder

Build and package the ESK Kernel for xaga and plato, locally or with GitHub Actions.

| Preset | KernelSU | SuSFS |
| --- | --- | --- |
| `vnl` (default) | No | No |
| `ksu` | Yes | No |
| `ksu-susfs` | Yes | Yes |

## Setup

On Ubuntu 24.04:

```bash
sudo apt update
sudo apt install aria2 bc bison bsdextrautils build-essential ccache curl flex git \
  kmod libfaketime llvm patch tar xz-utils zip zstd
```

On Fedora:

```bash
sudo dnf install aria2 bc bison util-linux gcc gcc-c++ make ccache curl flex git \
  kmod libfaketime llvm patch tar xz zip zstd
```

Install [uv](https://docs.astral.sh/uv/getting-started/installation/), then:

```bash
uv python install 3.14
uv sync --locked --no-dev
uv run esk doctor xaga # optional
uv run esk build xaga
```

The builder downloads its sources and toolchain. Builds do not require root.

## Build

```bash
uv run esk targets
uv run esk presets
uv run esk show xaga --preset ksu-susfs
uv run esk build xaga --preset ksu-susfs
uv run esk build plato --preset ksu
```

Omit the target to use `default_target` from `builder.toml`. Run `uv run esk build --help` for all options. Common overrides:

```bash
uv run esk build xaga --kernel-ref my-branch
uv run esk build xaga --preset ksu-susfs --ksu-ref main
uv run esk build xaga --debug
uv run esk build xaga --jobs 8 --no-ccache
```

`--ksu-ref` overrides BakaSU branch.

`--debug` enables kernel debugging options. Enable scheduler statistics at runtime when needed:

```bash
sysctl -w kernel.sched_schedstats=1
```

Settings are resolved in this order: CLI options > preset > target > `builder.toml`.

## Outputs and cleanup

Outputs are written to `out/<target>/<preset>/`:

- `*-AnyKernel3.zip`: flashable package.
- `module.tar.xz`: staged modules, also included in the package.
- `build.json` and `build.log`: build settings, revisions, artifact hashes, and log.
- `ccache-stats.txt` and `ccache.log`: compiler-cache information when enabled.

The builder resets and cleans its managed source checkouts. Keep your own edits outside `sources/`. 
After changing a source URL, use `--reset-sources` to replace the old checkout.

```bash
uv run esk clean xaga --dry-run
uv run esk clean xaga              # work, staging, and outputs
uv run esk clean xaga --sources    # also remove source checkouts
```

By default, the ccache defaults to 2 GB.

## Configuration

- `builder.toml`: project defaults, toolchain sources, and cache settings.
- `targets/*.toml`: kernel and AnyKernel3 sources, config overlays, and module-load paths.
- `targets/<target>/modules.load*`: device module-load lists.
- `presets.toml`: KernelSU and SuSFS settings.

## GitHub Actions

`build.yml` builds a single device and preset. `multi-build.yml` builds all combinations or a custom selection.

The multi-build workflow resolves kernel refs, checks artifacts and can publish prereleases to `ESK-Project/esk-releases`. Publishing requires `GH_TOKEN` and a release tag. Debug builds cannot be published.

Build outputs and logs are available as GitHub Actions artifacts. Telegram notifications require `TG_BOT_TOKEN` and `TG_CHAT_ID`.

## Development

Install [just](https://just.systems/man/en/chapter_4.html), `shellcheck`, and `shfmt`, then run:

```bash
uv sync --locked
just check
```

Use `just fmt` to format shell scripts and Python code.

`esk/` handles the CLI and configuration. `build.sh` and `scripts/` handle kernel builds.
