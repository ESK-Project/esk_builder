"""Resolve checked-in settings once, before the Bash backend starts."""

import os
import tomllib
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class BuildSettings(BaseModel):
    model_config = ConfigDict(extra="forbid")

    workspace: Path
    target: str
    preset: str
    description: str
    kernel_name: str
    build_user: str
    build_host: str
    timezone: str
    lto: Literal["thin", "full"]
    ccache: bool
    ccache_size: str
    ccache_dir: Path
    notify: bool
    reset_sources: bool
    stock_config: bool
    jobs: int = Field(default_factory=lambda: os.cpu_count() or 1, gt=0)
    fake_time: str
    clang_api: str
    libfakestat_api: str
    ksu_setup_url: str
    ksu_ref: str
    susfs_url: str
    susfs_ref: str
    kernel_url: str
    kernel_ref: str
    ak3_url: str
    ak3_ref: str
    defconfig: str
    defconfig_overlays: list[str]
    module_load_dir: Path
    stock_config_default: bool
    ksu: bool
    susfs: bool

    @field_validator("*", mode="before")
    @classmethod
    def no_multiline_settings(cls, value: object) -> object:
        items = value if isinstance(value, list) else [value]
        for item in items:
            if isinstance(item, str) and any(char in item for char in "\n\r\0"):
                raise ValueError("Settings cannot contain newlines or NUL characters")
        return value

    def environment(self) -> dict[str, str]:
        root = self.workspace
        source = root / "sources" / self.target
        stage = root / "staging" / self.target
        out = root / "out" / self.target / self.preset
        tool = root / "tools"
        paths = {
            "WORKSPACE": root,
            "SOURCE_DIR": source,
            "KERNEL": source / "kernel",
            "AK3": source / "anykernel3",
            "SUSFS_DIR": source / "susfs",
            "KERNEL_OUT": root / "work" / self.target,
            "STAGING": stage,
            "INSTALLED_MODULES": stage / "installed",
            "MOD_FLAT": stage / "flatten",
            "MOD_STAGE": stage / "modules",
            "MOD_LOAD": root / self.module_load_dir,
            "OUT_DIR": out,
            "LOGFILE": out / "build.log",
            "META_FILE": out / "build.json",
            "MODULE_PACKAGE": out / "module.tar.xz",
            "CLANG": tool / "clang",
            "CLANG_BIN": tool / "clang/bin",
            "LIBFAKESTAT_DIR": tool / "libfakestat",
            "LIBFAKESTAT": tool / "libfakestat/libfakestat.so",
            "WRAPPER_DIR": tool / "wrappers",
            "KERNEL_PATCHES": root / "kernel_patches",
            "CCACHE_DIR": root / self.ccache_dir,
            "CCACHE_STATSLOG": out / "ccache.log",
            "DLKM_FS_CONFIG": source / "anykernel3/config/vendor_dlkm_fs_config",
            "DLKM_FILE_CONTEXTS": source
            / "anykernel3/config/vendor_dlkm_file_contexts",
        }
        values = {
            "BUILD_TARGET": self.target,
            "TARGET_NAME": self.target,
            "PRESET": self.preset,
            "KERNEL_NAME": self.kernel_name,
            "KBUILD_BUILD_USER": self.build_user,
            "KBUILD_BUILD_HOST": self.build_host,
            "TZ": self.timezone,
            "CLANG_LTO": self.lto,
            "CCACHE_ENABLED": self.ccache,
            "CCACHE_SIZE": self.ccache_size,
            "TG_NOTIFY": self.notify,
            "RESET_SOURCES": self.reset_sources,
            "STOCK_CONFIG": self.stock_config,
            "JOBS": self.jobs,
            "FAKE_TIME": self.fake_time,
            "CLANG_RELEASE_API": self.clang_api,
            "LIBFAKESTAT_RELEASE_API": self.libfakestat_api,
            "KSU_SETUP_URL": self.ksu_setup_url,
            "KSU_REF": self.ksu_ref,
            "SUSFS_URL": self.susfs_url,
            "SUSFS_REF": self.susfs_ref,
            "KERNEL_URL": self.kernel_url,
            "KERNEL_REF": self.kernel_ref,
            "AK3_URL": self.ak3_url,
            "AK3_REF": self.ak3_ref,
            "KERNEL_DEFCONFIG": self.defconfig,
            "DEFCONFIG_OVERLAYS": "\n".join(self.defconfig_overlays),
            "KSU": self.ksu,
            "SUSFS": self.susfs,
        }
        environment = {}
        for key, value in (paths | values).items():
            if isinstance(value, bool):
                environment[key] = "true" if value else "false"
            else:
                environment[key] = str(value)
        return environment


def load_target(workspace: Path, target: str) -> dict[str, object]:
    targets = {path.stem: path for path in (workspace / "targets").glob("*.toml")}
    if target not in targets:
        raise ValueError(
            f"Unknown target: {target}. Available: {', '.join(sorted(targets))}"
        )
    with targets[target].open("rb") as handle:
        return tomllib.load(handle)


def resolve_settings(
    workspace: Path,
    target: str | None = None,
    preset: str = "vnl",
    overrides: dict[str, object] | None = None,
) -> BuildSettings:
    workspace = workspace.resolve()
    with (workspace / "builder.toml").open("rb") as handle:
        project = tomllib.load(handle)
    default_target = str(project.pop("default_target"))
    if target is None:
        target = default_target
    device = load_target(workspace, target)
    if device.get("layout") == "ack":
        raise ValueError("Use esk ack for ACK targets, or select this target in CI")
    with (workspace / "presets.toml").open("rb") as handle:
        presets = tomllib.load(handle)
    if preset not in presets:
        raise ValueError(f"Unknown preset: {preset}. Available: {', '.join(presets)}")
    overrides = {
        key: value for key, value in (overrides or {}).items() if value is not None
    }
    allowed = {
        "kernel_ref",
        "stock_config",
        "jobs",
        "ccache_size",
        "ccache_dir",
        "ccache",
        "reset_sources",
        "notify",
    }
    if overrides.keys() - allowed:
        raise ValueError(
            f"Unsupported override: {', '.join(overrides.keys() - allowed)}"
        )
    values = project | device | presets[preset] | overrides
    if values["stock_config"] == "auto":
        values["stock_config"] = values["stock_config_default"]
    settings = BuildSettings(
        workspace=workspace, target=target, preset=preset, **values
    )
    if settings.susfs and not settings.ksu:
        raise ValueError("SuSFS requires KernelSU")
    validate_managed_paths(settings)
    for name in ("modules.load", "modules.load.vendor_boot", "modules.load.recovery"):
        path = workspace / settings.module_load_dir / name
        if not path.is_file():
            raise ValueError(f"Missing module-load file: {path}")
    return settings


def validate_managed_paths(settings: BuildSettings) -> None:
    """Reject symlinks before the backend cleans or writes managed directories."""
    workspace = settings.workspace
    environment = settings.environment()
    for key in (
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
        path = Path(environment[key])
        for ancestor in (path, *path.parents):
            if ancestor == workspace:
                break
            if ancestor.is_symlink():
                raise ValueError(f"Managed path cannot use a symlink: {ancestor}")
