import shutil
import struct
import subprocess
import tempfile
from graphlib import TopologicalSorter
from pathlib import Path

from .config import load_target

# Adapted from https://github.com/RengokuSensei/android_kernel_modules_xiaomi_mt6895-6.12/blob/main/build.sh
PROBE_DEPENDENCIES = {
    "mtu3.ko": ("xhci-mtk-hcd-v2.ko", "xhci-mtk-hcd.ko"),
    "mt6375-charger.ko": ("mtu3.ko",),
    "tcpc_class.ko": ("mtu3.ko",),
    "tcpc_mt6375.ko": ("mtu3.ko",),
    "extcon-mtk-usb.ko": ("mtu3.ko", "tcpc_mt6375.ko", "tcpc_class.ko"),
    "mediatek-drm.ko": ("mtk_iommu.ko", "mtk-scpsys-mt6895.ko", "mtk-smi.ko"),
}


def dt_image(payload: bytes) -> bytes:
    header = struct.pack(">8I", 0xD7B7AB1E, 64 + len(payload), 32, 32, 1, 32, 4096, 0)
    entry = struct.pack(">8I", len(payload), 64, 0, 0, 0, 0, 0, 0)
    return header + entry + payload


def module_order(root: Path) -> list[str]:
    graph: dict[str, set[str]] = {}
    for line in (root / "modules.dep").read_text().splitlines():
        module, dependencies = line.split(":", 1)
        graph[Path(module).name] = {Path(dep).name for dep in dependencies.split()}
    files = {path.name for path in root.rglob("*.ko")}
    if graph.keys() != files or any(deps - files for deps in graph.values()):
        raise ValueError("Incomplete installed module dependencies")
    names = {name.removesuffix(".ko").replace("-", "_"): name for name in files}
    for line in (root / "modules.softdep").read_text().splitlines():
        fields = line.split()
        if len(fields) < 3 or fields[0] != "softdep":
            continue
        module = names.get(fields[1].removesuffix(".ko").replace("-", "_"))
        if module is None:
            continue
        mode = ""
        for field in fields[2:]:
            if field in {"pre:", "post:"}:
                mode = field
            elif dependency := names.get(field.removesuffix(".ko").replace("-", "_")):
                if mode == "pre:":
                    graph[module].add(dependency)
                elif mode == "post:":
                    graph[dependency].add(module)
    # Probe-time device lookups also require providers without symbol dependencies.
    for module, dependencies in PROBE_DEPENDENCIES.items():
        if module in graph:
            graph[module].update(dep for dep in dependencies if dep in graph)
    # This helper can shut down LK clocks before display takeover.
    selected = {
        path.name
        for path in (root / "updates").rglob("*.ko")
        if path.name not in {"clk-disable-unused.ko", "clk_disable_unused.ko"}
    }
    if not selected:
        raise ValueError("No installed donor modules")
    pending = list(selected)
    while pending:
        for dependency in graph[pending.pop()] - selected:
            selected.add(dependency)
            pending.append(dependency)
    return list(
        TopologicalSorter(
            {name: sorted(graph[name]) for name in sorted(selected)}
        ).static_order()
    )


def update_ramdisk(tool: Path, archive: Path, additions: dict[str, Path]) -> None:
    listing = subprocess.check_output(
        [str(tool), "cpio", str(archive), "ls -r"], text=True
    )
    commands = [
        f"rm {name}"
        for line in listing.splitlines()
        if (name := line.rsplit("\t", 1)[-1]).endswith(".ko")
    ]
    if additions:
        commands.append("rm -r lib/modules")
        directories = sorted(
            {
                str(parent)
                for name in additions
                for parent in Path(name).parents
                if str(parent) != "."
            },
            key=lambda name: (name.count("/"), name),
        )
        commands.extend(f"mkdir 0755 {directory}" for directory in directories)
        commands.extend(f"add 0644 {name} {path}" for name, path in additions.items())
    if commands:
        subprocess.run([str(tool), "cpio", str(archive), *commands], check=True)


def package_ack(
    workspace: Path, target: str, out: Path, assets: Path, modules: Path
) -> list[Path]:
    if load_target(workspace, target).get("layout") != "ack":
        raise ValueError("Packaging requires an ACK target")
    out, assets, modules = out.resolve(), assets.resolve(), modules.resolve()
    tool = assets / "magiskboot"
    release = (out / "include/config/kernel.release").read_text().strip()
    installed = list((out / "modules").glob(f"*/lib/modules/{release}"))
    if len(installed) != 1:
        raise ValueError(
            "Expected exactly one installed module tree for the kernel release"
        )
    root = installed[0]
    order = module_order(root)
    destination = out / "images"
    if destination.is_symlink():
        raise ValueError("Package output cannot be a symlink")
    destination.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ack-package-", dir=out) as temporary:
        stage = Path(temporary)
        flat = stage / "lib/modules" / release
        flat.mkdir(parents=True)
        for line in (root / "modules.dep").read_text().splitlines():
            module = root / line.split(":", 1)[0]
            if module.name in order:
                shutil.copy2(module, flat / module.name)
        for name in ("modules.order", "modules.builtin", "modules.builtin.modinfo"):
            shutil.copy2(root / name, flat / name)
        subprocess.run(["depmod", "-b", str(stage), release], check=True)
        for name in ("modules.load", "modules.load.recovery"):
            (flat / name).write_text("\n".join(order) + "\n")
        lines = []
        for line in (flat / "modules.dep").read_text().splitlines():
            module, dependencies = line.split(":", 1)
            providers = set(dependencies.split())
            providers.update(
                name for name in PROBE_DEPENDENCIES.get(module, ()) if name in order
            )
            lines.append(f"{module}: {' '.join(sorted(providers))}")
        (flat / "modules.dep").write_text("\n".join(lines) + "\n")
        additions = {
            f"lib/modules/{path.name}": path
            for path in flat.iterdir()
            if path.is_file() and path.suffix != ".bin"
        }
        for firmware in sorted((modules / "vendor_firmware").rglob("*")):
            if firmware.is_file() and firmware.name not in {"README.md", ".gitkeep"}:
                for directory in ("lib/firmware", "vendor/firmware"):
                    additions[f"{directory}/{firmware.name}"] = firmware
        for partition, base in (
            ("boot", "boot_a.img"),
            ("vendor_boot", "vendor_boot.img"),
        ):
            work = stage / partition
            work.mkdir()
            subprocess.run(
                [str(tool), "unpack", "-n", "-h", str(assets / base)],
                cwd=work,
                check=True,
            )
            compressed = work / (
                "ramdisk.cpio" if partition == "boot" else "vendor_ramdisk/ramdisk.cpio"
            )
            archive = work / "ramdisk.raw"
            subprocess.run(
                [str(tool), "decompress", str(compressed), str(archive)], check=True
            )
            update_ramdisk(
                tool, archive, additions if partition == "vendor_boot" else {}
            )
            subprocess.run(
                [str(tool), "compress=lz4_legacy", str(archive), str(compressed)],
                check=True,
            )
            archive.unlink()
            if partition == "boot":
                shutil.copy2(out / "arch/arm64/boot/Image.gz", work / "kernel")
            else:
                (work / "dtb").write_bytes(
                    dt_image((out / "dt/mt6895.dtb").read_bytes())
                )
                header = work / "header"
                header.write_text(
                    header.read_text().replace(
                        "cmdline=", "cmdline=clk_ignore_unused log_buf_len=8M ", 1
                    )
                )
            subprocess.run(
                [
                    str(tool),
                    "repack",
                    "-n",
                    str(assets / base),
                    str(stage / f"{partition}.img"),
                ],
                cwd=work,
                check=True,
            )
        (stage / "dtbo.img").write_bytes(dt_image((out / "dt/xaga.dtbo").read_bytes()))
        packages = [
            destination / name for name in ("boot.img", "vendor_boot.img", "dtbo.img")
        ]
        for package in packages:
            shutil.copy2(stage / package.name, package)
    return packages
