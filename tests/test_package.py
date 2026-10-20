import os
import unittest
from pathlib import Path
from unittest.mock import patch

from esk.tg import notify


class PackageNotificationTests(unittest.TestCase):
    def test_success_uploads_one_package_and_escapes_caption(self):
        values = dict(TG_NOTIFY="true", KERNEL_NAME="ESK_Test", TARGET_NAME="xaga", PRESET="ksu-susfs",
                      PACKAGE_NAME="fixture", OUT_DIR="/tmp/example", KERNEL_COMMIT="abcdef",
                      KERNEL_VERSION="5.10", COMPILER_STRING="Clang (test)", KSU="true", SUSFS="true",
                      STOCK_CONFIG="false")
        with patch.dict(os.environ, values), patch("esk.tg.send_document") as upload:
            notify("success", seconds=65)
        self.assertEqual(upload.call_args.args[0], Path("/tmp/example/fixture-AnyKernel3.zip"))
        self.assertIn("ESK\\_Test", upload.call_args.args[1])
        self.assertIn("1m 5s", upload.call_args.args[1])
        self.assertIn("ksu\\-susfs", upload.call_args.args[1])


if __name__ == "__main__":
    unittest.main()
