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
            f"<b>ESK / Build</b> · {status}",
            "",
            f"<b>{target}</b> / <code>{preset}</code>{debug}",
        ]
        if version := os.environ.get("KERNEL_VERSION"):
            lines.append(f"Kernel <code>{html.escape(version)}</code>")
        if commit := os.environ.get("KERNEL_COMMIT"):
            lines.append(f"Commit <code>{html.escape(commit[:12])}</code>")
        if done and (compiler := os.environ.get("COMPILER_STRING")):
            lines.append(f"Compiler <code>{html.escape(compiler.strip())}</code>")
        lines.append("")
        current = os.environ.get("BUILD_PROGRESS", "sources") if failed else stage
        stage_index = next(
            (i for i, (key, _) in enumerate(STAGES) if key == current), 0
        )
        for i, (_, label) in enumerate(STAGES):
            marker = (
                "✓"
                if done or i < stage_index
                else "✕"
                if failed and i == stage_index
                else "●"
                if i == stage_index
                else "○"
            )
            lines.append(f"{marker} {html.escape(label)}")
        lines.extend(
            ["", f"<b>Elapsed:</b> <code>{seconds // 60:02d}:{seconds % 60:02d}</code>"]
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
