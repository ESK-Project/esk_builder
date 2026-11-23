import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

from esk.tg import notify


class TelegramProgressTest(unittest.TestCase):
    def test_progress_edits_one_message_and_sends_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            (out / "test-AnyKernel3.zip").write_bytes(b"zip")
            env = {
                "TG_NOTIFY": "true",
                "TG_BOT_TOKEN": "123:token",
                "TG_CHAT_ID": "123",
                "OUT_DIR": directory,
                "TARGET_NAME": "xaga",
                "PRESET": "ksu-susfs",
                "PACKAGE_NAME": "test",
                "KERNEL_COMMIT": "1234567890123456",
            }
            bot = AsyncMock()
            bot.__aenter__.return_value = bot
            bot.send_message.return_value.message_id = 42
            with (
                patch.dict(os.environ, env, clear=True),
                patch("esk.tg.Bot", return_value=bot),
            ):
                notify("sources", 1)
                notify("compile", 65)
                notify("success", 125)
            self.assertEqual((out / ".telegram-message-id").read_text(), "42")
            self.assertEqual(bot.send_message.await_count, 1)
            self.assertEqual(bot.edit_message_text.await_count, 2)
            self.assertEqual(bot.send_document.await_count, 1)
            self.assertIn("✓ Passed", bot.edit_message_text.call_args.args[0])

    def test_failure_shows_stage_and_redacts_token(self):
        with tempfile.TemporaryDirectory() as directory:
            env = {
                "TG_NOTIFY": "true",
                "TG_BOT_TOKEN": "123:token",
                "TG_CHAT_ID": "123",
                "OUT_DIR": directory,
                "TARGET_NAME": "xaga",
                "PRESET": "vnl",
                "BUILD_PROGRESS": "compile",
            }
            bot = AsyncMock()
            bot.__aenter__.return_value = bot
            bot.send_message.return_value.message_id = 42
            with (
                patch.dict(os.environ, env, clear=True),
                patch("esk.tg.Bot", return_value=bot),
            ):
                notify("error", 70, "failed 123:token")
            text = bot.send_message.call_args.args[1]
            self.assertIn("✕ Compiling kernel", text)
            self.assertIn("[redacted]", text)
            self.assertNotIn("123:token", text)


if __name__ == "__main__":
    unittest.main()
