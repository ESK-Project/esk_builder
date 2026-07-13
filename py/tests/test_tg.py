import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import requests

from tools.tg import send_document_gallery


class GalleryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.files = []
        for index in range(11):
            path = Path(self.directory.name) / f"artifact-{index}.zip"
            path.write_bytes(b"artifact")
            self.files.append(path)
        environment = patch.dict(os.environ, TG_BOT_TOKEN="test-token", TG_CHAT_ID="test-chat")
        environment.start()
        self.addCleanup(environment.stop)

    def test_rejects_counts_outside_two_to_ten_before_opening_files(self):
        response = requests.Response()
        response.status_code = 200
        response._content = b'{"ok":true,"result":[]}'
        for count in (0, 1, 11):
            with self.subTest(count=count):
                with (
                    patch("pathlib.Path.open") as open_file,
                    patch("requests.post", return_value=response) as post,
                ):
                    with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                        send_document_gallery(self.files[:count], "caption")
                    open_file.assert_not_called()
                    post.assert_not_called()

    def test_accepts_both_album_boundaries_and_closes_handles(self):
        for count in (2, 10):
            handles = []

            def upload(url, **kwargs):
                self.assertTrue(url.endswith("/sendMediaGroup"))
                self.assertEqual(kwargs["data"]["chat_id"], "test-chat")
                media = json.loads(kwargs["data"]["media"])
                self.assertEqual(len(media), count)
                self.assertEqual(media[0]["caption"], "caption")
                self.assertEqual(media[0]["parse_mode"], "MarkdownV2")
                for index, item in enumerate(media):
                    self.assertEqual(item["media"], f"attach://file{index}")
                    if index:
                        self.assertNotIn("caption", item)
                        self.assertNotIn("parse_mode", item)
                    name, handle = kwargs["files"][f"file{index}"]
                    self.assertEqual(name, self.files[index].name)
                    self.assertEqual(handle.read(), b"artifact")
                    handles.append(handle)
                response = requests.Response()
                response.status_code = 200
                response._content = b'{"ok":true,"result":[]}'
                return response

            with self.subTest(count=count), patch("requests.post", side_effect=upload) as post:
                send_document_gallery(self.files[:count], "caption")
                post.assert_called_once()
            self.assertTrue(all(handle.closed for handle in handles))

    def test_closes_handles_on_request_failure(self):
        handles = []

        def upload(url, **kwargs):
            handles.extend(handle for _, handle in kwargs["files"].values())
            raise requests.ConnectionError("test failure")

        with patch("requests.post", side_effect=upload):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                send_document_gallery(self.files[:2], "caption")
        self.assertEqual(len(handles), 2)
        self.assertTrue(all(handle.closed for handle in handles))


if __name__ == "__main__":
    unittest.main()
