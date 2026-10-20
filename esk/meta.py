import hashlib
import os
from pathlib import Path

from .common import env, write_json_file
from .models import MetadataPayload


def write_metadata(output: Path) -> None:
    directory = Path(env("OUT_DIR"))
    artifacts = {}
    for path in sorted(directory.iterdir()):
        if path.is_file() and (path.suffix == ".zip" or path.name.endswith(".tar.xz")):
            with path.open("rb") as handle:
                artifacts[path.name] = hashlib.file_digest(handle, "sha256").hexdigest()
    payload = MetadataPayload(
        target=env("TARGET_NAME"), preset=env("PRESET"), kernel_name=env("KERNEL_NAME"),
        kernel_version=env("KERNEL_VERSION"), kernel_commit=env("KERNEL_COMMIT"),
        kernel_url=env("KERNEL_URL"), builder_commit=env("BUILDER_COMMIT"),
        toolchain=env("COMPILER_STRING"), variant=env("VARIANT"), package_name=env("PACKAGE_NAME"),
        ksu_commit=os.environ.get("KSU_COMMIT") if env("KSU") == "true" else None,
        susfs_commit=os.environ.get("SUSFS_COMMIT") if env("SUSFS") == "true" else None,
        features={key: env(key.upper()) == "true" for key in ("ksu", "susfs", "stock_config")},
        compile_seconds=int(env("COMPILE_SECONDS")), artifacts=artifacts,
    )
    write_json_file(output, payload)
