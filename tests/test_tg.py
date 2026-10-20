import contextlib
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import requests

from esk.tg import notify, send_document, send_message


class TelegramTests(unittest.TestCase):
    def test_disabled_notification_never_reads_credentials(self):
        with patch.dict(os.environ, {"TG_NOTIFY": "false"}, clear=True), patch("requests.post") as post:
            notify("start")
        post.assert_not_called()

    def test_http_failure_does_not_log_token(self):
        response = requests.Response()
        response.status_code = 401
        response.url = "https://api.telegram.org/botSYNTHETIC_SECRET/sendMessage"
        stderr = io.StringIO()
        with patch.dict(os.environ, TG_BOT_TOKEN="SYNTHETIC_SECRET", TG_CHAT_ID="fixture"):
            with patch("requests.post", return_value=response), contextlib.redirect_stderr(stderr):
                with self.assertRaises(SystemExit):
                    send_message("test")
        self.assertNotIn("SYNTHETIC_SECRET", stderr.getvalue())
        self.assertIn("401", stderr.getvalue())

    def test_document_upload_closes_handle(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "package.zip"
            path.write_bytes(b"archive")
            response = requests.Response()
            response.status_code = 200
            response._content = b'{"ok":true}'
            handles = []

            def upload(url, **kwargs):
                handle = kwargs["files"]["document"][1]
                self.assertEqual(handle.read(), b"archive")
                handles.append(handle)
                return response

            with patch.dict(os.environ, TG_BOT_TOKEN="synthetic", TG_CHAT_ID="fixture"):
                with patch("requests.post", side_effect=upload):
                    send_document(path, "caption")
            self.assertTrue(handles[0].closed)


if __name__ == "__main__":
    unittest.main()
