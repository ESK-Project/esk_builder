import gzip
import os
import shutil
import struct
import subprocess
import tempfile
from graphlib import TopologicalSorter
from pathlib import Path

from .config import load_target


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
        module = names.get(fields[1].replace("-", "_"))
        if module is None:
            continue
        mode = ""
        for field in fields[2:]:
            if field in {"pre:", "post:"}:
                mode = field
            elif dependency := names.get(field.replace("-", "_")):
                if mode == "pre:":
                    graph[module].add(dependency)
                elif mode == "post:":
                    graph[dependency].add(module)
    # mtu3 probes its xHCI child synchronously, without a symbol dependency.
    for host in ("xhci-mtk-hcd-v2.ko", "xhci-mtk-hcd.ko"):
        if host in graph and "mtu3.ko" in graph:
            graph["mtu3.ko"].add(host)
    selected = {path.name for path in (root / "updates").rglob("*.ko")}
    if not selected:
        raise ValueError("No installed donor modules")
    pending = list(selected)
    while pending:
        for dependency in graph[pending.pop()] - selected:
            selected.add(dependency)
            pending.append(dependency)
    ordered = TopologicalSorter(
        {name: sorted(graph[name]) for name in sorted(selected)}
    )
    return list(ordered.static_order())


def package_ack(workspace: Path, target: str, out: Path, anykernel: Path) -> list[Path]:
    profile = load_target(workspace, target)
    if profile.get("layout") != "ack":
        raise ValueError("Packaging requires an ACK target")
    out, anykernel = out.resolve(), anykernel.resolve()
    release = (out / "include/config/kernel.release").read_text().strip()
    installed = list((out / "modules").glob(f"*/lib/modules/{release}"))
    if len(installed) != 1:
        raise ValueError(
            "Expected exactly one installed module tree for the kernel release"
        )
    root = installed[0]
    order = module_order(root)
    destination = out / "ak3"
    if destination.is_symlink():
        raise ValueError("Package output cannot be a symlink")
    destination.mkdir(exist_ok=True)
    packages = []
    with tempfile.TemporaryDirectory(prefix="ack-package-", dir=out) as temporary:
        stage = Path(temporary)
        flat = stage / "flatten"
        flat.mkdir()
        for line in (root / "modules.dep").read_text().splitlines():
            module = root / line.split(":", 1)[0]
            if (flat / module.name).exists():
                raise ValueError(f"Duplicate depmod module basename: {module.name}")
            shutil.copy2(module, flat / module.name)
        loads = stage / "load"
        loads.mkdir()
        for name in (
            "modules.load",
            "modules.load.vendor_boot",
            "modules.load.recovery",
        ):
            (loads / name).write_text("\n".join(order) + "\n")
        kernel = stage / "kernel/arch/arm64/boot"
        kernel.mkdir(parents=True)
        with gzip.open(out / "arch/arm64/boot/Image.gz", "rb") as source:
            with (kernel / "Image").open("wb") as image:
                shutil.copyfileobj(source, image)
        for board in ("xaga", "xaga_global"):
            ak3 = stage / board
            shutil.copytree(
                anykernel,
                ak3,
                ignore=shutil.ignore_patterns(".git", ".github", "placeholder"),
            )
            dt = ak3 / "dt"
            dt.mkdir()
            (dt / "dtb").write_bytes(dt_image((out / "dt/mt6895.dtb").read_bytes()))
            (dt / "dtbo.img").write_bytes(
                dt_image((out / f"dt/{board}.dtbo").read_bytes())
            )
            environment = os.environ | {
                "AK3": str(ak3),
                "KERNEL_OUT": str(stage / "kernel"),
                "INSTALLED_MODULES": str(root.parents[2]),
                "KERNEL_RELEASE": release,
                "MOD_FLAT": str(flat),
                "MOD_STAGE": str(stage / "modules"),
                "MOD_LOAD": str(loads),
                "MODULE_PACKAGE": str(ak3 / "module.tar.xz"),
                "DLKM_FS_CONFIG": str(ak3 / "config/vendor_dlkm_fs_config"),
                "DLKM_FILE_CONTEXTS": str(ak3 / "config/vendor_dlkm_file_contexts"),
                "OUT_DIR": str(destination),
                "STEP": "1",
                "PACKAGE_NAME": f"ESK-{target}-{board}-{release}",
            }
            subprocess.run(
                [
                    "bash",
                    "-euo",
                    "pipefail",
                    "-c",
                    "source scripts/common.sh; source scripts/modules.sh; source scripts/package.sh; "
                    "vendor_boot; vendor_dlkm; "
                    'tar -C "$MOD_STAGE" -cJf "$MODULE_PACKAGE" vendor_dlkm vendor_boot; '
                    'package_anykernel "$PACKAGE_NAME"',
                ],
                cwd=workspace,
                env=environment,
                check=True,
            )
            packages.append(
                destination / f"{environment['PACKAGE_NAME']}-AnyKernel3.zip"
            )
    return packages
