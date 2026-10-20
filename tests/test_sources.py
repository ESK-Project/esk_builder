import subprocess
import tempfile
import unittest
from pathlib import Path

from typer.testing import CliRunner

from esk.cli import app


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.origin = self.root / "origin"
        self.checkout = self.root / "checkout"
        self.git("init", "-q", "-b", "main", str(self.origin))
        (self.origin / "tracked").write_text("first")
        self.commit("first")

    def git(self, *args):
        return subprocess.check_output(["git", *args], text=True).strip()

    def commit(self, message):
        self.git("-C", str(self.origin), "add", ".")
        self.git("-C", str(self.origin), "-c", "user.name=Test", "-c",
                 "user.email=test@example.invalid", "commit", "-qm", message)
        return self.git("-C", str(self.origin), "rev-parse", "HEAD")

    def sync(self, url=None, ref="main"):
        return CliRunner().invoke(app, ["source", "sync", str(url or self.origin), ref, str(self.checkout)])

    def test_checkout_update_and_nested_cleanup_return_exact_sha(self):
        result = self.sync()
        self.assertEqual(result.exit_code, 0, result.output)
        self.assertEqual(result.output.strip(), self.git("-C", str(self.origin), "rev-parse", "HEAD"))
        nested = self.checkout / "KernelSU"
        self.git("init", "-q", str(nested))
        (nested / "stale").write_text("old")
        (self.checkout / "untracked").write_text("old")
        (self.origin / "tracked").write_text("second")
        revision = self.commit("second")
        result = self.sync(ref=revision)
        self.assertEqual(result.exit_code, 0, result.output)
        self.assertEqual(result.output.strip(), revision)
        self.assertEqual((self.checkout / "tracked").read_text(), "second")
        self.assertFalse(nested.exists())
        self.assertFalse((self.checkout / "untracked").exists())

    def test_origin_mismatch_fails_before_cleanup(self):
        self.assertEqual(self.sync().exit_code, 0)
        sentinel = self.checkout / "untracked"
        sentinel.write_text("keep")
        result = self.sync(url=self.root / "wrong")
        self.assertNotEqual(result.exit_code, 0)
        self.assertIn("origin mismatch", result.output.lower())
        self.assertIn("--reset-sources", result.output)
        self.assertEqual(sentinel.read_text(), "keep")

    def test_fetch_failure_preserves_checkout_and_has_no_traceback(self):
        self.assertEqual(self.sync().exit_code, 0)
        sentinel = self.checkout / "untracked"
        sentinel.write_text("keep")
        result = self.sync(ref="missing-branch")
        self.assertNotEqual(result.exit_code, 0)
        self.assertEqual(sentinel.read_text(), "keep")
        self.assertEqual((self.checkout / "tracked").read_text(), "first")
        self.assertIn("Git source sync failed", result.output)
        self.assertNotIn("Traceback", result.output)


if __name__ == "__main__":
    unittest.main()
