import struct
import tempfile
import unittest
from pathlib import Path

from esk.ack_package import dt_image, module_order


class AckPackageTest(unittest.TestCase):
    def test_load_only_donor_modules_and_dependencies(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in (
                "updates/mtu3.ko",
                "updates/xhci-mtk-hcd-v2.ko",
                "kernel/provider.ko",
                "kernel/kunit-test.ko",
            ):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            (root / "modules.dep").write_text(
                "updates/mtu3.ko: kernel/provider.ko\nupdates/xhci-mtk-hcd-v2.ko:\nkernel/provider.ko:\nkernel/kunit-test.ko:\n"
            )
            (root / "modules.softdep").write_text(
                "softdep xhci_mtk_hcd_v2 pre: provider post: mtu3\n"
            )
            (root / "kernel/mtu3.ko").touch()
            order = module_order(root)
            self.assertEqual(
                set(order), {"provider.ko", "mtu3.ko", "xhci-mtk-hcd-v2.ko"}
            )
            self.assertLess(order.index("provider.ko"), order.index("mtu3.ko"))
            self.assertLess(order.index("xhci-mtk-hcd-v2.ko"), order.index("mtu3.ko"))
            self.assertLess(
                order.index("provider.ko"), order.index("xhci-mtk-hcd-v2.ko")
            )
            (root / "modules.softdep").write_text("softdep provider pre: mtu3\n")
            with self.assertRaises(ValueError):
                module_order(root)
            (root / "modules.dep").write_text(
                "updates/mtu3.ko: kernel/missing.ko\nupdates/xhci-mtk-hcd-v2.ko:\n"
            )
            with self.assertRaises(ValueError):
                module_order(root)

    def test_probe_dependencies_and_suffixed_softdeps(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            names = [
                "extcon-mtk-usb",
                "tcpc_mt6375",
                "tcpc_class",
                "mtu3",
                "xhci-mtk-hcd-v2",
                "mediatek-drm",
                "mtk_iommu",
                "mtk-scpsys-mt6895",
                "mtk-smi",
                "a-consumer",
            ]
            paths = [f"updates/{name}.ko" for name in names] + ["kernel/z-provider.ko"]
            for name in paths:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
            (root / "modules.dep").write_text("".join(f"{name}:\n" for name in paths))
            (root / "modules.softdep").write_text(
                "softdep a_consumer pre: z_provider.ko\n"
            )
            order = module_order(root)
            pairs = [
                ("z-provider", "a-consumer"),
                ("xhci-mtk-hcd-v2", "mtu3"),
                ("mtu3", "tcpc_mt6375"),
                ("tcpc_mt6375", "extcon-mtk-usb"),
                ("tcpc_class", "extcon-mtk-usb"),
            ]
            pairs += [
                (name, "mediatek-drm")
                for name in ("mtk_iommu", "mtk-scpsys-mt6895", "mtk-smi")
            ]
            for provider, consumer in pairs:
                with self.subTest(provider=provider, consumer=consumer):
                    self.assertIn(provider + ".ko", order)
                    self.assertLess(
                        order.index(provider + ".ko"), order.index(consumer + ".ko")
                    )

    def test_standard_dt_table(self):
        payload = b"device-tree"
        data = dt_image(payload)
        self.assertEqual(
            struct.unpack(">8I", data[:32]),
            (0xD7B7AB1E, len(data), 32, 32, 1, 32, 4096, 0),
        )
        size, offset, *fields = struct.unpack(">8I", data[32:64])
        self.assertEqual((size, offset, fields), (len(payload), 64, [0] * 6))
        self.assertEqual(data[offset : offset + size], payload)


if __name__ == "__main__":
    unittest.main()
