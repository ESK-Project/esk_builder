import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Annotated

import typer

from .ack_package import package_ack
from .common import die, stdin_text
from .config import BuildSettings, load_target, resolve_settings
from .github_release import asset_url_api, asset_url_json
from .meta import write_metadata
from .sources import sync_source
from .tg import notify, send_document, send_message

app = typer.Typer(no_args_is_help=True)
release_app = typer.Typer(no_args_is_help=True)
meta_app = typer.Typer(no_args_is_help=True)
tg_app = typer.Typer(no_args_is_help=True)
source_app = typer.Typer(no_args_is_help=True)

app.add_typer(release_app, name="release")
app.add_typer(meta_app, name="meta")
app.add_typer(tg_app, name="tg")
app.add_typer(source_app, name="source")

WORKSPACE = Path(__file__).resolve().parents[1]


def settings_for(
    target: str | None, preset: str = "vnl", **overrides: object
) -> BuildSettings:
    try:
        return resolve_settings(WORKSPACE, target, preset, overrides)
    except (ValueError, OSError) as error:
        raise typer.BadParameter(str(error)) from error


@app.command("targets")
def list_targets() -> None:
    for path in sorted((WORKSPACE / "targets").glob("*.toml")):
        config = load_target(WORKSPACE, path.stem)
        typer.echo(f"{path.stem}: {config['description']}")


@app.command("profile")
def profile(target: Annotated[str, typer.Argument()]) -> None:
    try:
        config = load_target(WORKSPACE, target)
    except (ValueError, OSError) as error:
        raise typer.BadParameter(str(error)) from error
    typer.echo(json.dumps(config, indent=2))


@app.command("build")
def build(
    target: Annotated[str | None, typer.Argument()] = None,
    preset: str = "vnl",
    kernel_ref: str | None = None,
    stock_config: str | None = None,
    jobs: int | None = None,
    ccache_size: str | None = None,
    ccache_dir: Path | None = None,
    ccache: Annotated[bool | None, typer.Option("--ccache/--no-ccache")] = None,
    reset_sources: Annotated[
        bool | None, typer.Option("--reset-sources/--no-reset-sources")
    ] = None,
    notify: Annotated[bool | None, typer.Option("--notify/--no-notify")] = None,
    dry_run: bool = False,
) -> None:
    settings = settings_for(
        target,
        preset,
        kernel_ref=kernel_ref,
        stock_config=stock_config,
        jobs=jobs,
        ccache_size=ccache_size,
        ccache_dir=ccache_dir,
        ccache=ccache,
        reset_sources=reset_sources,
        notify=notify,
    )
    environment = settings.environment()
    if dry_run:
        typer.echo(json.dumps(environment, indent=2, sort_keys=True))
        return
    result = subprocess.run(
        ["bash", str(WORKSPACE / "build.sh")],
        cwd=WORKSPACE,
        env=os.environ | environment,
        check=False,
    )
    raise typer.Exit(
        result.returncode if result.returncode >= 0 else 128 - result.returncode
    )


@app.command("ack")
def ack(
    modules: Annotated[Path, typer.Argument()],
    llvm: Annotated[Path, typer.Option()],
    action: str = "build",
    out: Path | None = None,
    jobs: Annotated[int, typer.Option(min=1)] = 8,
    dry_run: bool = False,
) -> None:
    if action not in {"check", "configure", "build"}:
        raise typer.BadParameter("Action must be check, configure, or build")
    runner = modules.resolve() / "xaga/build.py"
    if not runner.is_file():
        raise typer.BadParameter(f"Missing ACK build entry point: {runner}")
    args = [
        sys.executable,
        "-B",
        str(runner),
        action,
        "--llvm",
        str(llvm.resolve()),
        "--jobs",
        str(jobs),
    ]
    if out is not None:
        args.extend(["--out", str(out.resolve())])
    if dry_run:
        args.append("--dry-run")
    result = subprocess.run(args, check=False)
    raise typer.Exit(
        result.returncode if result.returncode >= 0 else 128 - result.returncode
    )


@app.command("pack-ack")
def pack_ack(
    out: Annotated[Path, typer.Argument()],
    anykernel: Annotated[Path, typer.Option()],
    target: str = "xaga-6.12",
) -> None:
    try:
        for package in package_ack(WORKSPACE, target, out, anykernel):
            typer.echo(package)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        die(str(error))


@app.command("clean")
def clean(
    target: Annotated[str | None, typer.Argument()] = None, sources: bool = False
) -> None:
    settings = settings_for(target)
    roots = ["work", "staging", "out"]
    if sources:
        roots.append("sources")
    for name in roots:
        path = WORKSPACE / name / settings.target
        if path.exists():
            shutil.rmtree(path)
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


@tg_app.command("msg")
def tg_msg() -> None:
    send_message(stdin_text())


@tg_app.command("doc")
def tg_doc(file: Path) -> None:
    send_document(file, stdin_text())


@tg_app.command("notify")
def tg_notify(stage: str, seconds: int = 0) -> None:
    if stage not in {"start", "success", "error"}:
        raise typer.BadParameter("Stage must be start, success, or error")
    notify(stage, seconds, sys.stdin.read() if stage == "error" else "")


if __name__ == "__main__":
    app()
