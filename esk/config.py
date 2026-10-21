import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(kw_only=True)
class BuildSettings:
    workspace: Path
    target: str
    preset: str

    description: str
    kernel_url: str
    kernel_ref: str
    ak3_url: str
    ak3_ref: str
    defconfig: str
    defconfig_overlays: list[str]
    module_load_dir: str | Path

    kernel_name: str
    build_user: str
    build_host: str
    timezone: str
    fake_time: str
    jobs: int = field(default_factory=lambda: os.cpu_count() or 1)
    lto: str
    stock_config: bool
    ksu: bool
    susfs: bool

    ccache: bool
    ccache_size: str
    ccache_dir: str | Path
    notify: bool
    reset_sources: bool

    clang_api: str
    libfakestat_api: str
    ksu_setup_url: str
    ksu_ref: str
    susfs_url: str
    susfs_ref: str


def resolve_settings(
    workspace: Path,
    target: str | None = None,
    preset: str = "vnl",
    overrides: dict[str, object] | None = None,
) -> BuildSettings:
    workspace = workspace.resolve()
    project = read_toml(workspace / "builder.toml")
    default_target = project.pop("default_target")
    if target is None:
        target = default_target
    targets = {path.stem: path for path in (workspace / "targets").glob("*.toml")}
    if target not in targets:
        raise ValueError(
            f"Unknown target: {target}. Available: {', '.join(sorted(targets))}"
        )
    device = read_toml(targets[target])
    presets = read_toml(workspace / "presets.toml")
    if preset not in presets:
        raise ValueError(f"Unknown preset: {preset}. Available: {', '.join(presets)}")
    overrides = {
        key: value for key, value in (overrides or {}).items() if value is not None
    }
    values = project | device | presets[preset] | overrides
    stock_default = values.pop("stock_config_default")
    stock_config = values["stock_config"]
    if isinstance(stock_config, str):
        if stock_config not in {"auto", "true", "false"}:
            raise ValueError("stock_config must be auto, true or false")
        values["stock_config"] = (
            stock_default if stock_config == "auto" else stock_config == "true"
        )
    settings = BuildSettings(
        workspace=workspace, target=target, preset=preset, **values
    )
    if settings.jobs < 1:
        raise ValueError("jobs must be greater than zero")
    if settings.susfs and not settings.ksu:
        raise ValueError("SuSFS requires KernelSU")
    return settings


def validate_build(settings: BuildSettings, environment: dict[str, str]) -> None:
    for name in (
        "KERNEL",
        "AK3",
        "SUSFS_DIR",
        "KERNEL_OUT",
        "INSTALLED_MODULES",
        "MOD_FLAT",
        "MOD_STAGE",
        "OUT_DIR",
        "CLANG",
        "LIBFAKESTAT_DIR",
        "WRAPPER_DIR",
    ):
        validate_managed_path(settings.workspace, Path(environment[name]))
    for name in ("modules.load", "modules.load.vendor_boot", "modules.load.recovery"):
        path = settings.workspace / settings.module_load_dir / name
        if not path.is_file():
            raise ValueError(f"Missing module-load file: {path}")


def validate_managed_path(workspace: Path, path: Path) -> None:
    if (
        path == workspace
        or not path.is_relative_to(workspace)
        or path.resolve() != path
    ):
        raise ValueError(f"Unsafe managed path: {path}")


def read_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as handle:
        return tomllib.load(handle)
