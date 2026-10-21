import os
from pathlib import Path

import requests
from pydantic import ValidationError

from .common import die, env, escape_md_v2
from .models import TelegramDocumentRequest, TelegramMessageRequest, TelegramResponse


def _request(method: str, payload: dict[str, object], files=None) -> None:
    try:
        response = requests.post(
            f"https://api.telegram.org/bot{env('TG_BOT_TOKEN')}/{method}",
            data=payload,
            files=files,
            timeout=180 if files else 30,
        )
        response.raise_for_status()
    except requests.RequestException as error:
        status = (
            error.response.status_code if error.response is not None else "unavailable"
        )
        die(f"{method} failed: {type(error).__name__}, HTTP status {status}")
    try:
        result = TelegramResponse.model_validate_json(response.text)
    except ValidationError:
        die(f"{method} returned invalid JSON")
    if not result.ok:
        description = (result.description or "Unknown error").replace(
            env("TG_BOT_TOKEN"), "[redacted]"
        )
        die(f"{method} failed: {description}")


def send_message(text: str) -> None:
    payload = TelegramMessageRequest(chat_id=env("TG_CHAT_ID"), text=text)
    _request("sendMessage", payload.model_dump(mode="json"))


def send_document(file_path: Path, caption: str) -> None:
    payload = TelegramDocumentRequest(chat_id=env("TG_CHAT_ID"), caption=caption)
    with file_path.open("rb") as handle:
        _request(
            "sendDocument",
            payload.model_dump(mode="json"),
            {"document": (file_path.name, handle)},
        )


def notify(stage: str, seconds: int = 0, message: str = "") -> None:
    if os.environ.get("TG_NOTIFY") != "true":
        return
    heading = {
        "start": "Build started",
        "success": "Build completed",
        "error": "Build failed",
    }[stage]
    title = escape_md_v2(f"{env('KERNEL_NAME')} {heading}")
    lines = [f"*{title}*"]
    for label, value in (
        ("Target", env("TARGET_NAME")),
        ("Preset", env("PRESET")),
        ("Stock config", env("STOCK_CONFIG")),
    ):
        lines.append(f"*{label}:* {escape_md_v2(value)}")
    if stage == "success":
        for label, value in (
            ("Time", f"{seconds // 60}m {seconds % 60}s"),
            ("Kernel", env("KERNEL_VERSION")),
            ("Commit", env("KERNEL_COMMIT")),
            ("Compiler", env("COMPILER_STRING")),
        ):
            lines.append(f"*{label}:* {escape_md_v2(value)}")
    if os.environ.get("GITHUB_RUN_ID"):
        url = (
            f"{env('GITHUB_SERVER_URL')}/{env('GITHUB_REPOSITORY')}"
            f"/actions/runs/{env('GITHUB_RUN_ID')}"
        )
        lines.append(escape_md_v2(url))
    if message:
        redacted_message = message.replace(
            os.environ.get("TG_BOT_TOKEN", "\0"), "[redacted]"
        )
        lines.append(escape_md_v2(redacted_message))
    caption = "\n".join(lines)
    if stage == "success":
        send_document(
            Path(env("OUT_DIR")) / f"{env('PACKAGE_NAME')}-AnyKernel3.zip", caption
        )
    elif stage == "error" and Path(os.environ.get("LOGFILE", "")).is_file():
        send_document(Path(env("LOGFILE")), caption)
    else:
        send_message(caption)
