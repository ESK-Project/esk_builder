import html
import json
import os
from contextlib import ExitStack
from pathlib import Path
from typing import Any

import requests

from .common import env

STAGES = (
    ("sources", "Sources"),
    ("toolchain", "Toolchain"),
    ("configure", "Kernel configuration"),
    ("compile", "Compiling kernel"),
    ("modules", "Modules"),
    ("package", "Packaging"),
)


class TelegramError(Exception):
    pass


def request(
    method: str, data: dict[str, Any], files: dict[str, Path] | None = None
) -> Any:
    token = env("TG_BOT_TOKEN")
    try:
        with ExitStack() as stack:
            uploads = {
                name: (path.name, stack.enter_context(path.open("rb")))
                for name, path in (files or {}).items()
            }
            response = requests.post(
                f"https://api.telegram.org/bot{token}/{method}",
                data=data,
                files=uploads or None,
                timeout=180 if uploads else 30,
            )
        payload = response.json()
        if not response.ok or not payload.get("ok"):
            description = str(payload.get("description", "request failed"))
            raise TelegramError(description.replace(token, "[redacted]"))
        return payload["result"]
    except (requests.RequestException, ValueError, OSError, KeyError) as error:
        raise TelegramError(f"{method} failed: {type(error).__name__}") from None


def send_message(text: str) -> None:
    request(
        "sendMessage",
        {"chat_id": env("TG_CHAT_ID"), "text": text, "parse_mode": "MarkdownV2"},
    )


def send_document(file_path: Path, caption: str) -> None:
    request(
        "sendDocument",
        {"chat_id": env("TG_CHAT_ID"), "caption": caption, "parse_mode": "MarkdownV2"},
        {"document": file_path},
    )


def format_time(seconds: int) -> str:
    if seconds < 60:
        return f"{seconds}s"
    return f"{seconds // 60}m {seconds % 60:02d}s"


def notify(stage: str, seconds: int = 0, message: str = "") -> None:
    if os.environ.get("TG_NOTIFY") != "true":
        return

    token = env("TG_BOT_TOKEN")
    chat_id = env("TG_CHAT_ID")
    out = Path(env("OUT_DIR"))
    state_file = out / ".telegram-message-id"
    failed = stage == "error"
    done = stage == "success"
    status = "✕ Failed" if failed else "✓ Passed" if done else "● Running"
    target = html.escape(env("TARGET_NAME"))
    preset = html.escape(env("PRESET"))
    debug = " · debug" if os.environ.get("DEBUG") == "true" else ""
    lines = [
        f"<h3>ESK Build — {status}</h3>",
        f"<p><b>Device:</b> <code>{target}</code><br><b>Variant:</b> <code>{preset}</code>{debug}",
    ]
    commit_url = ""
    if version := os.environ.get("KERNEL_VERSION"):
        lines.append(f"<br><b>Kernel:</b> <code>{html.escape(version)}</code>")
    if commit := os.environ.get("KERNEL_COMMIT"):
        short_commit = html.escape(commit[:12])
        if kernel_url := os.environ.get("KERNEL_URL"):
            commit_url = (
                f"{kernel_url.rstrip('/').removesuffix('.git')}/commit/{commit}"
            )
            short_commit = (
                f'<a href="{html.escape(commit_url, quote=True)}">{short_commit}</a>'
            )
        else:
            short_commit = f"<code>{short_commit}</code>"
        lines.append(f"<br><b>Commit:</b> {short_commit}")
    current = os.environ.get("BUILD_PROGRESS", "sources") if failed else stage
    stage_index = next((i for i, (key, _) in enumerate(STAGES) if key == current), 0)
    timings = {}
    for item in os.environ.get("BUILD_TIMINGS", "").split(","):
        key, separator, duration = item.partition(":")
        if separator and duration.isdecimal():
            timings[key] = timings.get(key, 0) + int(duration)
    started = os.environ.get("BUILD_PROGRESS_STARTED", "")
    if (failed or not done) and started.isdecimal():
        timings[current] = timings.get(current, 0) + max(0, seconds - int(started))
    if done:
        lines.append(f"<br><b>Duration:</b> <code>{format_time(seconds)}</code></p>")
    elif failed:
        lines.append(
            f"<br><b>Failed at:</b> {html.escape(STAGES[stage_index][1])}<br><b>Elapsed:</b> <code>{format_time(seconds)}</code></p>"
        )
    else:
        lines.append("</p><p><b>Progress</b><br>")
        for i, (key, label) in enumerate(STAGES):
            label = html.escape(label)
            duration = (
                f" · <code>{format_time(timings[key])}</code>" if key in timings else ""
            )
            if i < stage_index:
                lines.append(f"✓ {label}{duration}<br>")
            elif i == stage_index:
                lines.append(f"◉ <b>{label}</b>{duration}<br>")
            else:
                lines.append(f"○ {label}<br>")
        lines.append(f"</p><p><b>Elapsed:</b> <code>{format_time(seconds)}</code></p>")

    details = []
    for label, name in (
        ("Kernel ref", "KERNEL_REF"),
        ("Compiler", "COMPILER_STRING"),
        ("Builder commit", "BUILDER_COMMIT"),
        ("KernelSU commit", "KSU_COMMIT"),
        ("SuSFS commit", "SUSFS_COMMIT"),
    ):
        if value := os.environ.get(name):
            details.append(f"<b>{label}:</b> <code>{html.escape(value.strip())}</code>")
    if details:
        lines.append(
            "<details><summary>Build details</summary><p>"
            + "<br>".join(details)
            + "</p></details>"
        )
    if (done or failed) and timings:
        entries = [
            f"{html.escape(label)} · <code>{format_time(timings[key])}</code>"
            for key, label in STAGES
            if key in timings
        ]
        lines.append(
            "<details><summary>Stage timings</summary><p>"
            + "<br>".join(entries)
            + "</p></details>"
        )
    if failed and message:
        detail = html.escape(message.replace(token, "[redacted]")[:4000])
        lines.append(
            f"<details><summary>Error details</summary><pre>{detail}</pre></details>"
        )
    stats = out / "ccache-stats.txt"
    if (done or failed) and stats.is_file():
        lines.append(
            f"<details><summary>Ccache stats</summary><pre>{html.escape(stats.read_text(errors='replace'))}</pre></details>"
        )

    files: dict[str, Path] = {}
    media = []
    if done:
        files["kernel"] = out / f"{env('PACKAGE_NAME')}-AnyKernel3.zip"
        lines.append('<tg-document src="tg://document?id=kernel"></tg-document>')
    if done or failed:
        build_files = []
        for name, path in (
            ("metadata", out / "build.json"),
            ("log", out / "build.log"),
        ):
            if path.is_file():
                files[name] = path
                build_files.append(
                    f'<tg-document src="tg://document?id={name}"></tg-document>'
                )
        if build_files:
            lines.append(
                "<details><summary>Build files</summary>"
                + "".join(build_files)
                + "</details>"
            )
    for name in files:
        media.append(
            {"id": name, "media": {"type": "document", "media": f"attach://{name}"}}
        )

    buttons = []
    if os.environ.get("GITHUB_RUN_ID"):
        workflow = f"{env('GITHUB_SERVER_URL')}/{env('GITHUB_REPOSITORY')}/actions/runs/{env('GITHUB_RUN_ID')}"
        buttons.append(
            f'<tg-button type="url" url="{html.escape(workflow, quote=True)}">View workflow</tg-button>'
        )
    if commit_url:
        buttons.append(
            f'<tg-button type="url" url="{html.escape(commit_url, quote=True)}">View commit</tg-button>'
        )
    if buttons:
        lines.append("<tg-button-row>" + "".join(buttons) + "</tg-button-row>")

    message_id = state_file.read_text().strip() if state_file.is_file() else ""

    def publish(content: dict[str, Any], uploads: dict[str, Path]) -> None:
        data = {"chat_id": chat_id, "rich_message": json.dumps(content)}
        if message_id:
            try:
                request("editMessageText", data | {"message_id": message_id}, uploads)
                return
            except TelegramError as error:
                if "message is not modified" in str(error).lower():
                    return
                if "message to edit not found" not in str(error).lower():
                    raise
        sent = request("sendRichMessage", data, uploads)
        state_file.write_text(str(sent["message_id"]))

    rich_message: dict[str, Any] = {"html": "".join(lines)}
    if media:
        rich_message["media"] = media
    try:
        publish(rich_message, files)
    except TelegramError:
        if not files:
            raise
        fallback = "".join(line for line in lines if "<tg-document" not in line)
        fallback += "<p>Files could not be attached. See workflow artifacts.</p>"
        publish({"html": fallback}, {})
