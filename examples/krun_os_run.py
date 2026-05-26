#!/usr/bin/env python3
"""Run a prepared libkrun OS bundle image on the macOS host.

This is a product-facing wrapper around os_mode_import_container_bundle.py. The
container image is only the artifact transport; the launched VM is still a
host-side libkrun/HVF process.
"""

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
IMPORTER = REPO_ROOT / "examples" / "os_mode_import_container_bundle.py"
IMPORT_METADATA_FILE = ".libkrun-os-bundle-import.json"
EPHEMERAL_CLONE_RE = re.compile(r"^vm-root-\d+-\d+\.raw$")
EPHEMERAL_SMOKE_RE = re.compile(r"^smoke-\d+-\d+\.json$")


def non_empty_arg(value: str) -> str:
    if value == "":
        raise argparse.ArgumentTypeError("value must be non-empty")
    return value


def non_empty_path(value: str) -> Path:
    if value == "":
        raise argparse.ArgumentTypeError("path must be non-empty")
    return Path(value)


def non_negative_float(value: str) -> float:
    try:
        parsed = float(value)
    except ValueError as err:
        raise argparse.ArgumentTypeError("value must be a number") from err
    if parsed < 0:
        raise argparse.ArgumentTypeError("value must be non-negative")
    return parsed


def default_cache_root() -> Path:
    if "KRUN_OS_BUNDLE_CACHE" in os.environ:
        return Path(os.environ["KRUN_OS_BUNDLE_CACHE"]).expanduser()
    if platform.system() == "Darwin":
        return Path.home() / "Library" / "Caches" / "libkrun" / "os-bundles"
    if "XDG_CACHE_HOME" in os.environ:
        return Path(os.environ["XDG_CACHE_HOME"]).expanduser() / "libkrun" / "os-bundles"
    return Path.home() / ".cache" / "libkrun" / "os-bundles"


def image_cache_name(image: str) -> str:
    digest = hashlib.sha256(image.encode("utf-8")).hexdigest()[:16]
    readable = image
    if "@sha256:" in readable:
        readable = readable.split("@sha256:", 1)[0]
    readable = readable.rsplit("/", 1)[-1]
    readable = readable.replace(":", "-")
    readable = re.sub(r"[^A-Za-z0-9_.-]+", "-", readable).strip(".-")
    if not readable:
        readable = "image"
    return f"{readable}-{digest}"


def image_is_digest_pinned(image: str) -> bool:
    return "@sha256:" in image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run a prepared libkrun OS bundle image from a macOS host cache. "
            "The image is extracted and validated, a fresh APFS clone is "
            "created, and the host-side libkrun/HVF VM is launched."
        )
    )
    parser.add_argument(
        "image",
        type=non_empty_arg,
        nargs="?",
        help="OCI image containing /libkrun-os-bundle. Optional with --clean-cache.",
    )
    parser.add_argument(
        "--cache-dir",
        type=non_empty_path,
        default=None,
        help=(
            "Directory for extracted bundles. Defaults to "
            "$KRUN_OS_BUNDLE_CACHE, ~/Library/Caches/libkrun/os-bundles on "
            "macOS, or $XDG_CACHE_HOME/libkrun/os-bundles on other hosts."
        ),
    )
    parser.add_argument(
        "--runtime",
        choices=("auto", "docker", "podman"),
        default="auto",
        help="Container runtime used only for bundle extraction.",
    )
    parser.add_argument(
        "--pull",
        action="store_true",
        help="Explicitly pull IMAGE before extracting the bundle and record pull timing.",
    )
    parser.add_argument(
        "--name",
        type=non_empty_arg,
        default=None,
        help="Cache entry name. Defaults to a sanitized image name plus image-reference hash.",
    )
    parser.add_argument(
        "--clone-dest",
        type=non_empty_path,
        default=None,
        help="Per-launch APFS clone destination. Relative paths resolve inside the extracted bundle.",
    )
    parser.add_argument(
        "--smoke-output",
        type=non_empty_path,
        default=None,
        help="Smoke JSON output path. Relative paths resolve inside the extracted bundle.",
    )
    parser.add_argument(
        "--perf-output",
        type=non_empty_path,
        default=None,
        help="Optional perf JSON output path. Relative paths resolve inside the extracted bundle.",
    )
    parser.add_argument(
        "--no-reuse",
        action="store_true",
        help="Do not reuse a matching extracted bundle cache entry.",
    )
    parser.add_argument(
        "--strict-digest",
        action="store_true",
        default=None,
        help="Require image@sha256:<digest>. Defaults on for digest-pinned image references.",
    )
    parser.add_argument(
        "--no-strict-digest",
        action="store_false",
        dest="strict_digest",
        help="Allow mutable image tags.",
    )
    parser.add_argument(
        "--print-only",
        action="store_true",
        help="Print the resolved importer command without running it.",
    )
    parser.add_argument(
        "--clean-cache",
        action="store_true",
        help=(
            "Remove wrapper-generated ephemeral APFS clones and smoke JSON "
            "from the cache. If IMAGE is supplied, clean only that cache entry."
        ),
    )
    parser.add_argument(
        "--delete-extracted-bundles",
        action="store_true",
        help=(
            "With --clean-cache, also remove safe extracted bundle cache "
            "entries. Entries containing unknown files are refused."
        ),
    )
    parser.add_argument(
        "--older-than-hours",
        type=non_negative_float,
        default=0.0,
        help="With --clean-cache, remove only matching files older than this many hours.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="With --clean-cache, print what would be removed without deleting files.",
    )
    args = parser.parse_args()
    if not args.clean_cache and args.image is None:
        parser.error("image is required unless --clean-cache is used")
    if args.delete_extracted_bundles and not args.clean_cache:
        parser.error("--delete-extracted-bundles requires --clean-cache")
    return args


def command_quote(command: list[str]) -> str:
    import shlex

    return " ".join(shlex.quote(item) for item in command)


def build_importer_command(args: argparse.Namespace, launch_id: str) -> list[str]:
    assert args.image is not None
    cache_root = (args.cache_dir if args.cache_dir is not None else default_cache_root()).expanduser()
    output_dir = cache_root / (args.name if args.name is not None else image_cache_name(args.image))
    output_dir = output_dir.resolve()

    strict_digest = image_is_digest_pinned(args.image) if args.strict_digest is None else args.strict_digest
    clone_dest = args.clone_dest or Path(f"vm-root-{launch_id}.raw")
    smoke_output = args.smoke_output or Path(f"smoke-{launch_id}.json")

    command = [
        sys.executable,
        str(IMPORTER),
        "--image",
        args.image,
        "--output-dir",
        str(output_dir),
        "--runtime",
        args.runtime,
        "--clone-dest",
        str(clone_dest),
        "--smoke-output",
        str(smoke_output),
    ]
    if not args.no_reuse:
        command.append("--reuse-extracted-output-dir")
    if args.pull:
        command.append("--pull")
    if strict_digest:
        command.append("--strict-digest")
    if args.perf_output is not None:
        command.extend(["--perf-output", str(args.perf_output)])
    if not args.print_only:
        command.append("--run")
    return command


def cache_root_from_args(args: argparse.Namespace) -> Path:
    return (args.cache_dir if args.cache_dir is not None else default_cache_root()).expanduser().resolve()


def cache_entries(args: argparse.Namespace) -> list[Path]:
    cache_root = cache_root_from_args(args)
    if args.image is not None:
        return [cache_root / (args.name if args.name is not None else image_cache_name(args.image))]
    if not cache_root.is_dir():
        return []
    return sorted(path for path in cache_root.iterdir() if path.is_dir())


def is_old_enough(path: Path, older_than_hours: float) -> bool:
    if older_than_hours <= 0:
        return True
    age_seconds = time.time() - path.stat().st_mtime
    return age_seconds >= older_than_hours * 3600


def is_wrapper_ephemeral_file(path: Path) -> bool:
    name = path.name
    return path.is_file() and (
        EPHEMERAL_CLONE_RE.fullmatch(name) is not None
        or EPHEMERAL_SMOKE_RE.fullmatch(name) is not None
    )


def manifest_bundle_files(bundle_dir: Path) -> set[Path]:
    manifest_path = bundle_dir / "manifest.json"
    allowed = {manifest_path, bundle_dir / "source-manifest.json"}
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return allowed
    if not isinstance(manifest, dict):
        return allowed
    for key in ("root_disk", "kernel", "initramfs"):
        value = manifest.get(key)
        if isinstance(value, str) and value and not Path(value).is_absolute() and ".." not in Path(value).parts:
            allowed.add(bundle_dir / value)
    return {path.resolve() for path in allowed}


def safe_to_delete_cache_entry(entry: Path) -> tuple[bool, str | None]:
    metadata = entry / IMPORT_METADATA_FILE
    bundle_dir = entry / "libkrun-os-bundle"
    if not metadata.is_file():
        return False, f"missing import metadata: {metadata}"
    if not bundle_dir.is_dir():
        return False, f"missing bundle directory: {bundle_dir}"
    allowed_files = manifest_bundle_files(bundle_dir)
    allowed_files.add(metadata.resolve())

    for path in entry.rglob("*"):
        if path.is_dir():
            continue
        if path.is_symlink():
            return False, f"refusing symlink in cache entry: {path}"
        resolved = path.resolve()
        if resolved in allowed_files or is_wrapper_ephemeral_file(path):
            continue
        return False, f"refusing unknown file in cache entry: {path}"
    return True, None


def remove_path(path: Path, *, dry_run: bool) -> None:
    if dry_run:
        print(f"would remove: {path}")
        return
    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink()
    print(f"removed: {path}")


def clean_cache(args: argparse.Namespace) -> int:
    entries = cache_entries(args)
    if not entries:
        print(f"cache has no matching entries: {cache_root_from_args(args)}")
        return 0

    removed_files = 0
    removed_entries = 0
    refused_entries = 0
    for entry in entries:
        bundle_dir = entry / "libkrun-os-bundle"
        if bundle_dir.is_dir():
            for path in sorted(bundle_dir.iterdir()):
                if is_wrapper_ephemeral_file(path) and is_old_enough(path, args.older_than_hours):
                    remove_path(path, dry_run=args.dry_run)
                    removed_files += 1

        if not args.delete_extracted_bundles:
            continue

        if not entry.exists():
            continue
        ok, reason = safe_to_delete_cache_entry(entry)
        if not ok:
            print(f"refused cache entry: {entry}: {reason}", file=sys.stderr)
            refused_entries += 1
            continue
        if args.older_than_hours > 0 and not is_old_enough(entry, args.older_than_hours):
            continue
        remove_path(entry, dry_run=args.dry_run)
        removed_entries += 1

    print(
        "cache cleanup summary: "
        f"ephemeral_files={removed_files} "
        f"extracted_bundles={removed_entries} "
        f"refused_entries={refused_entries}"
    )
    return 1 if refused_entries else 0


def main() -> None:
    args = parse_args()
    if args.clean_cache:
        raise SystemExit(clean_cache(args))

    if not IMPORTER.is_file():
        print(f"bundle importer does not exist: {IMPORTER}", file=sys.stderr)
        raise SystemExit(1)

    launch_id = f"{int(time.time())}-{os.getpid()}"
    command = build_importer_command(args, launch_id)
    print(command_quote(command))
    if args.print_only:
        return

    proc = subprocess.run(command)
    raise SystemExit(proc.returncode)


if __name__ == "__main__":
    main()
