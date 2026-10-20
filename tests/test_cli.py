import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from typer.testing import CliRunner

from esk.cli import app

ROOT = Path(__file__).resolve().parents[1]


class CliTests(unittest.TestCase):
    def test_managed_symlink_cannot_delete_target_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("builder.toml", "presets.toml"):
                shutil.copy(ROOT / name, root / name)
            shutil.copytree(ROOT / "targets", root / "targets")
            (root / "work").symlink_to(root / "targets", target_is_directory=True)
            with patch("esk.cli.WORKSPACE", root), patch("subprocess.run") as run:
                for arguments in (["clean", "xaga"], ["build", "xaga"]):
                    result = CliRunner().invoke(app, arguments)
                    self.assertNotEqual(result.exit_code, 0, result.output)
                    self.assertIn("symlink", result.output.lower())
                    self.assertTrue((root / "targets/xaga/modules.load").is_file())
                run.assert_not_called()

    def test_dry_run_has_no_side_effects(self):
        with patch("subprocess.run") as run:
            result = CliRunner().invoke(app, ["build", "xaga", "--preset", "ksu-susfs", "--dry-run"])
        self.assertEqual(result.exit_code, 0, result.output)
        self.assertIn("ksu-susfs", result.output)
        self.assertNotIn("TG_BOT_TOKEN", result.output)
        run.assert_not_called()

    def test_literal_ref_and_backend_exit(self):
        with patch("subprocess.run", return_value=subprocess.CompletedProcess([], 17)) as run:
            result = CliRunner().invoke(app, ["build", "xaga", "--no-notify", "--kernel-ref", "$(touch stolen) with space"])
        self.assertEqual(result.exit_code, 17, result.output)
        self.assertEqual(run.call_args.kwargs["env"]["KERNEL_REF"], "$(touch stolen) with space")
        self.assertEqual(run.call_args.kwargs["env"]["TG_NOTIFY"], "false")
        self.assertEqual(run.call_args.args[0], ["bash", str(ROOT / "build.sh")])

    def test_clean_only_selected_managed_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("builder.toml", "presets.toml"):
                shutil.copy(ROOT / name, root / name)
            shutil.copytree(ROOT / "targets", root / "targets")
            for name in ("work/xaga", "staging/xaga", "out/xaga/vnl", "sources/xaga", "tools", ".ccache"):
                (root / name).mkdir(parents=True)
            with patch("esk.cli.WORKSPACE", root):
                result = CliRunner().invoke(app, ["clean", "xaga"])
                self.assertEqual(result.exit_code, 0, result.output)
                for name in ("work/xaga", "staging/xaga", "out/xaga"):
                    self.assertFalse((root / name).exists())
                for name in ("tools", ".ccache", "sources/xaga", "targets/xaga/modules.load"):
                    self.assertTrue((root / name).exists())
                result = CliRunner().invoke(app, ["clean", "xaga", "--sources"])
                self.assertEqual(result.exit_code, 0, result.output)
                self.assertFalse((root / "sources/xaga").exists())
                self.assertNotEqual(CliRunner().invoke(app, ["clean", "../tools"]).exit_code, 0)


if __name__ == "__main__":
    unittest.main()
