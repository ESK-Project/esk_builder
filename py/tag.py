#!/usr/bin/env python3
from typing import Any, NoReturn
import json
import subprocess
import sys


def die(reason: str) -> NoReturn:
    print(f"[ERROR] {reason}", file=sys.stderr)
    sys.exit(1)


def usage() -> None:
    die("Usage: tag.py <owner/repo>")


def parse(tag: str) -> tuple[int, int]:
    tag = tag.strip()
    if tag[:1] in ("v", "V"):
        tag = tag[1:]
    major, minor = tag.split(".")
    return int(major), int(minor)


def main() -> None:
    if len(sys.argv) != 2:
        usage()

    repo: str = sys.argv[1].strip()
    if not repo:
        usage()

    try:
        raw: str = subprocess.check_output(
            ["gh", "release", "list", "--repo", repo, "--limit", "100", "--json", "tagName"],
            text=True, stderr=subprocess.STDOUT
        )
    except subprocess.CalledProcessError as e:
        die(f"gh failed: {e.output.strip()}")

    data: list[dict[str, Any]] = json.loads(raw)
    tags: list[str] = [x["tagName"] for x in data if x.get("tagName")]

    next_tag: str

    if not tags:
        next_tag = "v1.0"
        sys.stdout.write(next_tag)
        return

    latest: str = max(tags, key=parse)
    major, minor = parse(latest)

    if minor >= 9:
        major += 1
        minor = 0
    else:
        minor += 1

    next_tag = f"v{major}.{minor}"
    sys.stdout.write(next_tag)


if __name__ == "__main__":
    main()
