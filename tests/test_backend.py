import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from esk.config import resolve_settings

ROOT = Path(__file__).resolve().parents[1]


def shell(script, **environment):
    env = os.environ | resolve_settings(ROOT).environment() | {k: str(v) for k, v in environment.items()}
    return subprocess.run(["bash", "-Eeuo", "pipefail", "-c", script], env=env, text=True, capture_output=True)


class BackendTests(unittest.TestCase):
    def test_source_helper_failure_notifies_once_and_preserves_status(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "notifications"
            result = shell('''source "$WORKSPACE/build.sh"
STEP=0
py_cli() {
    if [[ $1 == source ]]; then return 17; fi
    printf '%s\\n' "$*" >> "$MARKER"
}
trap 'error "Source sync failed"' ERR
fetch_sources
''', MARKER=marker, TG_NOTIFY="true")
            self.assertEqual(result.returncode, 17, result.stderr)
            self.assertEqual(marker.read_text().splitlines(), ["tg notify error"])

    def test_fatal_reaches_error_notification(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "notification"
            result = shell('''source "$WORKSPACE/scripts/common.sh"
source "$WORKSPACE/scripts/notify.sh"
py_cli() { printf '%s\\n' "$*" > "$MARKER"; }
trap 'error "Build failed at line $LINENO: $BASH_COMMAND"' ERR
fatal "Fixture failure"
''', MARKER=marker, TG_NOTIFY="true")
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("Fixture failure", result.stderr)
            self.assertTrue(marker.is_file(), result.stderr)
            self.assertEqual(marker.read_text().strip(), "tg notify error")

    def test_flatten_uses_current_release_and_rejects_collisions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for version, value in (("current", "new"), ("stale", "old")):
                folder = root / "installed/lib/modules" / version / "kernel"
                folder.mkdir(parents=True)
                (folder / "driver.ko").write_text(value)
            flat = root / "flat"
            flat.mkdir()
            script = '''source "$WORKSPACE/scripts/common.sh"
source "$WORKSPACE/scripts/modules.sh"
STEP=0
llvm-strip() { :; }
flatten
'''
            env = dict(INSTALLED_MODULES=root / "installed", MOD_FLAT=flat, KERNEL_RELEASE="current")
            result = shell(script, **env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((flat / "driver.ko").read_text(), "new")
            (flat / "driver.ko").unlink()
            duplicate = root / "installed/lib/modules/current/other"
            duplicate.mkdir()
            (duplicate / "driver.ko").write_text("collision")
            result = shell(script, **env)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Duplicate module", result.stderr)

    def test_main_is_ordered_and_stops_on_error(self):
        script = '''source "$WORKSPACE/build.sh"
validate_deps() { echo deps; }
validate_env() { echo env; }
prepare_output() { echo output; }
init_logging() { echo logging; }
init_build() { echo init; }
send_start_msg() { echo start; }
prepare_dirs() { echo dirs; }
fetch_sources() { echo fetch; }
setup_toolchain() { echo tools; }
setup_ld_preload() { echo preload; }
setup_ccache() { echo cache; }
prepare_build() { echo patch; }
build_kernel() { echo compile; return 23; }
build_module() { echo modules; }
error() { echo stopped >&2; exit 23; }
main
'''
        result = shell(script)
        self.assertEqual(result.returncode, 23, result.stderr)
        sequence = result.stdout.splitlines()
        self.assertLess(sequence.index("deps"), sequence.index("output"))
        self.assertLess(sequence.index("output"), sequence.index("logging"))
        self.assertLess(sequence.index("fetch"), sequence.index("tools"))
        self.assertLess(sequence.index("patch"), sequence.index("compile"))
        self.assertNotIn("modules", sequence)


if __name__ == "__main__":
    unittest.main()
