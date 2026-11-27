# ESK builder

Build ESK for xaga and plato.

## Build your first ZIP

1. Open Actions → Build kernel → Run workflow.
2. Choose your device (`xaga` or `plato`) and a variant. Leave the other fields at their defaults.
3. Run the workflow. Find `*-AnyKernel3.zip` in the run's artifacts.

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

Find the ZIP in `out/xaga/vnl/`. Use `plato` for Plato or add `--preset ksu-susfs` to change the variant. For setup errors, run `uv run esk doctor xaga`.

## Advanced setup

### Configuration

| File | What it controls |
| --- | --- |
| `builder.toml` | Defaults for all builds |
| `targets/<device>.toml` | Sources and kernel config for each device |
| `targets/<device>/modules.load*` | Which modules load during boot and recovery |
| `presets.toml` | Which variants enable KernelSU and SuSFS |

`builder.toml` → device config → preset → command-line options

Later settings win. Defaults are `default_target` and `vnl`.

Preview settings with `esk show`.

```bash
uv run esk show xaga --preset ksu-susfs
```

### Build overrides

Pick a kernel ref with `--kernel-ref` or a BakaSU ref with `--ksu-ref`. Use `--debug` for performance debugging. Run `sysctl -w kernel.sched_schedstats=1` on the device to collect scheduler stats.

Run `uv run esk build --help` for all options.

### Outputs and cleanup

Find build outputs in `out/<target>/<preset>/`.

The builder resets and cleans its checkouts in `sources/`. Keep your edits outside that directory. Use `--reset-sources` after changing a source URL.

```bash
uv run esk clean xaga --dry-run
uv run esk clean xaga              # work, staging, and outputs
uv run esk clean xaga --sources    # also remove source checkouts
```

The default ccache limit is 2 GB.

### Batch builds and releases

Use Multi-variant Build for batch builds. Choose full for all combinations or custom to pick your own.

Set `GH_TOKEN` to publish to `ESK-Project/esk-releases`. Enable Create release and enter a tag. Leave debug off.

### Telegram notifications

- Single builds show live progress and attach the log. Successful builds also attach the ZIP.
- Release posts group ZIPs by device.

Add the secrets under Settings → Secrets and variables → Actions. Give the bot permission to post.

| Secret | Used by | Value |
| --- | --- | --- |
| `TG_CHAT_ID` | Both | Chat ID or channel username |
| `TG_BOT_TOKEN` | Both | Bot token from BotFather |
| `TELEGRAM_API_ID` | Both | `api_id` from Telegram |
| `TELEGRAM_API_HASH` | Both | `api_hash` from Telegram |

Sign in at my.telegram.org and create an application under "API development tools". Copy its API ID and hash into the secrets above. [Sign in](https://my.telegram.org) · [Telegram setup guide](https://core.telegram.org/api/obtaining_api_id)

If the bot used the cloud API, run "Log out Telegram bot" once in Actions. For local builds with `--notify`, set `TG_BOT_API_URL` to your local Bot API server.

## Development

Install [just](https://just.systems/man/en/chapter_4.html), `shellcheck`, and `shfmt`, then run:

```bash
uv sync --locked
just check
```

Use `just fmt` to format shell scripts and Python code.

`esk/` holds the CLI, configuration, and CI workflow code. `build.sh` and `scripts/` hold the shell build steps.
