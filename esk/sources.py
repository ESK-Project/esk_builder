"""Synchronize disposable source checkouts and return their actual revision."""

import shutil
import subprocess
from pathlib import Path


def sync_source(url: str, ref: str, destination: Path) -> str:
    destination = destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)

    def git(*args: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(destination), *args], text=True,
        ).strip()

    if (destination / ".git").is_dir():
        if git("remote", "get-url", "origin") != url:
            raise ValueError(
                f"Source origin mismatch at {destination}. Use --reset-sources."
            )
    else:
        git("init", "-q")
        git("remote", "add", "origin", url)

    git("fetch", "-q", "--depth=1", "--no-tags", "--", "origin", ref)

    # KernelSU's nested Git checkout survives an ordinary git clean.
    kernelsu = destination / "KernelSU"
    if kernelsu.is_symlink() or kernelsu.is_file():
        kernelsu.unlink()
    elif kernelsu.exists():
        shutil.rmtree(kernelsu)

    git("clean", "-fdx", "-q")
    git("reset", "-q", "--hard", "FETCH_HEAD")
    return git("rev-parse", "HEAD")
