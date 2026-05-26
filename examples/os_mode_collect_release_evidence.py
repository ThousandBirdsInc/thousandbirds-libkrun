#!/usr/bin/env python3
"""Collect release-gate evidence for a libkrun OS bundle run."""

import argparse
import json
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from os_mode_import_container_bundle import apfs_info, sha256_file


class EvidenceError(Exception):
    pass


EARLY_KERNEL_MARKERS = (
    "Booting Linux",
    "Linux version",
    "Kernel command line",
)


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
            "Archive the manifests, smoke/perf JSON, host metadata, APFS "
            "metadata, image reference, build flags, and command lines needed "
            "for a macOS OS-bundle release gate."
        )
    )
    parser.add_argument("--bundle-dir", type=non_empty_path, required=True)
    parser.add_argument("--smoke-json", type=non_empty_path, required=True)
    parser.add_argument("--perf-json", type=non_empty_path, default=None)
    parser.add_argument(
        "--preflight-json",
        type=non_empty_path,
        default=None,
        help="Optional clean-host preflight JSON to archive with release evidence.",
    )
    parser.add_argument(
        "--artifact-manifest-json",
        type=non_empty_path,
        default=None,
        help="Optional libkrun.os-bundle.artifact.v1 manifest to archive with release evidence.",
    )
    parser.add_argument(
        "--artifact-load-ms",
        type=int,
        default=None,
        help="Optional elapsed milliseconds spent loading an archive-delivered artifact image.",
    )
    parser.add_argument("--image-ref", type=non_empty_arg, required=True)
    parser.add_argument("--output-dir", type=non_empty_path, required=True)
    parser.add_argument(
        "--build-command",
        type=non_empty_arg,
        action="append",
        default=[],
        help="Build or install command used for this release gate. May be repeated.",
    )
    parser.add_argument(
        "--apfs-path",
        type=non_empty_path,
        default=None,
        help="Path whose filesystem should be recorded. Defaults to --bundle-dir.",
    )
    parser.add_argument(
        "--allow-existing-output-dir",
        action="store_true",
        help="Allow an existing empty output directory. Non-empty directories are always rejected.",
    )
    return parser.parse_args()


def prepare_output_dir(path: Path, allow_existing_empty: bool) -> Path:
    path = path.expanduser().resolve()
    if path.exists():
        if not path.is_dir():
            raise EvidenceError(f"--output-dir exists and is not a directory: {path}")
        if any(path.iterdir()):
            raise EvidenceError(f"--output-dir already contains files: {path}")
        if not allow_existing_empty:
            raise EvidenceError(
                f"--output-dir already exists; pass --allow-existing-output-dir for an empty directory: {path}"
            )
    else:
        path.mkdir(parents=True)
    return path


def load_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file():
        raise EvidenceError(f"{label} does not exist or is not a file: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise EvidenceError(f"{label} is invalid JSON: {err}") from err
    if not isinstance(payload, dict):
        raise EvidenceError(f"{label} must be a JSON object")
    return payload


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def is_kernel_timestamp_line(line: str) -> bool:
    if not line.startswith("["):
        return False
    end = line.find("]")
    if end <= 1:
        return False
    timestamp = line[1:end].strip()
    seconds, dot, fraction = timestamp.partition(".")
    return bool(dot) and seconds.isdigit() and fraction.isdigit()


def is_early_kernel_line(line: str) -> bool:
    return is_kernel_timestamp_line(line) and any(marker in line for marker in EARLY_KERNEL_MARKERS)


def require_timing(timings: dict[str, Any], key: str, label: str) -> int:
    value = timings.get(key)
    require(isinstance(value, int) and not isinstance(value, bool) and value >= 0, f"{label} timing {key} is missing or invalid")
    return value


def copy_artifact(src: Path, output_dir: Path, name: str) -> dict[str, Any]:
    if not src.is_file():
        raise EvidenceError(f"artifact does not exist or is not a file: {src}")
    dst = output_dir / name
    if dst.exists():
        raise EvidenceError(f"archive destination already exists: {dst}")
    shutil.copy2(src, dst)
    return {
        "source": str(src),
        "archive": str(dst),
        "sha256": sha256_file(dst),
        "size_bytes": dst.stat().st_size,
    }


def sw_vers() -> dict[str, str] | None:
    if platform.system() != "Darwin":
        return None
    values: dict[str, str] = {}
    for key in ("productName", "productVersion", "buildVersion"):
        try:
            proc = subprocess.run(
                ["sw_vers", f"-{key}"],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            return None
        values[key] = proc.stdout.strip()
    return values


def host_metadata() -> dict[str, Any]:
    uname = platform.uname()
    return {
        "system": uname.system,
        "node": uname.node,
        "release": uname.release,
        "version": uname.version,
        "machine": uname.machine,
        "processor": uname.processor,
        "platform": platform.platform(),
        "macos": sw_vers(),
    }


def validate_smoke(smoke: dict[str, Any], bundle_manifest: dict[str, Any]) -> None:
    require(smoke.get("ready") is True, "smoke JSON must record ready=true")
    require(smoke.get("observed_root") == bundle_manifest.get("expected_root"), "smoke observed_root does not match bundle expected_root")
    observed_consoles = smoke.get("observed_consoles")
    require(
        isinstance(observed_consoles, list) and bundle_manifest.get("console") in observed_consoles,
        "smoke observed_consoles does not include bundle console",
    )
    expected_pid1 = bundle_manifest.get("expected_pid1")
    require(smoke.get("observed_pid1") != "init.krun", "smoke observed init.krun as PID 1")
    if expected_pid1 is not None:
        require(smoke.get("observed_pid1") == expected_pid1, "smoke observed_pid1 does not match bundle expected_pid1")
    require(isinstance(smoke.get("bundle"), dict), "smoke JSON must contain importer bundle metadata")
    timings = smoke.get("timings")
    require(isinstance(timings, dict), "smoke JSON must contain timing markers")
    first = require_timing(timings, "first_kernel_log_ms", "smoke")
    for key in ("root_ms", "pid1_ms", "console_ms", "ready_ms"):
        value = require_timing(timings, key, "smoke")
        require(first <= value, f"smoke timing first_kernel_log_ms must be no later than {key}")
    output_lines = smoke.get("output_lines")
    require(
        isinstance(output_lines, list)
        and all(isinstance(line, str) for line in output_lines)
        and any(is_early_kernel_line(line) for line in output_lines),
        "smoke JSON must include an early kernel boot log line",
    )


def collect_release_evidence(args: argparse.Namespace) -> dict[str, Any]:
    bundle_dir = args.bundle_dir.expanduser().resolve()
    if not bundle_dir.is_dir():
        raise EvidenceError(f"--bundle-dir does not exist or is not a directory: {bundle_dir}")
    output_dir = prepare_output_dir(args.output_dir, args.allow_existing_output_dir)

    bundle_manifest_path = bundle_dir / "manifest.json"
    source_manifest_path = bundle_dir / "source-manifest.json"
    smoke_json = args.smoke_json.expanduser().resolve()
    perf_json = args.perf_json.expanduser().resolve() if args.perf_json is not None else None
    preflight_arg = getattr(args, "preflight_json", None)
    preflight_json = preflight_arg.expanduser().resolve() if preflight_arg is not None else None
    artifact_manifest_arg = getattr(args, "artifact_manifest_json", None)
    artifact_manifest_json = (
        artifact_manifest_arg.expanduser().resolve()
        if artifact_manifest_arg is not None
        else None
    )
    artifact_load_ms = getattr(args, "artifact_load_ms", None)
    if artifact_load_ms is not None:
        require(
            isinstance(artifact_load_ms, int)
            and not isinstance(artifact_load_ms, bool)
            and artifact_load_ms >= 0,
            "--artifact-load-ms must be a non-negative integer",
        )

    bundle_manifest = load_json(bundle_manifest_path, "bundle manifest")
    smoke = load_json(smoke_json, "smoke JSON")
    validate_smoke(smoke, bundle_manifest)
    perf = load_json(perf_json, "perf JSON") if perf_json is not None else None
    preflight = load_json(preflight_json, "clean-host preflight JSON") if preflight_json is not None else None
    artifact_manifest = (
        load_json(artifact_manifest_json, "artifact manifest JSON")
        if artifact_manifest_json is not None
        else None
    )

    artifacts = {
        "bundle_manifest": copy_artifact(bundle_manifest_path, output_dir, "bundle-manifest.json"),
        "smoke_json": copy_artifact(smoke_json, output_dir, "smoke.json"),
    }
    if source_manifest_path.is_file():
        artifacts["source_manifest"] = copy_artifact(source_manifest_path, output_dir, "source-manifest.json")
    if perf_json is not None:
        assert perf is not None
        artifacts["perf_json"] = copy_artifact(perf_json, output_dir, "perf.json")
    if preflight_json is not None:
        assert preflight is not None
        artifacts["clean_host_preflight_json"] = copy_artifact(
            preflight_json,
            output_dir,
            "clean-host-preflight.json",
        )
    if artifact_manifest_json is not None:
        assert artifact_manifest is not None
        artifacts["artifact_manifest_json"] = copy_artifact(
            artifact_manifest_json,
            output_dir,
            "artifact-manifest.json",
        )

    apfs_path = (args.apfs_path or bundle_dir).expanduser().resolve()
    smoke_process_pid = smoke.get("process_pid")
    smoke_process_parent_pid = smoke.get("process_parent_pid")
    summary = {
        "schema_version": 1,
        "created_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "image_ref": args.image_ref,
        "bundle_dir": str(bundle_dir),
        "host": host_metadata(),
        "apfs": apfs_info(apfs_path),
        "build_commands": args.build_command,
        "bundle": {
            "kind": bundle_manifest.get("kind"),
            "manifest_schema_version": bundle_manifest.get("manifest_schema_version"),
            "platform": bundle_manifest.get("platform"),
            "source_image": bundle_manifest.get("source_image"),
            "source_digest": bundle_manifest.get("source_digest"),
            "root_disk_sha256": bundle_manifest.get("root_disk_sha256"),
            "kernel_sha256": bundle_manifest.get("kernel_sha256"),
            "initramfs_sha256": bundle_manifest.get("initramfs_sha256"),
            "expected_root": bundle_manifest.get("expected_root"),
            "expected_console": bundle_manifest.get("console"),
            "expected_pid1": bundle_manifest.get("expected_pid1"),
        },
        "smoke": {
            "ready": smoke.get("ready"),
            "failure_reason": smoke.get("failure_reason"),
            "timings_ms": smoke.get("timings"),
            "observed_root": smoke.get("observed_root"),
            "observed_pid1": smoke.get("observed_pid1"),
            "observed_consoles": smoke.get("observed_consoles"),
            "observed_network": smoke.get("observed_network"),
            "launcher_pid": smoke.get("launcher_pid"),
            "process_parent_pid": smoke_process_parent_pid,
            "process_pid": smoke_process_pid,
            "child_pid": smoke.get("child_pid", smoke_process_pid),
            "bundle_timings_ms": smoke.get("bundle", {}).get("timings_ms"),
            "apfs_clone_command": smoke.get("bundle", {}).get("apfs_clone_command"),
            "os_mode_command": smoke.get("bundle", {}).get("os_mode_command"),
            "smoke_command": smoke.get("bundle", {}).get("smoke_command"),
        },
        "perf": None,
        "clean_host_preflight": None,
        "artifact_manifest": None,
        "artifact": None,
        "artifacts": artifacts,
    }
    if artifact_manifest is not None:
        summary["artifact_manifest"] = {
            "kind": artifact_manifest.get("kind"),
            "digest_ref": artifact_manifest.get("digest_ref"),
            "image_tag": artifact_manifest.get("image_tag"),
            "runtime": artifact_manifest.get("runtime"),
        }
    if artifact_load_ms is not None:
        summary["artifact"] = {
            "load_ms": artifact_load_ms,
        }
    if preflight is not None:
        summary["clean_host_preflight"] = {
            "ok": preflight.get("ok"),
            "created_at_utc": preflight.get("created_at_utc"),
            "image_ref": preflight.get("image_ref"),
            "cache_entry": preflight.get("cache_entry"),
            "output_dir": preflight.get("output_dir"),
            "runtime": preflight.get("runtime"),
            "release_gate_command": preflight.get("release_gate_command"),
        }
    if perf is not None:
        perf_timings = perf.get("timings")
        if not isinstance(perf_timings, dict):
            perf_timings = {}
        summary["perf"] = {
            "failure_reason": perf.get("failure_reason"),
            "timings_ms": {
                key: perf.get(key, perf_timings.get(key))
                for key in ("first_kernel_log_ms", "first_output_ms", "root_ms", "pid1_ms", "console_ms", "ready_ms")
                if key in perf or key in perf_timings
            },
            "observed_root": perf.get("observed_root"),
            "observed_pid1": perf.get("observed_pid1"),
            "observed_consoles": perf.get("observed_consoles"),
            "observed_network": perf.get("observed_network"),
        }

    summary_path = output_dir / "release-evidence.json"
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return summary


def main() -> int:
    args = parse_args()
    try:
        summary = collect_release_evidence(args)
    except EvidenceError as err:
        print(err, file=sys.stderr)
        return 1
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
