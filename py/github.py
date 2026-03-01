#!/usr/bin/env python3
#
# Handle GitHub metadata json generation
#

import json
import sys
from pathlib import Path
from typing import NoReturn


def die(reason: str) -> NoReturn:
    print(f"[ERROR] {reason}", file=sys.stderr)
    sys.exit(1)


def usage() -> NoReturn:
    die(
        "Usage: github.py <output> <kernel_version> <kernel_name> <toolchain> "
        "<package_name> <variant> <name> <out_dir> <release_repo> <release_branch> "
        "<anykernel_zip> <boot_image>"
    )


def main() -> None:
    if len(sys.argv) != 13:
        usage()

    (
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
        anykernel_zip,
        boot_image,
    ) = sys.argv[1:]

    metadata = {
        "kernel_version": kernel_version,
        "kernel_name": kernel_name,
        "toolchain": toolchain,
        "package_name": package_name,
        "variant": variant,
        "name": name,
        "out_dir": out_dir,
        "release_repo": release_repo,
        "release_branch": release_branch,
        "anykernel_zip": anykernel_zip,
        "boot_image": boot_image,
    }

    out_file = Path(output)
    json_text = json.dumps(metadata, indent=2, sort_keys=True)
    text = json_text + "\n"
    with open(out_file, "w") as f:
        f.write(text)

if __name__ == "__main__":
    main()
