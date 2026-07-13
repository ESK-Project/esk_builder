import json
from io import BufferedReader
from pathlib import Path

import requests
from pydantic import ValidationError

from .common import die, env
from .models import (
    TelegramDocumentRequest,
    TelegramMediaDocument,
    TelegramMediaGroupRequest,
    TelegramMessageRequest,
    TelegramResponse,
)


def tg_api_url(method: str) -> str:
    return f"https://api.telegram.org/bot{env('TG_BOT_TOKEN')}/{method}"


def send_message(text: str) -> None:
    payload = TelegramMessageRequest(chat_id=env("TG_CHAT_ID"), text=text)
    try:
        response = requests.post(
            tg_api_url("sendMessage"),
            json=payload.model_dump(mode="json"),
            timeout=30,
        )
        response.raise_for_status()
    except requests.RequestException as e:
        die(f"sendMessage request failed: {e}")

    try:
        data = TelegramResponse.model_validate_json(response.text)
    except ValidationError as e:
        die(f"sendMessage returned invalid JSON: {e}")
    if not data.ok:
        die(f"sendMessage failed: {data.description or 'Unknown error'}")


def send_document(file_path: Path, caption: str) -> None:
    if not file_path.exists():
        die(f"File not found: {file_path}")

    payload = TelegramDocumentRequest(chat_id=env("TG_CHAT_ID"), caption=caption)
    with file_path.open("rb") as handle:
        try:
            response = requests.post(
                tg_api_url("sendDocument"),
                data=payload.model_dump(mode="json"),
                files={"document": (file_path.name, handle)},
                timeout=180,
            )
            response.raise_for_status()
        except requests.RequestException as e:
            die(f"sendDocument request failed: {e}")

    try:
        data = TelegramResponse.model_validate_json(response.text)
    except ValidationError as e:
        die(f"sendDocument returned invalid JSON: {e}")
    if not data.ok:
        die(f"sendDocument failed: {data.description or 'Unknown error'}")


def send_document_gallery(file_paths: list[Path], caption: str) -> None:
    if not file_paths:
        die("No files provided for document gallery upload")

    missing_files = [str(file_path) for file_path in file_paths if not file_path.exists()]
    if missing_files:
        die(f"File not found: {', '.join(missing_files)}")

    media = []
    files: dict[str, tuple[str, BufferedReader]] = {}
    handles: list[BufferedReader] = []
    try:
        for index, file_path in enumerate(file_paths):
            attachment_name = f"file{index}"
            media.append(
                TelegramMediaDocument(
                    media=f"attach://{attachment_name}",
                    caption=caption if index == 0 else None,
                    parse_mode="MarkdownV2" if index == 0 else None,
                )
            )

            handle = file_path.open("rb")
            handles.append(handle)
            files[attachment_name] = (file_path.name, handle)

        payload = TelegramMediaGroupRequest(chat_id=env("TG_CHAT_ID"), media=media)
        response = requests.post(
            tg_api_url("sendMediaGroup"),
            data={
                "chat_id": payload.chat_id,
                "media": json.dumps([item.model_dump(mode="json", exclude_none=True) for item in payload.media]),
            },
            files=files,
            timeout=180,
        )
        response.raise_for_status()
    except requests.RequestException as e:
        die(f"sendMediaGroup request failed: {e}")
    finally:
        for handle in handles:
            handle.close()

    try:
        data = TelegramResponse.model_validate_json(response.text)
    except ValidationError as e:
        die(f"sendMediaGroup returned invalid JSON: {e}")
    if not data.ok:
        die(f"sendMediaGroup failed: {data.description or 'Unknown error'}")
