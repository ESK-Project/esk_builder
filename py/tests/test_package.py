import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile


class NotificationTests(unittest.TestCase):
    def test_device_uploads_one_package_and_generic_uploads_an_album(self):
        workspace = Path(__file__).resolve().parents[2]
        script = r'''
set -Eeuo pipefail
source "$WORKSPACE/config.sh"
source "$WORKSPACE/build/utils.sh"
source "$WORKSPACE/ci/utils.sh"
source "$WORKSPACE/ci/package.sh"
OUT_DIR="$TEST_OUT"
TG_NOTIFY=true
KSU=false SUSFS=false LXC=false STOCK_CONFIG=false
BUILD_TAG=test KERNEL_VERSION=5.10 KERNEL_COMMIT=abcdef COMPILER_STRING=clang
py_cli() {
    if [[ $1 == util && $2 == escape-md-v2 ]]; then
        printf '%s' "$3"
        return
    fi
    printf '%s\n' "$@" > "$OUT_DIR/upload-args"
    cat > "$OUT_DIR/caption"
    if [[ $2 == gallery ]]; then
        cp "$4" "$OUT_DIR/captured-boot.zip"
    fi
}
telegram_notify 65 package
'''
        for target in ("device", "generic"):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as directory:
                output = Path(directory)
                ak3 = output / "package-AnyKernel3.zip"
                ak3.write_bytes(b"anykernel")
                if target == "generic":
                    for name in ("raw", "gz", "lz4"):
                        (output / f"package-boot-{name}.img").write_bytes(b"boot image")
                environment = dict(
                    os.environ,
                    WORKSPACE=str(workspace),
                    TEST_OUT=directory,
                    BUILD_TARGET=target,
                    GITHUB_ACTIONS="false",
                )
                subprocess.run(["bash", "-c", script], env=environment, check=True, capture_output=True)
                args = (output / "upload-args").read_text().splitlines()
                caption = (output / "caption").read_text()
                self.assertIn("1m 5s", caption)
                if target == "device":
                    self.assertEqual(args, ["tg", "doc", str(ak3)])
                    self.assertIn("*Target:* xaga", caption)
                    self.assertFalse((output / "captured-boot.zip").exists())
                else:
                    self.assertEqual(args, ["tg", "gallery", str(ak3), str(output / "package-boot.zip")])
                    self.assertIn("raw, gzip, and lz4 variants", caption)
                    with ZipFile(output / "captured-boot.zip") as archive:
                        self.assertEqual(
                            set(archive.namelist()),
                            {"package-boot-raw.img", "package-boot-gz.img", "package-boot-lz4.img"},
                        )
                self.assertFalse((output / "package-boot.zip").exists())
                self.assertEqual(ak3.read_bytes(), b"anykernel")


if __name__ == "__main__":
    unittest.main()
