import json
import os
import re
import sys
from pathlib import Path
from typing import NoReturn

import requests
from pydantic import BaseModel


def die(reason: str) -> NoReturn:
    print(f"[ERROR] {reason}", file=sys.stderr)
    sys.exit(1)


def env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        die(f"Cannot get environment variable: {name}")
    return value


def stdin_text() -> str:
    text = sys.stdin.read().rstrip()
    if not text:
        die("stdin is empty")
    return text


def escape_md_v2(text: str) -> str:
    return re.sub(r"([\\_*[\]()~`>#+\-=|{}.!])", r"\\\1", text)


def write_json_file(path: Path, payload: BaseModel) -> None:
    text = json.dumps(payload.model_dump(mode="json"), indent=2, sort_keys=True) + "\n"
    path.write_text(text)


def get_json_text(url: str, token_env: str = "GH_TOKEN") -> str:
    headers: dict[str, str] = {
        "Accept": "application/vnd.github+json",
    }
    token = os.environ.get(token_env)
    if token:
        headers["Authorization"] = f"Bearer {token}"

    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
    except requests.RequestException as e:
        die(f"GET {url} failed: {e}")

    return response.text
