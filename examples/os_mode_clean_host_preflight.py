#!/usr/bin/env python3
"""Preflight a clean macOS host before an OS-bundle release-gate run."""

import argparse
import json
import platform
import shutil
import sys
import time
from pathlib import Path
from typing import Any

import krun_os_run
import os_mode_collect_release_evidence as release_evidence
import os_mode_import_container_bundle as importer
import os_mode_release_gate as release_gate


def utc_timestamp() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def non_empty_arg(value: str) -> str:
    if value == "":
        raise argparse.ArgumentTypeError("value must be non-empty")
    return value


def non_empty_path(value: str) -> Path:
    if value == "":
        raise argparse.ArgumentTypeError("path must be non-empty")
    return Path(value)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Check that a fresh Apple Silicon host is ready to run the "
            "libkrun OS-bundle release gate without reusing an existing "
            "bundle cache entry."
        )
    )
    parser.add_argument(
        "image",
        type=non_empty_arg,
        nargs="?",
        help="Digest-pinned OS bundle image reference. Optional with --artifact-manifest.",
    )
    parser.add_argument(
        "--artifact-manifest",
        type=non_empty_path,
        default=None,
        help=(
            "Validate a libkrun.os-bundle.artifact.v1 JSON manifest and use "
            "its digest_ref when IMAGE is omitted."
        ),
    )
    parser.add_argument(
        "--output-dir",
        type=non_empty_path,
        required=True,
        help="Release evidence directory that will be passed to os_mode_release_gate.py.",
    )
    parser.add_argument(
        "--cache-dir",
        type=non_empty_path,
        default=None,
        help="Bundle cache root. Defaults to krun_os_run.py's cache selection.",
    )
    parser.add_argument(
        "--name",
        type=non_empty_arg,
        default=None,
        help="Cache entry name. Defaults to krun_os_run.py's image cache name.",
    )
    parser.add_argument(
        "--runtime",
        choices=("auto", "docker", "podman"),
        default="auto",
        help="Container runtime that will be used for bundle extraction or artifact load.",
    )
    parser.add_argument(
        "--allow-existing-output-dir",
        action="store_true",
        help="Deprecated compatibility option; clean-host baseline preflight rejects it.",
    )
    parser.add_argument(
        "--allow-existing-empty-cache-entry",
        action="store_true",
        help=(
            "Deprecated compatibility option; clean-host baseline preflight "
            "requires the cache entry to be absent."
        ),
    )
    parser.add_argument(
        "--json-output",
        type=non_empty_path,
        required=True,
        help=(
            "Required path for the JSON preflight report. The release gate "
            "consumes this same file with --preflight-json."
        ),
    )
    return parser.parse_args()


def existing_ancestor(path: Path) -> Path | None:
    candidate = path.expanduser()
    while True:
        if candidate.exists():
            return candidate.resolve()
        parent = candidate.parent
        if parent == candidate:
            return None
        candidate = parent


def directory_entries(path: Path) -> list[str]:
    if not path.is_dir():
        return []
    return sorted(child.name for child in path.iterdir())


def output_dir_report(path: Path, allow_existing_empty: bool) -> tuple[dict[str, Any], list[str]]:
    output_dir = path.expanduser().resolve()
    errors: list[str] = []
    report: dict[str, Any] = {
        "path": str(output_dir),
        "exists": output_dir.exists(),
        "allow_existing_empty": allow_existing_empty,
        "entries": [],
    }
    if output_dir.exists():
        if not output_dir.is_dir():
            report["clean"] = False
            errors.append(f"--output-dir exists and is not a directory: {output_dir}")
            return report, errors
        entries = directory_entries(output_dir)
        report["entries"] = entries
        report["clean"] = len(entries) == 0
        if entries:
            errors.append(f"--output-dir already contains files: {output_dir}; entries={entries}")
        elif not allow_existing_empty:
            errors.append(f"clean-host preflight requires --output-dir to be absent: {output_dir}")
    else:
        report["clean"] = True
    return report, errors


def apfs_report(label: str, target: Path, require_apfs: bool) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    expanded = target.expanduser().resolve()
    ancestor = existing_ancestor(expanded)
    report: dict[str, Any] = {
        "label": label,
        "target": str(expanded),
        "existing_ancestor": str(ancestor) if ancestor is not None else None,
    }
    if ancestor is None:
        report["info"] = {"checked": False, "reason": "no existing ancestor"}
        errors.append(f"{label} path has no existing ancestor: {expanded}")
        return report, errors

    info = importer.apfs_info(ancestor)
    report["info"] = info
    if require_apfs and info.get("is_apfs") is not True:
        errors.append(f"{label} path is not on APFS: {expanded}; info={info}")
    return report, errors


def release_gate_command(
    image: str,
    args: argparse.Namespace,
    *,
    use_artifact_manifest: bool,
) -> list[str]:
    command = [
        str(importer.REPO_ROOT / "examples" / "os_mode_release_gate.py"),
    ]
    if use_artifact_manifest:
        if args.image is not None:
            command.append(image)
        command.extend(["--artifact-manifest", str(args.artifact_manifest.expanduser().resolve())])
    else:
        command.append(image)
    command.extend(["--output-dir", str(args.output_dir.expanduser().resolve())])
    cache_entry = release_gate.cache_entry_for_image(image, args.cache_dir, args.name)
    command.extend(["--cache-dir", str(cache_entry.parent)])
    if args.name is not None:
        command.extend(["--name", args.name])
    if args.runtime != "auto":
        command.extend(["--runtime", args.runtime])
    if args.allow_existing_output_dir:
        command.append("--allow-existing-output-dir")
    if args.json_output is not None:
        command.extend(["--preflight-json", str(args.json_output.expanduser().resolve())])
    command.append("--clean-host-baseline")
    return command


def host_report(require_macos_arm64: bool) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    uname = platform.uname()
    report = {
        "system": uname.system,
        "release": uname.release,
        "version": uname.version,
        "machine": uname.machine,
        "processor": uname.processor,
        "platform": platform.platform(),
        "macos": release_evidence.sw_vers(),
    }
    if require_macos_arm64:
        if uname.system != "Darwin":
            errors.append(f"host system must be Darwin for the macOS clean-host baseline: {uname.system}")
        if uname.machine not in ("arm64", "aarch64"):
            errors.append(f"host machine must be Apple Silicon arm64 for the clean-host baseline: {uname.machine}")
        if report["macos"] is None:
            errors.append("sw_vers metadata is required for the macOS clean-host baseline")
    return report, errors


def runtime_report(requested: str, require_runtime: bool) -> tuple[dict[str, Any], list[str]]:
    report: dict[str, Any] = {
        "requested": requested,
        "available": {
            "docker": shutil.which("docker"),
            "podman": shutil.which("podman"),
        },
        "selected": None,
    }
    if not require_runtime:
        return report, []
    try:
        report["selected"] = importer.choose_runtime(requested)
    except importer.BundleError as err:
        return report, [str(err)]
    return report, []


def artifact_report(path: Path | None) -> tuple[dict[str, Any] | None, str | None, list[str]]:
    if path is None:
        return None, None, []
    try:
        artifact, archive = release_gate.load_artifact_manifest(path)
        image = release_gate.artifact_image_reference(artifact)
    except (release_gate.ReleaseGateError, importer.BundleError) as err:
        return {"path": str(path.expanduser()), "valid": False}, None, [str(err)]
    archive_meta = artifact.get("archive")
    return (
        {
            "path": str(path.expanduser().resolve()),
            "valid": True,
            "digest_ref": image,
            "archive": str(archive),
            "archive_sha256": archive_meta.get("sha256") if isinstance(archive_meta, dict) else None,
            "archive_size_bytes": archive.stat().st_size,
        },
        image,
        [],
    )


def run_preflight(args: argparse.Namespace) -> dict[str, Any]:
    errors: list[str] = []
    require_macos_arm64 = getattr(args, "require_macos_arm64", True)
    require_apfs = getattr(args, "require_apfs", True)
    require_runtime = getattr(args, "require_runtime", True)

    host, host_errors = host_report(require_macos_arm64)
    errors.extend(host_errors)

    artifact, artifact_image, artifact_errors = artifact_report(args.artifact_manifest)
    errors.extend(artifact_errors)

    image = args.image
    if image is not None and artifact_image is not None and image != artifact_image:
        errors.append(f"IMAGE does not match artifact manifest digest_ref: {image} != {artifact_image}")
    if image is None:
        image = artifact_image
    if image is None:
        errors.append("image is required unless --artifact-manifest provides digest_ref")
        image = ""
    elif not importer.image_reference_is_digest_pinned(image):
        errors.append(f"image reference must be digest-pinned: {image}")

    if args.allow_existing_empty_cache_entry:
        errors.append("--allow-existing-empty-cache-entry cannot be used for clean-host baseline preflight")
    if args.allow_existing_output_dir:
        errors.append("--allow-existing-output-dir cannot be used for clean-host baseline preflight")

    cache_entry = release_gate.cache_entry_for_image(image, args.cache_dir, args.name) if image else None
    cache = release_gate.cache_clean_report(cache_entry) if cache_entry is not None else None
    if cache is not None:
        if cache.get("exists") is not False:
            errors.append(f"clean-host preflight requires the derived bundle cache entry to be absent: {cache_entry}")

    output, output_errors = output_dir_report(args.output_dir, False)
    errors.extend(output_errors)

    runtime, runtime_errors = runtime_report(args.runtime, require_runtime)
    errors.extend(runtime_errors)

    if args.json_output is not None:
        json_output = args.json_output.expanduser().resolve()
        if json_output.exists():
            errors.append(f"--json-output destination already exists: {json_output}")
        elif not json_output.parent.is_dir():
            errors.append(f"--json-output parent directory does not exist: {json_output.parent}")
    else:
        errors.append(
            "--json-output is required so the release gate can consume the "
            "same clean-host preflight report with --preflight-json"
        )

    apfs_checks = []
    if cache_entry is not None:
        cache_apfs, cache_apfs_errors = apfs_report("bundle_cache_entry", cache_entry, require_apfs)
        apfs_checks.append(cache_apfs)
        errors.extend(cache_apfs_errors)
    output_apfs, output_apfs_errors = apfs_report("release_evidence_output", args.output_dir, require_apfs)
    apfs_checks.append(output_apfs)
    errors.extend(output_apfs_errors)

    report = {
        "schema_version": 1,
        "created_at_utc": utc_timestamp(),
        "ok": len(errors) == 0,
        "errors": errors,
        "image_ref": image or None,
        "artifact_manifest": artifact,
        "host": host,
        "runtime": runtime,
        "cache_entry": cache,
        "output_dir": output,
        "apfs": apfs_checks,
        "release_gate_command": release_gate_command(
            image,
            args,
            use_artifact_manifest=args.artifact_manifest is not None,
        )
        if image
        else None,
    }
    return report


def main() -> int:
    args = parse_args()
    report = run_preflight(args)
    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.json_output is not None:
        json_output = args.json_output.expanduser().resolve()
        if not json_output.exists() and json_output.parent.is_dir():
            json_output.write_text(payload, encoding="utf-8")
    print(payload, end="")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
