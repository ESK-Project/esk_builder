import shutil
import tempfile
import unittest
from pathlib import Path

from esk.config import resolve_settings

ROOT = Path(__file__).resolve().parents[1]


class ConfigTests(unittest.TestCase):
    def test_presets_and_paths(self):
        for preset, flags in {"vnl": (False, False), "ksu": (True, False), "ksu-susfs": (True, True)}.items():
            settings = resolve_settings(ROOT, preset=preset)
            self.assertEqual((settings.ksu, settings.susfs), flags)
            self.assertEqual(settings.target, "xaga")
            self.assertFalse(settings.stock_config)
            self.assertEqual(settings.environment()["OUT_DIR"], str(ROOT / "out/xaga" / preset))

    def test_overrides_and_explicit_false(self):
        settings = resolve_settings(ROOT, overrides={"notify": False, "stock_config": "true", "jobs": 8})
        self.assertFalse(settings.notify)
        self.assertTrue(settings.stock_config)
        self.assertEqual(settings.jobs, 8)
        self.assertEqual(settings.environment()["TG_NOTIFY"], "false")

    def test_invalid_inputs_do_not_touch_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("builder.toml", "presets.toml"):
                shutil.copy(ROOT / name, root / name)
            shutil.copytree(ROOT / "targets", root / "targets")
            output = root / "out/xaga/vnl"
            output.mkdir(parents=True)
            sentinel = output / "keep"
            sentinel.write_text("keep")
            for kwargs in ({"target": "../xaga"}, {"target": "generic"}, {"preset": "missing"},
                           {"overrides": {"jobs": 0}}, {"overrides": {"stock_config": "perhaps"}},
                           {"overrides": {"kernel_ref": "bad\nref"}}, {"overrides": {"ksu": True}}):
                with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                    resolve_settings(root, **kwargs)
                self.assertEqual(sentinel.read_text(), "keep")
            (root / "targets/xaga/modules.load").unlink()
            with self.assertRaises(ValueError):
                resolve_settings(root)
            (root / "builder.toml").write_text("bad = [")
            with self.assertRaises(ValueError):
                resolve_settings(root)


if __name__ == "__main__":
    unittest.main()
