import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from esk.meta import write_metadata


class MetadataTests(unittest.TestCase):
    def test_artifacts_and_actual_feature_revisions(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "package.zip").write_bytes(b"package")
            values = dict(OUT_DIR=str(output), TARGET_NAME="xaga", PRESET="ksu-susfs", KERNEL_NAME="ESK",
                          KERNEL_VERSION="5.10", KERNEL_COMMIT="kernel-sha", KERNEL_URL="https://example.invalid/kernel",
                          BUILDER_COMMIT="builder-sha", KSU_COMMIT="ksu-sha", SUSFS_COMMIT="susfs-sha",
                          COMPILER_STRING="clang", PACKAGE_NAME="package", VARIANT="KSU-SUSFS",
                          KSU="true", SUSFS="true", STOCK_CONFIG="false", COMPILE_SECONDS="12")
            with patch.dict(os.environ, values):
                write_metadata(output / "build.json")
            data = json.loads((output / "build.json").read_text())
            self.assertEqual(data["ksu_commit"], "ksu-sha")
            self.assertFalse(data["features"]["stock_config"])
            self.assertEqual(data["artifacts"]["package.zip"], hashlib.sha256(b"package").hexdigest())
            self.assertNotIn("release_repo", data)


if __name__ == "__main__":
    unittest.main()
