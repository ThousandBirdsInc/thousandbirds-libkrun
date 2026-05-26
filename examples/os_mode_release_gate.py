#!/usr/bin/env python3
"""Run the macOS OS-bundle release gate for a digest-pinned image."""

import argparse
import json
import os
import platform
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import krun_os_run
import os_mode_baseline_table
import os_mode_collect_release_evidence
import os_mode_import_container_bundle as importer
import os_mode_verify_release_evidence


class ReleaseGateError(Exception):
    pass


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
            "Validate a digest-pinned libkrun OS bundle image on macOS/HVF, "
            "archive release evidence, and render the product baseline table."
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
            "Load and validate a libkrun.os-bundle.artifact.v1 JSON manifest "
            "before running the gate. The manifest must contain a digest_ref."
        ),
    )
    parser.add_argument("--output-dir", type=non_empty_path, required=True, help="Release evidence archive directory.")
    parser.add_argument(
        "--preflight-json",
        type=non_empty_path,
        default=None,
        help=(
            "Clean-host preflight JSON produced by os_mode_clean_host_preflight.py. "
            "Required with --clean-host-baseline."
        ),
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
        help="Container runtime used only for bundle extraction.",
    )
    parser.add_argument(
        "--build-command",
        action="append",
        default=[],
        type=non_empty_arg,
        help="Build or install command to record in release evidence. May be repeated.",
    )
    parser.add_argument(
        "--allow-existing-output-dir",
        action="store_true",
        help="Allow an existing empty output directory for release evidence.",
    )
    parser.add_argument(
        "--skip-pull",
        action="store_true",
        help="Do not explicitly pull IMAGE before extraction. Intended only for offline local dry runs.",
    )
    parser.add_argument(
        "--require-clean-cache",
        action="store_true",
        help="Require the derived bundle cache entry to be absent or empty before launch.",
    )
    parser.add_argument(
        "--require-cache-entry-absent",
        action="store_true",
        help=(
            "Require the derived bundle cache entry to be absent before launch. "
            "Use with --require-clean-cache for clean-host baseline evidence."
        ),
    )
    parser.add_argument(
        "--clean-host-baseline",
        action="store_true",
        help=(
            "Shortcut for clean-host baseline evidence: require absent cache "
            "entry, clean-cache preflight, APFS/macOS/arm64/perf evidence, and "
            "a pull phase for registry images."
        ),
    )
    return parser.parse_args()


def load_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file():
        raise ReleaseGateError(f"{label} does not exist or is not a file: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise ReleaseGateError(f"{label} is invalid JSON: {err}") from err
    if not isinstance(payload, dict):
        raise ReleaseGateError(f"{label} must be a JSON object")
    return payload


def cache_entry_for_image(image: str, cache_dir: Path | None, name: str | None) -> Path:
    cache_root = cache_dir.expanduser() if cache_dir is not None else krun_os_run.default_cache_root()
    entry_name = name if name is not None else krun_os_run.image_cache_name(image)
    return (cache_root / entry_name).resolve()


def require_digest_pinned(image: str) -> None:
    if not importer.image_reference_is_digest_pinned(image):
        raise ReleaseGateError("release gate requires a digest-pinned image reference: IMAGE@sha256:<digest>")


def command_json(command: list[str]) -> str:
    return json.dumps(command, separators=(",", ":"))


def run_command(command: list[str]) -> int:
    started = time.monotonic()
    proc = subprocess.run(command)
    elapsed_ms = int((time.monotonic() - started) * 1000)
    if proc.returncode != 0:
        raise ReleaseGateError(f"command failed with status {proc.returncode}: {importer.command_quote(command)}")
    return elapsed_ms


def artifact_archive_path(artifact_manifest_path: Path, artifact: dict[str, Any]) -> Path:
    archive = artifact.get("archive")
    if not isinstance(archive, dict):
        raise ReleaseGateError("artifact manifest must contain archive metadata")
    path_value = archive.get("path")
    if not isinstance(path_value, str) or path_value == "":
        raise ReleaseGateError("artifact manifest archive.path must be a non-empty string")
    path = Path(path_value).expanduser()
    if path.is_file():
        return path.resolve()
    fallback = artifact_manifest_path.parent / path.name
    if fallback.is_file():
        return fallback.resolve()
    raise ReleaseGateError(f"artifact archive does not exist: {path}")


def artifact_image_reference(artifact: dict[str, Any]) -> str:
    digest_ref = artifact.get("digest_ref")
    if not isinstance(digest_ref, str) or digest_ref == "":
        raise ReleaseGateError("artifact manifest must contain digest_ref for release-gate validation")
    require_digest_pinned(digest_ref)
    return digest_ref


def load_artifact_manifest(path: Path) -> tuple[dict[str, Any], Path]:
    manifest_path = path.expanduser().resolve()
    artifact = load_json(manifest_path, "artifact manifest")
    if artifact.get("kind") != "libkrun.os-bundle.artifact.v1":
        raise ReleaseGateError("artifact manifest kind must be libkrun.os-bundle.artifact.v1")
    archive_path = artifact_archive_path(manifest_path, artifact)
    archive = artifact.get("archive")
    assert isinstance(archive, dict)
    expected_sha = archive.get("sha256")
    if not isinstance(expected_sha, str) or expected_sha == "":
        raise ReleaseGateError("artifact manifest archive.sha256 must be a non-empty string")
    actual_sha = importer.sha256_file(archive_path)
    if actual_sha != expected_sha:
        raise ReleaseGateError(
            f"artifact archive SHA-256 mismatch: expected {expected_sha}, got {actual_sha}"
        )
    return artifact, archive_path


def artifact_load_command(artifact: dict[str, Any], archive_path: Path, runtime: str) -> list[str]:
    archive = artifact.get("archive")
    if not isinstance(archive, dict):
        raise ReleaseGateError("artifact manifest must contain archive metadata")
    command = archive.get("load_command")
    if isinstance(command, list) and len(command) >= 4 and all(isinstance(item, str) for item in command):
        result = list(command)
        if runtime != "auto":
            result[0] = runtime
        result[-1] = str(archive_path)
        return result
    selected_runtime = importer.choose_runtime(runtime)
    return [selected_runtime, "load", "-i", str(archive_path)]


def load_artifact_image(artifact_path: Path, runtime: str) -> tuple[dict[str, Any], list[str]]:
    artifact, archive_path = load_artifact_manifest(artifact_path)
    command = artifact_load_command(artifact, archive_path, runtime)
    run_command(command)
    return artifact, command


def cache_clean_report(cache_entry: Path) -> dict[str, Any]:
    if not cache_entry.exists():
        return {
            "path": str(cache_entry),
            "exists": False,
            "clean": True,
            "entries": [],
        }
    if not cache_entry.is_dir():
        return {
            "path": str(cache_entry),
            "exists": True,
            "clean": False,
            "entries": [cache_entry.name],
            "reason": "cache entry exists and is not a directory",
        }
    entries = sorted(path.name for path in cache_entry.iterdir())
    return {
        "path": str(cache_entry),
        "exists": True,
        "clean": len(entries) == 0,
        "entries": entries,
    }


def require_clean_cache_entry(cache_entry: Path) -> dict[str, Any]:
    report = cache_clean_report(cache_entry)
    if report.get("clean") is not True:
        entries = report.get("entries")
        raise ReleaseGateError(
            "--require-clean-cache requires the bundle cache entry to be absent or empty: "
            f"{cache_entry}; entries={entries}"
        )
    return report


def require_absent_cache_entry(cache_entry: Path) -> dict[str, Any]:
    report = require_clean_cache_entry(cache_entry)
    if report.get("exists") is not False:
        raise ReleaseGateError(
            "--require-cache-entry-absent requires the derived bundle cache entry "
            f"to be absent before launch: {cache_entry}"
        )
    return report


def importer_smoke_command(
    image: str,
    cache_entry: Path,
    runtime: str,
    launch_id: str,
    *,
    pull: bool,
) -> tuple[list[str], Path, Path, Path]:
    clone_name = f"release-vm-root-smoke-{launch_id}.raw"
    smoke_name = f"release-smoke-{launch_id}.json"
    bundle_dir = cache_entry / "libkrun-os-bundle"
    command = [
        sys.executable,
        str(importer.REPO_ROOT / "examples" / "os_mode_import_container_bundle.py"),
        "--image",
        image,
        "--output-dir",
        str(cache_entry),
        "--runtime",
        runtime,
        "--reuse-extracted-output-dir",
        "--strict-digest",
        "--clone-dest",
        clone_name,
        "--smoke-output",
        smoke_name,
        "--run",
    ]
    if pull:
        command.append("--pull")
    return command, bundle_dir, bundle_dir / clone_name, bundle_dir / smoke_name


def run_perf_gate(bundle_dir: Path, launch_id: str) -> tuple[Path, list[str], list[str]]:
    manifest = importer.validate_manifest(bundle_dir, strict_digest=True)
    clone_dest = (bundle_dir / f"release-vm-root-perf-{launch_id}.raw").resolve()
    perf_output = (bundle_dir / f"release-perf-{launch_id}.json").resolve()
    root_disk = importer.resolve_bundle_path(bundle_dir, manifest["root_disk"], "root_disk", [])
    protected = {
        "manifest": (bundle_dir / "manifest.json").resolve(),
        "root_disk": root_disk,
    }
    importer.validate_output_candidate("--clone-dest", clone_dest, protected)
    perf_protected = dict(protected)
    perf_protected["clone_dest"] = clone_dest
    importer.validate_output_candidate("--perf-output", perf_output, perf_protected)

    info = importer.apfs_info(bundle_dir)
    if info.get("is_apfs") is not True:
        raise ReleaseGateError(f"bundle directory must be on APFS for release gate perf clone: {info}")

    clone, _launch, _smoke, perf = importer.build_commands(
        bundle_dir,
        manifest,
        clone_dest,
        None,
        perf_output,
        require_launcher=True,
    )
    if perf is None:
        raise ReleaseGateError("internal error: importer did not build a perf command")
    run_command(clone)
    run_command(perf)
    return perf_output, clone, perf


def collect_evidence(
    bundle_dir: Path,
    smoke_json: Path,
    perf_json: Path,
    image: str,
    output_dir: Path,
    build_commands: list[str],
    allow_existing_output_dir: bool,
    preflight_json: Path | None,
    artifact_manifest_json: Path | None,
    artifact_load_ms: int | None,
) -> dict[str, Any]:
    return os_mode_collect_release_evidence.collect_release_evidence(
        argparse.Namespace(
            bundle_dir=bundle_dir,
            smoke_json=smoke_json,
            perf_json=perf_json,
            preflight_json=preflight_json,
            artifact_manifest_json=artifact_manifest_json,
            image_ref=image,
            output_dir=output_dir,
            build_command=build_commands,
            apfs_path=bundle_dir,
            allow_existing_output_dir=allow_existing_output_dir,
            artifact_load_ms=artifact_load_ms,
        )
    )


def write_baseline(output_dir: Path) -> Path:
    rows = os_mode_baseline_table.rows_from_release_evidence([output_dir], [])
    baseline = os_mode_baseline_table.markdown_table(rows)
    path = output_dir / "baseline.md"
    if path.exists():
        raise ReleaseGateError(f"baseline destination already exists: {path}")
    path.write_text(baseline, encoding="utf-8")
    return path


def write_gate_summary(
    output_dir: Path,
    image: str,
    cache_entry: Path,
    smoke_command: list[str],
    perf_clone_command: list[str],
    perf_command: list[str],
    baseline_path: Path,
    artifact_manifest: Path | None = None,
    artifact_load_command_value: list[str] | None = None,
    cache_preflight: dict[str, Any] | None = None,
    require_clean_cache: bool = False,
    require_cache_entry_absent: bool = False,
    clean_host_baseline: bool = False,
    preflight_json: Path | None = None,
    image_was_explicit: bool = True,
) -> Path:
    path = output_dir / "release-gate-summary.json"
    if path.exists():
        raise ReleaseGateError(f"release gate summary already exists: {path}")
    summary = {
        "schema_version": 1,
        "image_ref": image,
        "image_was_explicit": image_was_explicit,
        "cache_entry": str(cache_entry),
        "smoke_importer_command": smoke_command,
        "perf_clone_command": perf_clone_command,
        "perf_command": perf_command,
        "release_evidence": str(output_dir / "release-evidence.json"),
        "baseline_table": str(baseline_path),
        "artifact_manifest": str(artifact_manifest) if artifact_manifest is not None else None,
        "artifact_load_command": artifact_load_command_value,
        "cache_preflight": cache_preflight,
        "require_clean_cache": require_clean_cache,
        "require_cache_entry_absent": require_cache_entry_absent,
        "clean_host_baseline": clean_host_baseline,
        "preflight_json": str(preflight_json) if preflight_json is not None else None,
    }
    path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def verify_release_evidence_archive(
    output_dir: Path,
    *,
    require_clean_cache: bool,
    require_cache_entry_absent: bool,
    require_artifact: bool,
    require_pull: bool,
    require_clean_host_preflight: bool,
) -> dict[str, Any]:
    return os_mode_verify_release_evidence.verify_evidence(
        argparse.Namespace(
            evidence_dir=output_dir,
            require_clean_cache=require_clean_cache,
            require_cache_entry_absent=require_cache_entry_absent,
            require_artifact_manifest=require_artifact,
            require_artifact_load=require_artifact,
            require_apfs=True,
            require_macos_arm64=True,
            require_perf=True,
            require_clean_poweroff=True,
            require_pull=require_pull,
            require_clean_host_preflight=require_clean_host_preflight,
            require_build_provenance=require_clean_host_preflight,
        )
    )


def command_option_path(command: list[str], option: str, label: str) -> Path:
    option_count = command.count(option)
    if option_count == 0:
        raise ReleaseGateError(f"{label} is missing required option: {option}")
    if option_count > 1:
        raise ReleaseGateError(f"{label} repeats option: {option}")
    index = command.index(option)
    if index + 1 >= len(command):
        raise ReleaseGateError(f"{label} option {option} is missing a value")
    value = command[index + 1]
    if value == "":
        raise ReleaseGateError(f"{label} option {option} has an empty value")
    return Path(value).expanduser().resolve()


def command_optional_value(command: list[str], option: str, label: str) -> str | None:
    option_count = command.count(option)
    if option_count == 0:
        return None
    if option_count > 1:
        raise ReleaseGateError(f"{label} repeats option: {option}")
    index = command.index(option)
    if index + 1 >= len(command):
        raise ReleaseGateError(f"{label} option {option} is missing a value")
    value = command[index + 1]
    if value == "":
        raise ReleaseGateError(f"{label} option {option} has an empty value")
    return value


def command_optional_path(command: list[str], option: str, label: str) -> Path | None:
    value = command_optional_value(command, option, label)
    if value is None:
        return None
    return Path(value).expanduser().resolve()


def command_positional_args(command: list[str], label: str) -> list[str]:
    if not command:
        raise ReleaseGateError(f"{label} is empty")
    if Path(command[0]).name != "os_mode_release_gate.py":
        raise ReleaseGateError(f"{label} executable is not os_mode_release_gate.py")
    positionals: list[str] = []
    for item in command[1:]:
        if item.startswith("--"):
            break
        if item == "":
            raise ReleaseGateError(f"{label} has an empty positional argument")
        positionals.append(item)
    return positionals


def validate_release_gate_command_shape(command: list[str], label: str) -> None:
    value_options = {
        "--artifact-manifest",
        "--cache-dir",
        "--name",
        "--output-dir",
        "--preflight-json",
        "--runtime",
    }
    flag_options = {"--clean-host-baseline"}
    for option in value_options | flag_options:
        if command.count(option) > 1:
            raise ReleaseGateError(f"{label} repeats option: {option}")
    canonical_options = [
        "--artifact-manifest",
        "--output-dir",
        "--cache-dir",
        "--name",
        "--runtime",
        "--preflight-json",
        "--clean-host-baseline",
    ]
    observed_options: list[str] = []
    seen_options: set[str] = set()
    seen_option = False
    index = 1
    while index < len(command):
        item = command[index]
        if item == "":
            raise ReleaseGateError(f"{label} contains an empty argument")
        if item.startswith("--"):
            seen_option = True
            if item in seen_options:
                raise ReleaseGateError(f"{label} repeats option: {item}")
            if item in value_options:
                if index + 1 >= len(command) or command[index + 1] == "" or command[index + 1].startswith("--"):
                    raise ReleaseGateError(f"{label} option {item} is missing a value")
                seen_options.add(item)
                observed_options.append(item)
                index += 2
                continue
            if item in flag_options:
                if item == "--clean-host-baseline" and index != len(command) - 1:
                    raise ReleaseGateError(f"{label} must end with --clean-host-baseline")
                seen_options.add(item)
                observed_options.append(item)
                index += 1
                continue
            raise ReleaseGateError(f"{label} contains unexpected option: {item}")
        if seen_option:
            raise ReleaseGateError(f"{label} contains unexpected positional argument after options: {item}")
        index += 1
    canonical_positions = [canonical_options.index(option) for option in observed_options]
    if canonical_positions != sorted(canonical_positions):
        raise ReleaseGateError(f"{label} options are not in preflight-generated order")


def require_utc_timestamp(value: Any, label: str) -> None:
    if not isinstance(value, str) or value == "":
        raise ReleaseGateError(f"{label} is missing created_at_utc")
    try:
        time.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as err:
        raise ReleaseGateError(f"{label} created_at_utc must be an ISO 8601 UTC timestamp ending in Z") from err


def validate_clean_host_preflight(
    path: Path,
    *,
    image: str,
    cache_entry: Path,
    output_dir: Path,
    artifact_manifest: Path | None,
    runtime: str = "auto",
    image_was_explicit: bool = True,
) -> Path:
    preflight_path = path.expanduser().resolve()
    preflight = load_json(preflight_path, "clean-host preflight JSON")
    if preflight.get("schema_version") != 1:
        raise ReleaseGateError("clean-host preflight schema_version must be 1")
    if preflight.get("ok") is not True:
        raise ReleaseGateError("clean-host preflight JSON did not record ok=true")
    if preflight.get("errors") != []:
        raise ReleaseGateError("clean-host preflight JSON recorded errors")
    require_utc_timestamp(preflight.get("created_at_utc"), "clean-host preflight")
    if preflight.get("image_ref") != image:
        raise ReleaseGateError("clean-host preflight image_ref does not match release gate image")
    preflight_artifact = preflight.get("artifact_manifest")
    if artifact_manifest is None:
        if preflight_artifact is not None:
            raise ReleaseGateError("clean-host preflight recorded artifact manifest for registry release gate")
    else:
        if not isinstance(preflight_artifact, dict):
            raise ReleaseGateError("clean-host preflight JSON is missing artifact_manifest")
        if preflight_artifact.get("valid") is not True:
            raise ReleaseGateError("clean-host preflight artifact_manifest was not valid")
        expected_artifact = artifact_manifest.expanduser().resolve()
        if Path(str(preflight_artifact.get("path"))).expanduser().resolve() != expected_artifact:
            raise ReleaseGateError("clean-host preflight artifact_manifest path does not match release gate")
    preflight_cache = preflight.get("cache_entry")
    if not isinstance(preflight_cache, dict):
        raise ReleaseGateError("clean-host preflight JSON is missing cache_entry")
    if preflight_cache.get("path") != str(cache_entry):
        raise ReleaseGateError("clean-host preflight cache_entry path does not match release gate cache entry")
    if preflight_cache.get("exists") is not False or preflight_cache.get("clean") is not True:
        raise ReleaseGateError("clean-host preflight cache entry was not absent and clean")
    if preflight_cache.get("entries") != []:
        raise ReleaseGateError("clean-host preflight cache entry reported entries")
    preflight_output = preflight.get("output_dir")
    if not isinstance(preflight_output, dict):
        raise ReleaseGateError("clean-host preflight JSON is missing output_dir")
    if Path(str(preflight_output.get("path"))).expanduser().resolve() != output_dir:
        raise ReleaseGateError("clean-host preflight output_dir does not match release gate output directory")
    if preflight_output.get("exists") is not False or preflight_output.get("clean") is not True:
        raise ReleaseGateError("clean-host preflight output directory was not fresh")
    preflight_host = preflight.get("host")
    if not isinstance(preflight_host, dict):
        raise ReleaseGateError("clean-host preflight JSON is missing host metadata")
    if preflight_host.get("system") != "Darwin":
        raise ReleaseGateError("clean-host preflight was not collected on macOS/Darwin")
    if preflight_host.get("machine") != "arm64":
        raise ReleaseGateError("clean-host preflight was not collected on arm64")
    if not isinstance(preflight_host.get("macos"), dict):
        raise ReleaseGateError("clean-host preflight did not record macOS metadata")
    preflight_apfs = preflight.get("apfs")
    if not isinstance(preflight_apfs, list):
        raise ReleaseGateError("clean-host preflight JSON is missing APFS checks")
    apfs_by_label = {
        item.get("label"): item.get("info")
        for item in preflight_apfs
        if isinstance(item, dict) and isinstance(item.get("info"), dict)
    }
    for label in ("bundle_cache_entry", "release_evidence_output"):
        info = apfs_by_label.get(label)
        if not isinstance(info, dict) or info.get("is_apfs") is not True:
            raise ReleaseGateError(f"clean-host preflight APFS check failed for {label}")
    preflight_runtime = preflight.get("runtime")
    if not isinstance(preflight_runtime, dict):
        raise ReleaseGateError("clean-host preflight JSON is missing runtime")
    if preflight_runtime.get("requested") != runtime:
        raise ReleaseGateError("clean-host preflight runtime requested mode does not match release gate runtime")
    if not isinstance(preflight_runtime.get("selected"), str) or preflight_runtime["selected"] == "":
        raise ReleaseGateError("clean-host preflight runtime did not record a selected runtime")
    if preflight_runtime["selected"] not in ("docker", "podman"):
        raise ReleaseGateError("clean-host preflight runtime selected mode is invalid")
    if runtime in ("docker", "podman") and preflight_runtime["selected"] != runtime:
        raise ReleaseGateError("clean-host preflight runtime selected mode does not match release gate runtime")
    release_gate_command = preflight.get("release_gate_command")
    if not isinstance(release_gate_command, list) or not all(isinstance(item, str) for item in release_gate_command):
        raise ReleaseGateError("clean-host preflight release_gate_command must be a string list")
    if "--clean-host-baseline" not in release_gate_command:
        raise ReleaseGateError("clean-host preflight release_gate_command is missing --clean-host-baseline")
    for forbidden_option in ("--allow-existing-output-dir", "--skip-pull"):
        if forbidden_option in release_gate_command:
            raise ReleaseGateError(
                f"clean-host preflight release_gate_command must not include {forbidden_option}"
            )
    validate_release_gate_command_shape(release_gate_command, "clean-host preflight release_gate_command")
    if command_option_path(release_gate_command, "--preflight-json", "clean-host preflight release_gate_command") != preflight_path:
        raise ReleaseGateError("clean-host preflight release_gate_command --preflight-json does not match the preflight JSON path")
    if command_option_path(release_gate_command, "--output-dir", "clean-host preflight release_gate_command") != output_dir:
        raise ReleaseGateError("clean-host preflight release_gate_command --output-dir does not match release gate output directory")
    command_runtime = command_optional_value(
        release_gate_command,
        "--runtime",
        "clean-host preflight release_gate_command",
    ) or "auto"
    if command_runtime != runtime:
        raise ReleaseGateError("clean-host preflight release_gate_command --runtime does not match release gate runtime")
    command_cache_dir = command_optional_path(
        release_gate_command,
        "--cache-dir",
        "clean-host preflight release_gate_command",
    )
    if command_cache_dir is None:
        raise ReleaseGateError("clean-host preflight release_gate_command is missing --cache-dir")
    command_name = command_optional_value(
        release_gate_command,
        "--name",
        "clean-host preflight release_gate_command",
    )
    if cache_entry_for_image(image, command_cache_dir, command_name) != cache_entry:
        raise ReleaseGateError("clean-host preflight release_gate_command cache options do not match release gate cache entry")
    positional_args = command_positional_args(release_gate_command, "clean-host preflight release_gate_command")
    if artifact_manifest is None:
        if "--artifact-manifest" in release_gate_command:
            raise ReleaseGateError("clean-host preflight release_gate_command unexpectedly includes --artifact-manifest")
        if positional_args != [image]:
            raise ReleaseGateError("clean-host preflight release_gate_command registry image positional does not match release gate")
    else:
        expected_positionals = [image] if image_was_explicit else []
        if positional_args != expected_positionals:
            raise ReleaseGateError("clean-host preflight release_gate_command positional image does not match release gate invocation")
        if command_option_path(
            release_gate_command,
            "--artifact-manifest",
            "clean-host preflight release_gate_command",
        ) != artifact_manifest.expanduser().resolve():
            raise ReleaseGateError("clean-host preflight release_gate_command --artifact-manifest does not match release gate")
    return preflight_path


def run_release_gate(args: argparse.Namespace) -> dict[str, Any]:
    if args.clean_host_baseline:
        if args.allow_existing_output_dir:
            raise ReleaseGateError("--clean-host-baseline requires a fresh output directory")
        args.require_clean_cache = True
        args.require_cache_entry_absent = True
        if args.skip_pull and args.artifact_manifest is None:
            raise ReleaseGateError("--clean-host-baseline cannot be combined with --skip-pull for registry images")
        if args.preflight_json is None:
            raise ReleaseGateError("--clean-host-baseline requires --preflight-json from os_mode_clean_host_preflight.py")
    if args.require_cache_entry_absent and not args.require_clean_cache:
        raise ReleaseGateError("--require-cache-entry-absent requires --require-clean-cache")
    artifact = None
    artifact_archive = None
    artifact_load = None
    image_was_explicit = args.image is not None
    if args.artifact_manifest is not None:
        artifact, artifact_archive = load_artifact_manifest(args.artifact_manifest)
        artifact_image = artifact_image_reference(artifact)
        if args.image is None:
            args.image = artifact_image
        elif args.image != artifact_image:
            raise ReleaseGateError(f"IMAGE does not match artifact manifest digest_ref: {args.image} != {artifact_image}")
    if args.image is None:
        raise ReleaseGateError("image is required unless --artifact-manifest provides digest_ref")
    require_digest_pinned(args.image)
    cache_entry = cache_entry_for_image(args.image, args.cache_dir, args.name)
    output_dir = args.output_dir.expanduser().resolve()
    preflight_json = None
    if args.preflight_json is not None:
        preflight_json = validate_clean_host_preflight(
            args.preflight_json,
            image=args.image,
            cache_entry=cache_entry,
            output_dir=output_dir,
            artifact_manifest=args.artifact_manifest,
            runtime=args.runtime,
            image_was_explicit=image_was_explicit,
        )
    if args.require_cache_entry_absent:
        cache_preflight = require_absent_cache_entry(cache_entry)
    elif args.require_clean_cache:
        cache_preflight = require_clean_cache_entry(cache_entry)
    else:
        cache_preflight = cache_clean_report(cache_entry)
    artifact_load_ms = None
    if artifact is not None:
        assert artifact_archive is not None
        artifact_load = artifact_load_command(artifact, artifact_archive, args.runtime)
        artifact_load_ms = run_command(artifact_load)
    launch_id = f"{int(time.time())}-{platform.machine() or 'host'}-{os.getpid()}"
    smoke_command, bundle_dir, _smoke_clone, smoke_json = importer_smoke_command(
        args.image,
        cache_entry,
        args.runtime,
        launch_id,
        pull=not args.skip_pull and args.artifact_manifest is None,
    )
    run_command(smoke_command)
    perf_json, perf_clone_command, perf_command = run_perf_gate(bundle_dir, launch_id)
    evidence = collect_evidence(
        bundle_dir,
        smoke_json,
        perf_json,
        args.image,
        output_dir,
        args.build_command
        + (
            [f"artifact_load_command={command_json(artifact_load)}"]
            if artifact_load is not None
            else []
        )
        + [f"smoke_importer_command={command_json(smoke_command)}"],
        args.allow_existing_output_dir,
        preflight_json,
        args.artifact_manifest.expanduser().resolve()
        if args.artifact_manifest is not None
        else None,
        artifact_load_ms,
    )
    baseline_path = write_baseline(output_dir)
    summary_path = write_gate_summary(
        output_dir,
        args.image,
        cache_entry,
        smoke_command,
        perf_clone_command,
        perf_command,
        baseline_path,
        artifact_manifest=args.artifact_manifest.expanduser().resolve()
        if args.artifact_manifest is not None
        else None,
        artifact_load_command_value=artifact_load,
        cache_preflight=cache_preflight,
        require_clean_cache=args.require_clean_cache,
        require_cache_entry_absent=args.require_cache_entry_absent,
        clean_host_baseline=args.clean_host_baseline,
        preflight_json=preflight_json,
        image_was_explicit=image_was_explicit,
    )
    verification = verify_release_evidence_archive(
        output_dir,
        require_clean_cache=args.require_clean_cache,
        require_cache_entry_absent=args.require_cache_entry_absent,
        require_artifact=args.artifact_manifest is not None,
        require_pull=not args.skip_pull and args.artifact_manifest is None,
        require_clean_host_preflight=args.clean_host_baseline,
    )
    return {
        "release_evidence": str(output_dir / "release-evidence.json"),
        "baseline_table": str(baseline_path),
        "summary": str(summary_path),
        "verification": verification,
        "image_ref": args.image,
        "cache_entry": str(cache_entry),
        "cache_preflight": cache_preflight,
        "evidence": evidence,
    }


def main() -> int:
    args = parse_args()
    try:
        result = run_release_gate(args)
    except (
        ReleaseGateError,
        importer.BundleError,
        os_mode_collect_release_evidence.EvidenceError,
        os_mode_verify_release_evidence.VerifyError,
    ) as err:
        print(err, file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
