from pathlib import Path
from typing import Annotated

import typer

from .common import escape_md_v2, stdin_text
from .github_release import asset_url_api, asset_url_json, next_tag
from .meta import write_metadata
from .tg import send_document, send_document_gallery, send_message

app = typer.Typer(no_args_is_help=True)
release_app = typer.Typer(no_args_is_help=True)
meta_app = typer.Typer(no_args_is_help=True)
tg_app = typer.Typer(no_args_is_help=True)
util_app = typer.Typer(no_args_is_help=True)

app.add_typer(release_app, name="release")
app.add_typer(meta_app, name="meta")
app.add_typer(tg_app, name="tg")
app.add_typer(util_app, name="util")


@release_app.command("asset-url")
def release_asset_url(
    pattern: Annotated[str, typer.Argument()] = "*.tar.gz",
    api_url: str | None = typer.Option(default=None, help="Fetch release JSON from this GitHub API URL"),
) -> None:
    if api_url is not None:
        typer.echo(asset_url_api(api_url, pattern))
        return

    typer.echo(asset_url_json(stdin_text(), pattern))


@release_app.command("next-tag")
def release_next_tag(repo: Annotated[str, typer.Argument()]) -> None:
    typer.echo(next_tag(repo))


@meta_app.command("write")
def meta_write(
    output: Path,
    kernel_version: str,
    kernel_name: str,
    toolchain: str,
    package_name: str,
    variant: str,
    name: str,
    out_dir: str,
    release_repo: str,
    release_branch: str,
    kernel_commit: str,
) -> None:
    write_metadata(
        output,
        kernel_version,
        kernel_name,
        toolchain,
        package_name,
        variant,
        name,
        out_dir,
        release_repo,
        release_branch,
        kernel_commit,
    )


@tg_app.command("msg")
def tg_msg() -> None:
    send_message(stdin_text())


@tg_app.command("doc")
def tg_doc(file: Path) -> None:
    send_document(file, stdin_text())


@tg_app.command("gallery")
def tg_gallery(files: list[Path]) -> None:
    send_document_gallery(files, stdin_text())


@util_app.command("escape-md-v2")
def util_escape_md_v2(text: Annotated[str, typer.Argument()]) -> None:
    typer.echo(escape_md_v2(text), nl=False)


if __name__ == "__main__":
    app()
