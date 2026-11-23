import asyncio
import html
import os
from pathlib import Path

from telegram import Bot, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.error import BadRequest, TelegramError

from .common import env

STAGES = (
    ("sources", "Sources"),
    ("toolchain", "Toolchain"),
    ("compile", "Compiling kernel"),
    ("modules", "Modules"),
    ("package", "Packaging"),
)


def send_message(text: str) -> None:
    async def send() -> None:
        async with Bot(env("TG_BOT_TOKEN")) as bot:
            await bot.send_message(env("TG_CHAT_ID"), text, parse_mode="MarkdownV2")

    asyncio.run(send())


def send_document(file_path: Path, caption: str) -> None:
    async def send() -> None:
        async with Bot(env("TG_BOT_TOKEN")) as bot:
            with file_path.open("rb") as document:
                await bot.send_document(
                    env("TG_CHAT_ID"),
                    document,
                    caption=caption,
                    parse_mode="MarkdownV2",
                    write_timeout=180,
                )

    asyncio.run(send())


def notify(stage: str, seconds: int = 0, message: str = "") -> None:
    if os.environ.get("TG_NOTIFY") != "true":
        return

    async def update() -> None:
        token = env("TG_BOT_TOKEN")
        chat_id = env("TG_CHAT_ID")
        state_file = Path(env("OUT_DIR")) / ".telegram-message-id"
        failed = stage == "error"
        done = stage == "success"
        status = "✕ Failed" if failed else "✓ Passed" if done else "● Running"
        target = html.escape(env("TARGET_NAME"))
        preset = html.escape(env("PRESET"))
        debug = " · debug" if os.environ.get("DEBUG") == "true" else ""
        lines = [
            f"<b>ESK Build · {status}</b>",
            "",
            f"<b>Device:</b> {target}",
            f"<b>Variant:</b> <code>{preset}</code>{debug}",
        ]
        if version := os.environ.get("KERNEL_VERSION"):
            lines.append(f"<b>Kernel:</b> <code>{html.escape(version)}</code>")
        if commit := os.environ.get("KERNEL_COMMIT"):
            short_commit = html.escape(commit[:12])
            if kernel_url := os.environ.get("KERNEL_URL"):
                url = html.escape(
                    f"{kernel_url.rstrip('/').removesuffix('.git')}/commit/{commit}",
                    quote=True,
                )
                short_commit = f'<a href="{url}"><code>{short_commit}</code></a>'
            else:
                short_commit = f"<code>{short_commit}</code>"
            lines.append(f"<b>Commit:</b> {short_commit}")
        if done and (compiler := os.environ.get("COMPILER_STRING")):
            lines.append(f"<b>Compiler:</b> {html.escape(compiler.strip())}")
        lines.append("")
        current = os.environ.get("BUILD_PROGRESS", "sources") if failed else stage
        stage_index = next(
            (i for i, (key, _) in enumerate(STAGES) if key == current), 0
        )
        if done:
            lines.extend(
                [
                    f"<b>Duration:</b> <code>{seconds // 60}m {seconds % 60:02d}s</code>",
                    "<b>Package:</b> AnyKernel3 ready",
                ]
            )
        elif failed:
            lines.extend(
                [
                    f"<b>Failed at:</b> {html.escape(STAGES[stage_index][1])}",
                    f"<b>Elapsed:</b> <code>{seconds // 60:02d}:{seconds % 60:02d}</code>",
                ]
            )
        else:
            lines.append("<b>Progress</b>")
            for i, (_, label) in enumerate(STAGES):
                label = html.escape(label)
                if i < stage_index:
                    lines.append(f"✓ {label}")
                elif i == stage_index:
                    lines.append(f"● <b>{label}</b>")
                else:
                    lines.append(f"○ {label}")
            lines.extend(
                [
                    "",
                    f"<b>Elapsed:</b> <code>{seconds // 60:02d}:{seconds % 60:02d}</code>",
                ]
            )
        if failed and message:
            detail = message.replace(token, "[redacted]")
            lines.extend(["", f"<code>{html.escape(detail[:500])}</code>"])
        markup = None
        if os.environ.get("GITHUB_RUN_ID"):
            url = f"{env('GITHUB_SERVER_URL')}/{env('GITHUB_REPOSITORY')}/actions/runs/{env('GITHUB_RUN_ID')}"
            markup = InlineKeyboardMarkup(
                [[InlineKeyboardButton("View workflow ↗", url=url)]]
            )
        text = "\n".join(lines)
        async with Bot(token) as bot:
            message_id = state_file.read_text().strip() if state_file.exists() else ""
            if message_id:
                try:
                    await bot.edit_message_text(
                        text,
                        chat_id=chat_id,
                        message_id=int(message_id),
                        parse_mode="HTML",
                        reply_markup=markup,
                    )
                except BadRequest as error:
                    if "message is not modified" not in str(error).lower():
                        sent = await bot.send_message(
                            chat_id, text, parse_mode="HTML", reply_markup=markup
                        )
                        state_file.write_text(str(sent.message_id))
                except TelegramError:
                    sent = await bot.send_message(
                        chat_id, text, parse_mode="HTML", reply_markup=markup
                    )
                    state_file.write_text(str(sent.message_id))
            else:
                sent = await bot.send_message(
                    chat_id, text, parse_mode="HTML", reply_markup=markup
                )
                state_file.write_text(str(sent.message_id))
            if done:
                path = Path(env("OUT_DIR")) / f"{env('PACKAGE_NAME')}-AnyKernel3.zip"
                with path.open("rb") as document:
                    await bot.send_document(chat_id, document, write_timeout=180)
            elif failed and (path := Path(os.environ.get("LOGFILE", ""))).is_file():
                with path.open("rb") as document:
                    await bot.send_document(chat_id, document, write_timeout=180)

    asyncio.run(update())
