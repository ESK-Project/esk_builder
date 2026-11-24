import html
import json
import os
import subprocess
from contextlib import ExitStack
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

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


def git_remote(path: Path) -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(path), "remote", "get-url", "origin"],
            capture_output=True,
            text=True,
            timeout=3,
            check=True,
        ).stdout.strip()
    except OSError, subprocess.SubprocessError:
        return ""


def repository_commit_url(repository: str, commit: str) -> str:
    if repository.startswith("git@") and ":" in repository:
        host, path = repository[4:].split(":", 1)
    else:
        try:
            parsed = urlsplit(repository)
            host, path = parsed.hostname or "", parsed.path.lstrip("/")
        except ValueError:
            return ""
    path = path.rstrip("/").removesuffix(".git")
    if host not in {"github.com", "gitlab.com"} or not path:
        return ""
    separator = "/-/commit/" if host == "gitlab.com" else "/commit/"
    return f"https://{host}/{path}{separator}{commit}"


def commit_link(commit: str, url: str) -> str:
    label = html.escape(commit[:12])
    return f'<a href="{html.escape(url, quote=True)}">{label}</a>' if url else label


def render_build_header(stage: str) -> tuple[list[str], str]:
    failed = stage == "error"
    done = stage == "success"
    status = "❌ Failed" if failed else "✅ Passed" if done else "⏳ Running"
    target = html.escape(env("TARGET_NAME"))
    preset = html.escape(env("PRESET"))
    debug = " · debug" if os.environ.get("DEBUG") == "true" else ""
    lines = [
        f"<p><b>ESK Build</b> — {status}</p>",
        f"<p><b>Device:</b> <code>{target}</code><br><b>Variant:</b> <code>{preset}</code>{debug}",
    ]
    commit_url = ""
    if version := os.environ.get("KERNEL_VERSION"):
        lines.append(f"<br><b>Kernel:</b> <code>{html.escape(version)}</code>")
    if commit := os.environ.get("KERNEL_COMMIT"):
        commit_url = repository_commit_url(os.environ.get("KERNEL_URL", ""), commit)
        short_commit = commit_link(commit, commit_url)
        lines.append(f"<br><b>Commit:</b> {short_commit}")
    return lines, commit_url


def stage_timings(stage: str, current: str, seconds: int) -> dict[str, int]:
    timings: dict[str, int] = {}
    for item in os.environ.get("BUILD_TIMINGS", "").split(","):
        key, separator, duration = item.partition(":")
        if separator and duration.isdecimal():
            timings[key] = timings.get(key, 0) + int(duration)
    started = os.environ.get("BUILD_PROGRESS_STARTED", "")
    if stage != "success" and started.isdecimal():
        timings[current] = timings.get(current, 0) + max(0, seconds - int(started))
    return timings


def render_progress(
    stage: str, current: str, seconds: int, timings: dict[str, int]
) -> list[str]:
    done = stage == "success"
    failed = stage == "error"
    stage_index = next((i for i, (key, _) in enumerate(STAGES) if key == current), 0)
    lines = []
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
                lines.append(f"› <b>{label}</b>{duration}<br>")
            else:
                lines.append(f"– {label}<br>")
        lines.append(f"</p><p><b>Elapsed:</b> <code>{format_time(seconds)}</code></p>")
    return lines


def render_build_details() -> str:
    details = []
    for label, name in (
        ("Kernel ref", "KERNEL_REF"),
        ("Compiler", "COMPILER_STRING"),
    ):
        if value := os.environ.get(name):
            details.append(f"<b>{label}:</b> <code>{html.escape(value.strip())}</code>")
    if value := os.environ.get("BUILDER_COMMIT"):
        url = repository_commit_url(git_remote(Path(env("WORKSPACE"))), value.strip())
        details.append(f"<b>Builder commit:</b> {commit_link(value.strip(), url)}")
    if value := os.environ.get("KSU_COMMIT"):
        repository = git_remote(Path(env("KERNEL")) / "KernelSU")
        url = repository_commit_url(repository, value.strip())
        details.append(f"<b>KernelSU commit:</b> {commit_link(value.strip(), url)}")
    if value := os.environ.get("SUSFS_COMMIT"):
        url = repository_commit_url(os.environ.get("SUSFS_URL", ""), value.strip())
        details.append(f"<b>SuSFS commit:</b> {commit_link(value.strip(), url)}")
    if not details:
        return ""
    return (
        "<details><summary>Build details</summary><p>"
        + "<br>".join(details)
        + "</p></details>"
    )


def render_build_diagnostics(
    out: Path, timings: dict[str, int], message: str, token: str
) -> list[str]:
    lines = []
    if timings:
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
    if message:
        detail = html.escape(message.replace(token, "[redacted]")[:4000])
        lines.append(
            f"<details><summary>Error details</summary><pre>{detail}</pre></details>"
        )
    stats = out / "ccache-stats.txt"
    if stats.is_file():
        lines.append(
            f"<details><summary>Ccache stats</summary><pre>{html.escape(stats.read_text(errors='replace'))}</pre></details>"
        )
    return lines


def build_attachments(out: Path, stage: str) -> dict[str, Path]:
    files: dict[str, Path] = {}
    if stage not in {"success", "error"}:
        return files
    if stage == "success":
        files["kernel"] = out / f"{env('PACKAGE_NAME')}-AnyKernel3.zip"
    for name, path in (("metadata", out / "build.json"), ("log", out / "build.log")):
        if path.is_file():
            files[name] = path
    return files


def render_document(name: str) -> str:
    return f'<tg-document src="tg://document?id={name}"></tg-document>'


def render_buttons(commit_url: str) -> str:
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
    if not buttons:
        return ""
    return "<tg-button-row>" + "".join(buttons) + "</tg-button-row>"


def publish_notification(
    state_file: Path, chat_id: str, content: dict[str, Any], files: dict[str, Path]
) -> None:
    message_id = state_file.read_text().strip() if state_file.is_file() else ""

    data = {"chat_id": chat_id, "rich_message": json.dumps(content)}
    if message_id:
        try:
            request("editMessageText", data | {"message_id": message_id}, files)
            return
        except TelegramError as error:
            if "message is not modified" in str(error).lower():
                return
            if "message to edit not found" not in str(error).lower():
                raise
    sent = request("sendRichMessage", data, files)
    state_file.write_text(str(sent["message_id"]))


def render_notification(
    stage: str, seconds: int, message: str, out: Path, token: str
) -> tuple[list[str], str]:
    current = os.environ.get("BUILD_PROGRESS", "sources") if stage == "error" else stage
    timings = stage_timings(stage, current, seconds)

    lines, commit_url = render_build_header(stage)
    lines.extend(render_progress(stage, current, seconds, timings))
    lines.append(render_build_details())

    if stage in {"success", "error"}:
        lines.extend(
            render_build_diagnostics(
                out, timings, message if stage == "error" else "", token
            )
        )
    return lines, render_buttons(commit_url)


def rich_message_payload(
    lines: list[str], buttons: str, files: dict[str, Path]
) -> dict[str, Any]:
    content = lines.copy()
    if "kernel" in files:
        content.insert(1, render_document("kernel"))
    build_files = [render_document(name) for name in files if name != "kernel"]
    if build_files:
        content.append(
            "<details><summary>Build files</summary>"
            + "".join(build_files)
            + "</details>"
        )

    rich_message: dict[str, Any] = {"html": "".join(content) + buttons}
    if files:
        rich_message["media"] = [
            {"id": name, "media": {"type": "document", "media": f"attach://{name}"}}
            for name in files
        ]
    return rich_message


def notify(stage: str, seconds: int = 0, message: str = "") -> None:
    if os.environ.get("TG_NOTIFY") != "true":
        return

    token = env("TG_BOT_TOKEN")
    chat_id = env("TG_CHAT_ID")
    out = Path(env("OUT_DIR"))
    state_file = out / ".telegram-message-id"
    lines, buttons = render_notification(stage, seconds, message, out, token)
    files = build_attachments(out, stage)
    payload = rich_message_payload(lines, buttons, files)
    try:
        publish_notification(state_file, chat_id, payload, files)
    except TelegramError:
        if not files:
            raise
        fallback = "".join(lines) + buttons
        fallback += "<p>Files could not be attached. See workflow artifacts.</p>"
        publish_notification(state_file, chat_id, {"html": fallback}, {})
