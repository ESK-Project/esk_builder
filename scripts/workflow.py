import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tomllib
from itertools import groupby
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def valid_version(version):
    if not version.startswith("v"):
        return False
    release, separator, suffix = version[1:].partition("-")
    parts = release.split(".")
    if len(parts) not in (2, 3) or not all(
        part.isascii() and part.isdecimal() for part in parts
    ):
        return False
    if not separator:
        return True
    for prefix in ("alpha", "beta", "rc"):
        if suffix.startswith(prefix):
            number = suffix[len(prefix) :]
            return number.isascii() and number.isdecimal()
    return False


def csv_items(value):
    items = [item.strip() for item in value.split(",")]
    if not items or any(not item for item in items):
        raise ValueError("Device and variant lists must contain nonempty names")
    return list(dict.fromkeys(items))


def select_builds(mode, devices, variants, available_devices, available_variants):
    if mode == "full":
        chosen_devices = list(available_devices)
        chosen_variants = list(available_variants)
    elif mode == "custom":
        chosen_devices = csv_items(devices)
        chosen_variants = csv_items(variants)
    else:
        raise ValueError(f"Unknown build mode: {mode}")

    for name in chosen_devices:
        if name not in available_devices:
            raise ValueError(f"Unknown device: {name}")

    for name in chosen_variants:
        if name not in available_variants:
            raise ValueError(f"Unknown variant: {name}")

    selection = [
        {"target": device, "preset": variant}
        for device in chosen_devices
        for variant in chosen_variants
    ]
    if not selection:
        raise ValueError("No builds selected")
    return selection


def resolve_kernel_ref(url, ref):
    if len(ref) == 40 and all(char in "0123456789abcdefABCDEF" for char in ref):
        return ref.lower()
    result = subprocess.run(
        ["git", "ls-remote", "--exit-code", "--", url, ref, f"{ref}^{{}}"],
        check=True,
        capture_output=True,
        text=True,
    )
    refs = dict(line.split("\t", 1)[::-1] for line in result.stdout.splitlines())
    names = [name for name in refs if not name.endswith("^{}")]
    if len(names) != 1:
        raise ValueError(f"Kernel ref is ambiguous: {ref}")
    name = names[0]
    return refs.get(f"{name}^{{}}", refs[name])


def pin_kernel_refs(selection, override):
    commits = {}
    for item in selection:
        with (ROOT / "targets" / f"{item['target']}.toml").open("rb") as handle:
            target = tomllib.load(handle)
        key = (target["kernel_url"], override or target["kernel_ref"])
        if key not in commits:
            commits[key] = resolve_kernel_ref(*key)
        item["kernel_ref"] = commits[key]


def append_outputs(values):
    with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as output:
        for key, value in values.items():
            output.write(f"{key}={value}\n")


def selected_from_env():
    selection = json.loads(os.environ["SELECTION"])
    if not isinstance(selection, list) or not selection:
        raise ValueError("Selected builds must be a nonempty list")
    pairs = [(item["target"], item["preset"]) for item in selection]
    if len(set(pairs)) != len(pairs):
        raise ValueError("Selected builds contain duplicates")
    return selection


def read_builds(selection, root, run_id, run_attempt):
    records = []
    for item in selection:
        target = item["target"]
        preset = item["preset"]
        directory = root / f"{target}-{preset}-{run_id}-{run_attempt}"
        metadata_path = directory / "build.json"
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        if metadata["target"] != target or metadata["preset"] != preset:
            raise ValueError(f"Incorrect build metadata: {directory.name}")
        if metadata["kernel_commit"] != item["kernel_ref"]:
            raise ValueError(f"Incorrect kernel commit: {directory.name}")

        artifacts = metadata["artifacts"]
        packages = [name for name in artifacts if name.endswith("-AnyKernel3.zip")]
        if len(packages) != 1:
            raise ValueError(f"Expected one AnyKernel3 archive: {directory.name}")

        for name, expected in artifacts.items():
            if Path(name).name != name:
                raise ValueError(f"Invalid artifact name: {name}")
            path = directory / name
            if not path.is_file():
                raise ValueError(f"Missing build artifact: {path}")
            with path.open("rb") as handle:
                actual = hashlib.file_digest(handle, "sha256").hexdigest()
            if actual != expected:
                raise ValueError(f"Artifact hash mismatch: {path}")

        records.append((item, metadata, directory, packages[0]))

    return records


def write_plan_summary(selection, mode, version):
    lines = [
        "### Build plan",
        "",
        f"Mode: {mode}",
        "",
        "| Device | Variant | Kernel commit |",
        "| --- | --- | --- |",
    ]
    for item in selection:
        lines.append(
            f"| {item['target']} | {item['preset']} | {item['kernel_ref'][:12]} |"
        )
    if version:
        lines.extend(["", f"Release: {version}"])
    lines.append("")
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as output:
        output.write("\n".join(lines))


def write_summary(records):
    lines = [
        "### Verified builds",
        "",
        "| Device | Variant | Kernel version | Commit |",
        "| --- | --- | --- | --- |",
    ]
    for item, metadata, _, _ in records:
        lines.append(
            f"| {item['target']} | {item['preset']} | "
            f"{metadata['kernel_version']} | {metadata['kernel_commit'][:12]} |"
        )
    lines.append("")
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as output:
        output.write("\n".join(lines))


def package_component(value):
    def allowed(char):
        return char.isascii() and (char.isalnum() or char in "._+-")

    result = "".join(
        "".join(chars) if valid else "-" for valid, chars in groupby(value, allowed)
    ).strip(".-")
    if not result:
        raise ValueError(f"Invalid package name component: {value}")
    return result


def prepare_release(records, version):
    destination = Path("publish_files")
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir()
    builds = []

    for item, metadata, directory, source_name in records:
        name = (
            f"{package_component(metadata['kernel_name'])}-{version}-"
            f"{item['target']}-{item['preset']}-"
            f"{package_component(metadata['kernel_version'])}-AnyKernel3.zip"
        )
        shutil.copyfile(directory / source_name, destination / name)
        builds.append(
            {
                "target": item["target"],
                "preset": item["preset"],
                "kernel_name": metadata["kernel_name"],
                "kernel_version": metadata["kernel_version"],
                "kernel_url": metadata["kernel_url"],
                "kernel_commit": metadata["kernel_commit"],
                "builder_commit": metadata["builder_commit"],
                "toolchain": metadata["toolchain"],
                "ksu_commit": metadata.get("ksu_commit"),
                "susfs_commit": metadata.get("susfs_commit"),
                "features": metadata["features"],
                "source_package": source_name,
                "release_package": name,
                "sha256": metadata["artifacts"][source_name],
            }
        )

    manifest = {
        "schema_version": 1,
        "version": version,
        "prerelease": True,
        "builds": builds,
    }
    (destination / "release.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    commits = dict.fromkeys(
        (build["kernel_url"], build["kernel_commit"]) for build in builds
    )
    commit_links = ", ".join(
        f"[{commit[:12]}]({url.rstrip('/')}/commit/{commit})" for url, commit in commits
    )
    lines = [
        "### Build information",
        "",
        f"ESK version: {version}",
        f"Kernel commit: {commit_links}",
        "",
        "| Device | Variant | Kernel version | Compiler |",
        "| --- | --- | --- | --- |",
    ]
    for build in builds:
        lines.append(
            f"| {build['target']} | {build['preset']} | {build['kernel_version']} | "
            f"{build['toolchain']} |"
        )
    lines.append("")
    Path("release-notes.md").write_text("\n".join(lines), encoding="utf-8")
    return records[0][1]["kernel_name"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("plan", "verify", "notes"))
    args = parser.parse_args()

    if args.command == "plan":
        available_devices = sorted(
            path.stem for path in (ROOT / "targets").glob("*.toml")
        )
        with (ROOT / "presets.toml").open("rb") as handle:
            available_variants = list(tomllib.load(handle))
        selection = select_builds(
            os.environ["MODE"],
            os.environ["DEVICES"],
            os.environ["VARIANTS"],
            available_devices,
            available_variants,
        )
        release = os.environ["CREATE_RELEASE"] == "true"
        version = os.environ.get("RELEASE_TAG", "").strip()
        if release:
            if not valid_version(version):
                raise ValueError(
                    "Release tag must use vN.M, vN.M.P or a -rcN/-betaN/-alphaN suffix"
                )
            if os.environ["DEBUG"] == "true":
                raise ValueError("Debug builds cannot be published as release assets")
        else:
            version = ""

        pin_kernel_refs(selection, os.environ.get("KERNEL_REF", ""))
        append_outputs({"selected": json.dumps(selection, separators=(",", ":"))})
        write_plan_summary(selection, os.environ["MODE"], version)
        print("Selected builds:")
        for item in selection:
            print(f"  {item['target']} / {item['preset']}")
        return

    selection = selected_from_env()
    records = read_builds(
        selection,
        Path("release_files"),
        os.environ["GITHUB_RUN_ID"],
        os.environ["GITHUB_RUN_ATTEMPT"],
    )

    if args.command == "verify":
        write_summary(records)
        return

    version = os.environ["RELEASE_TAG"]
    if not valid_version(version):
        raise ValueError("Invalid release tag")
    kernel_name = prepare_release(records, version)
    append_outputs({"kernel_name": kernel_name})


if __name__ == "__main__":
    try:
        main()
    except (
        ValueError,
        OSError,
        KeyError,
        TypeError,
        subprocess.CalledProcessError,
    ) as error:
        raise SystemExit(str(error)) from error
