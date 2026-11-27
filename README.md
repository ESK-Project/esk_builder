# ESK builder

Build and package the ESK Kernel for xaga and plato, locally or with GitHub Actions.

## Build your first ZIP

1. Open Actions → Build kernel → Run workflow.
2. Choose your device (`xaga` or `plato`) and a variant. Leave the other fields at their defaults.
3. Run the workflow. When it finishes, download the artifact and open it to find the `*-AnyKernel3.zip`.

| Variant | KernelSU | SuSFS |
| --- | --- | --- |
| `vnl` (default) | No | No |
| `ksu` | Yes | No |
| `ksu-susfs` | Yes | Yes |

## Build locally

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
uv run esk build xaga
```

The builder downloads its sources and toolchain and runs without root. The ZIP lands in `out/xaga/vnl/`. Use `plato` for Plato or add `--preset ksu-susfs` to change the variant. If setup fails, run `uv run esk doctor xaga`.

## Advanced setup

### Configuration

Choose where to make a change based on which builds should use it.

| File | What it controls |
| --- | --- |
| `builder.toml` | Shared defaults, including the default device, Clang source, and compiler cache |
| `targets/<device>.toml` | The device's kernel and AnyKernel3 sources, kernel config, and module-load directory |
| `targets/<device>/modules.load*` | Which modules load during boot and recovery |
| `presets.toml` | Which variants enable KernelSU and SuSFS |

The builder starts with `builder.toml`, then applies the device config, the chosen preset, and finally any command-line options you pass. With no device or preset specified, it uses `default_target` from `builder.toml` and the `vnl` preset.

To see which sources, config, and output path a build would use, run:

```bash
uv run esk show xaga --preset ksu-susfs
```

### Build overrides

Run `uv run esk build --help` for all options. Use `--kernel-ref` to pick a kernel branch, tag, or commit and `--ksu-ref` to override the BakaSU ref. `--debug` enables performance debugging. To collect scheduler statistics at runtime, run `sysctl -w kernel.sched_schedstats=1`.

### Outputs and cleanup

Find the build files in `out/<target>/<preset>/`.

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

The default ccache limit is 2 GB.

### Batch builds and releases

Use Multi-variant Build to build several devices or variants at once. Choose full for all combinations or custom to pick your own. To publish a prerelease to `ESK-Project/esk-releases`, enable Create release and enter a release tag. Publishing requires `GH_TOKEN`. Debug builds are for testing and cannot be published.

### Telegram notifications

- Single build with live progress, build logs, and a ZIP on success.
- Release post with ZIPs grouped by device.

To turn this on, add the secrets below in your GitHub repo under Settings → Secrets and variables → Actions. Give the bot permission to post in your Telegram chat or channel.

| Secret | Used by | Value |
| --- | --- | --- |
| `TG_CHAT_ID` | Both | Chat ID or channel username |
| `TG_BOT_TOKEN` | Both | Bot token from BotFather |
| `TELEGRAM_API_ID` | Release | `api_id` from Telegram |
| `TELEGRAM_API_HASH` | Release | `api_hash` from Telegram |

For release posts, sign in at [my.telegram.org](https://my.telegram.org), open "API development tools", and create an application. Copy the two values into the secrets above. CI uses them to upload the ZIPs through a temporary Telegram server. [Telegram setup guide](https://core.telegram.org/api/obtaining_api_id)

If the bot previously used the cloud Bot API, call `logOut` there once before its first local run. Cloud build notifications may be unavailable for 10 minutes after that call. [Telegram Bot API](https://core.telegram.org/bots/api#logout)

## Development

Install [just](https://just.systems/man/en/chapter_4.html), `shellcheck`, and `shfmt`, then run:

```bash
uv sync --locked
just check
```

Use `just fmt` to format shell scripts and Python code.

`esk/` holds the CLI, configuration, and CI workflow code. `build.sh` and `scripts/` hold the shell build steps.
