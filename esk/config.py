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
    debug: bool
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


def build_environment(settings: BuildSettings) -> dict[str, str]:
    root = settings.workspace
    source = root / "sources" / settings.target
    stage = root / "staging" / settings.target
    out = root / "out" / settings.target / settings.preset
    tool = root / "tools"
    paths = {
        "WORKSPACE": root,
        "SOURCE_DIR": source,
        "KERNEL": source / "kernel",
        "AK3": source / "anykernel3",
        "SUSFS_DIR": source / "susfs",
        "KERNEL_OUT": root / "work" / settings.target,
        "STAGING": stage,
        "INSTALLED_MODULES": stage / "installed",
        "MOD_FLAT": stage / "flatten",
        "MOD_STAGE": stage / "modules",
        "MOD_LOAD": root / settings.module_load_dir,
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
        "CCACHE_DIR": root / settings.ccache_dir,
        "CCACHE_STATSLOG": out / "ccache.log",
        "DLKM_FS_CONFIG": source / "anykernel3/config/vendor_dlkm_fs_config",
    }
    values = {
        "BUILD_TARGET": settings.target,
        "TARGET_NAME": settings.target,
        "PRESET": settings.preset,
        "KERNEL_NAME": settings.kernel_name,
        "KBUILD_BUILD_USER": settings.build_user,
        "KBUILD_BUILD_HOST": settings.build_host,
        "TZ": settings.timezone,
        "CLANG_LTO": settings.lto,
        "CCACHE_ENABLED": settings.ccache,
        "CCACHE_SIZE": settings.ccache_size,
        "TG_NOTIFY": settings.notify,
        "RESET_SOURCES": settings.reset_sources,
        "DEBUG": settings.debug,
        "JOBS": settings.jobs,
        "FAKE_TIME": settings.fake_time,
        "CLANG_RELEASE_API": settings.clang_api,
        "LIBFAKESTAT_RELEASE_API": settings.libfakestat_api,
        "KSU_SETUP_URL": settings.ksu_setup_url,
        "KSU_REF": settings.ksu_ref,
        "SUSFS_URL": settings.susfs_url,
        "SUSFS_REF": settings.susfs_ref,
        "KERNEL_URL": settings.kernel_url,
        "KERNEL_REF": settings.kernel_ref,
        "AK3_URL": settings.ak3_url,
        "AK3_REF": settings.ak3_ref,
        "KERNEL_DEFCONFIG": settings.defconfig,
        "DEFCONFIG_OVERLAYS": "\n".join(settings.defconfig_overlays),
        "KSU": settings.ksu,
        "SUSFS": settings.susfs,
    }
    environment = {}
    for key, value in (paths | values).items():
        if isinstance(value, bool):
            environment[key] = "true" if value else "false"
        else:
            environment[key] = str(value)
    return environment
