import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Annotated

import typer

from .common import die, stdin_text
from .config import (
    BuildSettings,
    build_environment,
    read_toml,
    resolve_settings,
    validate_build,
    validate_managed_path,
)
from .github_release import asset_url_api, asset_url_json
from .meta import write_metadata
from .sources import sync_source
from .tg import TelegramError, notify, send_release

app = typer.Typer(no_args_is_help=True)
release_app = typer.Typer(no_args_is_help=True)
meta_app = typer.Typer(no_args_is_help=True)
tg_app = typer.Typer(no_args_is_help=True)
source_app = typer.Typer(no_args_is_help=True)

app.add_typer(release_app, name="release", hidden=True)
app.add_typer(meta_app, name="meta", hidden=True)
app.add_typer(tg_app, name="tg", hidden=True)
app.add_typer(source_app, name="source", hidden=True)

WORKSPACE = Path(__file__).resolve().parents[1]


def settings_for(
    target: str | None, preset: str = "vnl", **overrides: object
) -> BuildSettings:
    try:
        return resolve_settings(WORKSPACE, target, preset, overrides)
    except (TypeError, ValueError, OSError) as error:
        raise typer.BadParameter(str(error)) from error


@app.command("targets")
def list_targets() -> None:
    default = read_toml(WORKSPACE / "builder.toml")["default_target"]
    for path in sorted((WORKSPACE / "targets").glob("*.toml")):
        settings = settings_for(path.stem)
        marker = " (default)" if settings.target == default else ""
        typer.echo(f"{settings.target}{marker}: {settings.description}")


@app.command("presets")
def list_presets() -> None:
    for name, values in read_toml(WORKSPACE / "presets.toml").items():
        features = ", ".join(key for key, enabled in values.items() if enabled is True)
        marker = " (default)" if name == "vnl" else ""
        typer.echo(f"{name}{marker}: {features or 'vanilla'}")


@app.command("doctor")
def doctor(target: Annotated[str | None, typer.Argument()] = None) -> None:
    settings = settings_for(target)
    result = subprocess.run(
        [
            "bash",
            "-c",
            'source "$1"\nvalidate_deps',
            "esk-doctor",
            str(WORKSPACE / "build.sh"),
        ],
        cwd=WORKSPACE,
        env=os.environ | build_environment(settings),
        check=False,
    )
    if result.returncode:
        distro = platform.freedesktop_os_release()
        family = distro.get("ID", "") + " " + distro.get("ID_LIKE", "")
        if "fedora" in family or "rhel" in family:
            typer.echo(
                "Install dependencies: sudo dnf install aria2 bc bison "
                "util-linux gcc gcc-c++ make ccache curl flex git kmod "
                "libfaketime llvm patch tar xz zip zstd",
                err=True,
            )
        elif "debian" in family or "ubuntu" in family:
            typer.echo(
                "Install dependencies: sudo apt install aria2 bc bison "
                "bsdextrautils build-essential ccache curl flex git kmod "
                "libfaketime llvm patch tar xz-utils zip zstd",
                err=True,
            )
        else:
            typer.echo("Install the missing tools with your package manager.", err=True)
        raise typer.Exit(1)
    typer.echo("Build dependencies are available.")


@app.command("build", help="Build and package a kernel.")
def build(
    target: Annotated[str | None, typer.Argument()] = None,
    preset: str = "vnl",
    kernel_ref: str | None = None,
    ksu_ref: str | None = None,
    debug: Annotated[bool | None, typer.Option("--debug/--no-debug")] = None,
    jobs: int | None = None,
    ccache_size: str | None = None,
    ccache_dir: Path | None = None,
    ccache: Annotated[bool | None, typer.Option("--ccache/--no-ccache")] = None,
    reset_sources: Annotated[
        bool | None, typer.Option("--reset-sources/--no-reset-sources")
    ] = None,
    notify: Annotated[bool | None, typer.Option("--notify/--no-notify")] = None,
    dry_run: Annotated[bool, typer.Option(hidden=True)] = False,
) -> None:
    settings = settings_for(
        target,
        preset,
        kernel_ref=kernel_ref,
        ksu_ref=ksu_ref,
        debug=debug,
        jobs=jobs,
        ccache_size=ccache_size,
        ccache_dir=ccache_dir,
        ccache=ccache,
        reset_sources=reset_sources,
        notify=notify,
    )
    environment = build_environment(settings)
    if dry_run:
        typer.echo(json.dumps(environment, indent=2, sort_keys=True))
        return
    try:
        validate_build(settings, environment)
    except (ValueError, OSError) as error:
        raise typer.BadParameter(str(error)) from error
    result = subprocess.run(
        ["bash", str(WORKSPACE / "build.sh")],
        cwd=WORKSPACE,
        env=os.environ | environment,
        check=False,
    )
    raise typer.Exit(
        result.returncode if result.returncode >= 0 else 128 - result.returncode
    )


@app.command("show", help="Show the selected sources, tools and output paths.")
def show(
    target: Annotated[str | None, typer.Argument()] = None,
    preset: str = "vnl",
    kernel_ref: str | None = None,
    ksu_ref: str | None = None,
    debug: Annotated[bool | None, typer.Option("--debug/--no-debug")] = None,
    jobs: int | None = None,
    ccache_size: str | None = None,
    ccache_dir: Path | None = None,
    ccache: Annotated[bool | None, typer.Option("--ccache/--no-ccache")] = None,
    reset_sources: Annotated[
        bool | None, typer.Option("--reset-sources/--no-reset-sources")
    ] = None,
    notify: Annotated[bool | None, typer.Option("--notify/--no-notify")] = None,
) -> None:
    settings = settings_for(
        target,
        preset,
        kernel_ref=kernel_ref,
        ksu_ref=ksu_ref,
        debug=debug,
        jobs=jobs,
        ccache_size=ccache_size,
        ccache_dir=ccache_dir,
        ccache=ccache,
        reset_sources=reset_sources,
        notify=notify,
    )
    environment = build_environment(settings)
    for label, value in (
        ("Target", settings.target),
        ("Preset", settings.preset),
        ("Kernel", f"{settings.kernel_url} @ {settings.kernel_ref}"),
        ("KernelSU ref", settings.ksu_ref),
        ("AnyKernel3", f"{settings.ak3_url} @ {settings.ak3_ref}"),
        ("Defconfig", settings.defconfig),
        ("Overlays", ", ".join(settings.defconfig_overlays)),
        ("Debug", "enabled" if settings.debug else "disabled"),
        ("Clang", settings.clang_api),
        (
            "Cache",
            f"{environment['CCACHE_DIR']} ({settings.ccache_size})"
            if settings.ccache
            else "disabled",
        ),
        ("Output", environment["OUT_DIR"]),
    ):
        typer.echo(f"{label}: {value}")


@app.command("resolve", help="Print resolved build settings as JSON.", hidden=True)
def resolve(
    target: Annotated[str | None, typer.Argument()] = None,
    preset: str = "vnl",
    kernel_ref: str | None = None,
    ksu_ref: str | None = None,
    debug: Annotated[bool | None, typer.Option("--debug/--no-debug")] = None,
    jobs: int | None = None,
    ccache_size: str | None = None,
    ccache_dir: Path | None = None,
    ccache: Annotated[bool | None, typer.Option("--ccache/--no-ccache")] = None,
    reset_sources: Annotated[
        bool | None, typer.Option("--reset-sources/--no-reset-sources")
    ] = None,
    notify: Annotated[bool | None, typer.Option("--notify/--no-notify")] = None,
) -> None:
    settings = settings_for(
        target,
        preset,
        kernel_ref=kernel_ref,
        ksu_ref=ksu_ref,
        debug=debug,
        jobs=jobs,
        ccache_size=ccache_size,
        ccache_dir=ccache_dir,
        ccache=ccache,
        reset_sources=reset_sources,
        notify=notify,
    )
    environment = build_environment(settings)
    typer.echo(json.dumps(environment, indent=2, sort_keys=True))


@app.command("clean")
def clean(
    target: Annotated[str | None, typer.Argument()] = None,
    sources: bool = False,
    dry_run: bool = False,
) -> None:
    settings = settings_for(target)
    roots = ["work", "staging", "out"]
    if sources:
        roots.append("sources")
    paths = [WORKSPACE / name / settings.target for name in roots]
    try:
        for path in paths:
            validate_managed_path(WORKSPACE, path)
    except ValueError as error:
        raise typer.BadParameter(str(error)) from error
    for path in paths:
        typer.echo(str(path))
        if not dry_run and path.exists():
            shutil.rmtree(path)
    if not dry_run:
        typer.echo(f"Cleaned {settings.target}")


@source_app.command("sync")
def source_sync(
    url: Annotated[str, typer.Argument()],
    ref: Annotated[str, typer.Argument()],
    destination: Annotated[Path, typer.Argument()],
) -> None:
    try:
        revision = sync_source(url, ref, destination)
    except subprocess.CalledProcessError as error:
        typer.echo(f"Git source sync failed (exit {error.returncode})", err=True)
        raise typer.Exit(error.returncode) from error
    except (OSError, ValueError) as error:
        die(str(error))
    typer.echo(revision)


@release_app.command("asset-url")
def release_asset_url(
    pattern: Annotated[str, typer.Argument()] = "*.tar.gz",
    api_url: str | None = typer.Option(
        default=None, help="Fetch release JSON from this GitHub API URL"
    ),
) -> None:
    if api_url is not None:
        typer.echo(asset_url_api(api_url, pattern))
        return

    typer.echo(asset_url_json(stdin_text(), pattern))


@meta_app.command("write")
def meta_write(output: Path) -> None:
    write_metadata(output)


@tg_app.command("notify")
def tg_notify(stage: str, seconds: int = 0) -> None:
    if stage not in {
        "sources",
        "toolchain",
        "configure",
        "compile",
        "modules",
        "package",
        "success",
        "error",
    }:
        raise typer.BadParameter("Unknown notification stage")
    notify(stage, seconds, sys.stdin.read() if stage == "error" else "")


@tg_app.command("release")
def tg_release(manifest: Path, release_url: str) -> None:
    try:
        send_release(manifest, release_url)
    except (TelegramError, ValueError, OSError) as error:
        die(str(error))


if __name__ == "__main__":
    app()
