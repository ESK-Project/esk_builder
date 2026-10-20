import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_backend import shell


class CacheTests(unittest.TestCase):
    def test_real_compiler_identity_and_prefix_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            library = root / "preload.so"
            library.write_bytes(b"fixture only")
            result = shell('''source "$WORKSPACE/scripts/common.sh"
source "$WORKSPACE/scripts/toolchain.sh"
mkdir -p "$WRAPPER_DIR"
gen_wrapper
ccache() { :; }
MAKE_ARGS=()
setup_ccache
python3 -c 'import os,json; print(json.dumps({k:v for k,v in os.environ.items() if k.startswith("CCACHE_")}))'
''', WRAPPER_DIR=root / "wrappers", LIBFAKESTAT=library, LIBFAKETIME=library,
                           CLANG_BIN=root / "clang/bin", CCACHE_DIR=root / "cache", CCACHE_STATSLOG=root / "stats.log")
            self.assertEqual(result.returncode, 0, result.stderr)
            env = json.loads(result.stdout.splitlines()[-1])
            self.assertEqual(env["CCACHE_COMPILERCHECK"], "content")
            self.assertEqual(env["CCACHE_PREFIX"], "esk-compiler-env")
            self.assertEqual(env["CCACHE_PREFIX_CPP"], "esk-compiler-env")
            self.assertEqual(env["CCACHE_SLOPPINESS"], "")
            self.assertNotIn("CCACHE_NOHASHDIR", env)
            self.assertIn(str(library), env["CCACHE_EXTRAFILES"])
            self.assertIn(str(root / "wrappers/esk-compiler-env"), env["CCACHE_EXTRAFILES"])

    @unittest.skipUnless(shutil.which("ccache") and shutil.which("gcc"), "real ccache/gcc unavailable")
    def test_clean_output_warm_hit_and_changed_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root / "test.c", root / "test.o"
            source.write_text("int answer(void) { return 1; }\n")
            launcher, library = root / "launcher", root / "preload-policy"
            launcher.write_text('#!/bin/sh\nexec "$@"\n')
            launcher.chmod(0o755)
            library.write_text("library identity v1")
            environment = {k: v for k, v in os.environ.items() if not k.startswith("CCACHE_")}
            environment |= {
                "CCACHE_DIR": str(root / "cache"), "CCACHE_COMPILERCHECK": "content",
                "CCACHE_PREFIX": str(launcher), "CCACHE_PREFIX_CPP": str(launcher),
                "CCACHE_EXTRAFILES": os.pathsep.join(map(str, (launcher, library))),
            }
            command = ["ccache", "gcc", "-c", str(source), "-o", str(output)]
            subprocess.run(command, env=environment, check=True, capture_output=True)
            original = output.read_bytes()
            output.unlink()
            subprocess.run(command, env=environment, check=True, capture_output=True)
            stats = subprocess.check_output(["ccache", "--print-stats"], env=environment, text=True)
            counters = dict(line.split() for line in stats.splitlines())
            self.assertGreater(int(counters["direct_cache_hit"]) + int(counters["preprocessed_cache_hit"]), 0)
            self.assertEqual(output.read_bytes(), original)
            source.write_text("int answer(void) { return 2; }\n")
            subprocess.run(command, env=environment, check=True, capture_output=True)
            self.assertNotEqual(output.read_bytes(), original)
            for identity in (launcher, library):
                before = dict(line.split() for line in subprocess.check_output(
                    ["ccache", "--print-stats"], env=environment, text=True).splitlines())
                with identity.open("a") as handle:
                    handle.write("\n# identity changed\n")
                output.unlink()
                subprocess.run(command, env=environment, check=True, capture_output=True)
                after = dict(line.split() for line in subprocess.check_output(
                    ["ccache", "--print-stats"], env=environment, text=True).splitlines())
                self.assertEqual(int(after["cache_miss"]), int(before["cache_miss"]) + 1)


if __name__ == "__main__":
    unittest.main()
