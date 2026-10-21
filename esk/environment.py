from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .config import BuildSettings


def build_environment(settings: "BuildSettings") -> dict[str, str]:
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
        "DLKM_FILE_CONTEXTS": source / "anykernel3/config/vendor_dlkm_file_contexts",
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
        "STOCK_CONFIG": settings.stock_config,
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
