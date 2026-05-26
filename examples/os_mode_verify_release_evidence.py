#!/usr/bin/env python3
"""Verify archived macOS OS-mode release-gate evidence."""

import argparse
import datetime
import json
import sys
from pathlib import Path
from typing import Any

import krun_os_run
import os_mode_baseline_table
import os_mode_import_container_bundle as importer


class VerifyError(Exception):
    pass


EARLY_KERNEL_MARKERS = (
    "Booting Linux",
    "Linux version",
    "Kernel command line",
)

GENERATED_BUILD_COMMAND_PREFIXES = (
    "artifact_load_command=",
    "smoke_importer_command=",
)


def non_empty_path(value: str) -> Path:
    if value == "":
        raise argparse.ArgumentTypeError("path must be non-empty")
    return Path(value)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Verify release-evidence.json, release-gate-summary.json, copied "
            "artifacts, and clean-cache invariants for a macOS OS-bundle gate."
        )
    )
    parser.add_argument("evidence_dir", type=non_empty_path)
    parser.add_argument("--require-clean-cache", action="store_true")
    parser.add_argument("--require-cache-entry-absent", action="store_true")
    parser.add_argument("--require-artifact-manifest", action="store_true")
    parser.add_argument("--require-artifact-load", action="store_true")
    parser.add_argument("--require-apfs", action="store_true")
    parser.add_argument("--require-macos-arm64", action="store_true")
    parser.add_argument("--require-perf", action="store_true")
    parser.add_argument("--require-clean-poweroff", action="store_true")
    parser.add_argument("--require-pull", action="store_true")
    parser.add_argument("--require-clean-host-preflight", action="store_true")
    parser.add_argument("--require-build-provenance", action="store_true")
    return parser.parse_args()


def load_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file():
        raise VerifyError(f"{label} does not exist or is not a file: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise VerifyError(f"{label} is invalid JSON: {err}") from err
    if not isinstance(payload, dict):
        raise VerifyError(f"{label} must be a JSON object")
    return payload


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerifyError(message)


def positive_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


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


def archived_artifact_path(evidence_dir: Path, artifact: dict[str, Any], fallback_name: str) -> Path:
    archive_value = artifact.get("archive")
    if not isinstance(archive_value, str) or archive_value == "":
        raise VerifyError(f"artifact archive path for {fallback_name} must be a non-empty string")
    archive = Path(archive_value).expanduser()
    if archive.is_file():
        return archive.resolve()
    fallback = evidence_dir / fallback_name
    if fallback.is_file():
        return fallback.resolve()
    raise VerifyError(f"artifact archive for {fallback_name} does not exist: {archive}")


def verify_artifact(evidence_dir: Path, artifacts: dict[str, Any], key: str, fallback_name: str) -> Path:
    artifact = artifacts.get(key)
    if not isinstance(artifact, dict):
        raise VerifyError(f"release evidence is missing artifact {key}")
    path = archived_artifact_path(evidence_dir, artifact, fallback_name)
    expected_sha = artifact.get("sha256")
    require(isinstance(expected_sha, str) and expected_sha != "", f"artifact {key} is missing sha256")
    actual_sha = importer.sha256_file(path)
    require(actual_sha == expected_sha, f"artifact {key} SHA-256 mismatch: expected {expected_sha}, got {actual_sha}")
    expected_size = artifact.get("size_bytes")
    if expected_size is not None:
        require(isinstance(expected_size, int) and expected_size >= 0, f"artifact {key} size_bytes is invalid")
        require(path.stat().st_size == expected_size, f"artifact {key} size mismatch")
    return path


def artifact_manifest_archive_path(
    manifest_path: Path,
    artifact_manifest: dict[str, Any],
    manifest_source: Path | None,
) -> Path:
    archive = artifact_manifest.get("archive")
    require(isinstance(archive, dict), "artifact manifest is missing archive metadata")
    archive_value = archive.get("path")
    require(isinstance(archive_value, str) and archive_value != "", "artifact manifest archive.path is invalid")
    path = Path(archive_value).expanduser()
    if path.is_file():
        resolved = path.resolve()
    else:
        fallbacks = [manifest_path.parent / path.name]
        if manifest_source is not None:
            fallbacks.append(manifest_source.expanduser().resolve().parent / path.name)
        resolved = next((fallback.resolve() for fallback in fallbacks if fallback.is_file()), None)
        require(resolved is not None, f"artifact manifest archive does not exist: {path}")
    expected_sha = archive.get("sha256")
    require(isinstance(expected_sha, str) and expected_sha != "", "artifact manifest archive.sha256 is invalid")
    actual_sha = importer.sha256_file(resolved)
    require(actual_sha == expected_sha, f"artifact manifest archive SHA-256 mismatch: expected {expected_sha}, got {actual_sha}")
    expected_size = archive.get("size_bytes")
    if expected_size is not None:
        require(isinstance(expected_size, int) and expected_size >= 0, "artifact manifest archive.size_bytes is invalid")
        require(resolved.stat().st_size == expected_size, "artifact manifest archive size mismatch")
    return resolved


def require_command_items(command: Any, items: tuple[str, ...], label: str) -> None:
    require(isinstance(command, list) and all(isinstance(item, str) for item in command), f"{label} must be a string list")
    missing = [item for item in items if item not in command]
    require(not missing, f"{label} is missing required items: {missing}")


def verify_optional_design_doc_command_items(command: Any, label: str) -> None:
    require(isinstance(command, list) and all(isinstance(item, str) for item in command), f"{label} must be a string list")
    design_doc_items = (
        "--design-doc-output",
        "DESIGN_DOC_SNIPPET_MD",
        "--evidence-label",
        "RELEASE_EVIDENCE_LABEL",
        "--final-release-baseline",
    )
    if any(item in command for item in design_doc_items):
        missing = [item for item in design_doc_items if item not in command]
        require(not missing, f"{label} has incomplete design-doc output items: {missing}")


def require_command_executable_name(command: Any, expected: str, label: str) -> None:
    require(isinstance(command, list) and all(isinstance(item, str) for item in command), f"{label} must be a string list")
    require(command, f"{label} is empty")
    require(Path(command[0]).name == expected, f"{label} executable is not {expected}")


def require_release_gate_command_shape(command: Any, label: str) -> None:
    require(isinstance(command, list) and all(isinstance(item, str) for item in command), f"{label} must be a string list")
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
        require(command.count(option) <= 1, f"{label} repeats option: {option}")
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
        require(item != "", f"{label} contains an empty argument")
        if item.startswith("--"):
            seen_option = True
            require(item not in seen_options, f"{label} repeats option: {item}")
            if item in value_options:
                require(index + 1 < len(command), f"{label} option {item} is missing a value")
                value = command[index + 1]
                require(value != "" and not value.startswith("--"), f"{label} option {item} is missing a value")
                seen_options.add(item)
                observed_options.append(item)
                index += 2
                continue
            if item in flag_options:
                if item == "--clean-host-baseline":
                    require(index == len(command) - 1, f"{label} must end with --clean-host-baseline")
                seen_options.add(item)
                observed_options.append(item)
                index += 1
                continue
            raise VerifyError(f"{label} contains unexpected option: {item}")
        require(not seen_option, f"{label} contains unexpected positional argument after options: {item}")
        index += 1
    canonical_positions = [canonical_options.index(option) for option in observed_options]
    require(canonical_positions == sorted(canonical_positions), f"{label} options are not in preflight-generated order")


def require_string_list(value: Any, label: str) -> list[str]:
    require(isinstance(value, list) and all(isinstance(item, str) for item in value), f"{label} must be a string list")
    return value


def require_command_option_path(command: Any, option: str, expected: Path, label: str) -> None:
    require(isinstance(command, list) and all(isinstance(item, str) for item in command), f"{label} must be a string list")
    option_count = command.count(option)
    require(option_count > 0, f"{label} is missing required option: {option}")
    require(option_count == 1, f"{label} repeats option: {option}")
    index = command.index(option)
    require(index + 1 < len(command), f"{label} option {option} is missing a value")
    require(
        Path(command[index + 1]).expanduser().resolve() == expected.expanduser().resolve(),
        f"{label} option {option} does not match expected path",
    )


def require_command_option_value(command: Any, option: str, expected: str, label: str) -> None:
    require(isinstance(command, list) and all(isinstance(item, str) for item in command), f"{label} must be a string list")
    option_count = command.count(option)
    require(option_count > 0, f"{label} is missing required option: {option}")
    require(option_count == 1, f"{label} repeats option: {option}")
    index = command.index(option)
    require(index + 1 < len(command), f"{label} option {option} is missing a value")
    require(command[index + 1] == expected, f"{label} option {option} does not match expected value")


def command_optional_value(command: Any, option: str, label: str) -> str | None:
    require(isinstance(command, list) and all(isinstance(item, str) for item in command), f"{label} must be a string list")
    option_count = command.count(option)
    if option_count == 0:
        return None
    require(option_count == 1, f"{label} repeats option: {option}")
    index = command.index(option)
    require(index + 1 < len(command), f"{label} option {option} is missing a value")
    value = command[index + 1]
    require(value != "", f"{label} option {option} has an empty value")
    return value


def require_command_option_basename(command: Any, option: str, expected_source: Any, label: str) -> None:
    require(isinstance(expected_source, str) and expected_source != "", f"{label} expected source for {option} is missing")
    require(isinstance(command, list) and all(isinstance(item, str) for item in command), f"{label} must be a string list")
    option_count = command.count(option)
    require(option_count > 0, f"{label} is missing required option: {option}")
    require(option_count == 1, f"{label} repeats option: {option}")
    index = command.index(option)
    require(index + 1 < len(command), f"{label} option {option} is missing a value")
    require(
        Path(command[index + 1]).name == Path(expected_source).name,
        f"{label} option {option} does not match expected artifact source",
    )


def verify_command_image_refs(command: Any, expected_image: Any, *, required: bool, label: str) -> None:
    require(isinstance(expected_image, str) and expected_image != "", "release evidence image_ref is missing")
    require(isinstance(command, list) and all(isinstance(item, str) for item in command), f"{label} must be a string list")
    image_refs = [item for item in command if importer.image_reference_is_digest_pinned(item)]
    if required:
        require(expected_image in image_refs, f"{label} is missing release image_ref")
    unexpected = [item for item in image_refs if item != expected_image]
    require(not unexpected, f"{label} contains unexpected image_ref values: {unexpected}")


def command_positional_args(command: Any, label: str) -> list[str]:
    require(isinstance(command, list) and all(isinstance(item, str) for item in command), f"{label} must be a string list")
    require(command, f"{label} is empty")
    positionals: list[str] = []
    for item in command[1:]:
        if item.startswith("--"):
            break
        require(item != "", f"{label} has an empty positional argument")
        positionals.append(item)
    return positionals


def parse_utc_timestamp(value: Any, label: str) -> datetime.datetime:
    require(isinstance(value, str) and value != "", f"{label} is missing created_at_utc")
    try:
        parsed = datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as err:
        raise VerifyError(f"{label} created_at_utc must be an ISO 8601 UTC timestamp ending in Z") from err
    return parsed.replace(tzinfo=datetime.UTC)


def require_summary_path(summary: dict[str, Any], key: str, expected: Path) -> None:
    value = summary.get(key)
    require(isinstance(value, str) and value != "", f"release-gate summary is missing {key}")
    require(Path(value).expanduser().resolve() == expected, f"release-gate summary {key} does not match archive")


def verify_summary_paths(evidence_dir: Path, summary: dict[str, Any]) -> None:
    require_summary_path(summary, "release_evidence", evidence_dir / "release-evidence.json")
    require_summary_path(summary, "baseline_table", evidence_dir / "baseline.md")


def verify_clean_cache(summary: dict[str, Any], require_absent: bool) -> None:
    require(summary.get("require_clean_cache") is True, "release-gate summary did not require a clean cache")
    if require_absent:
        require(
            summary.get("require_cache_entry_absent") is True,
            "release-gate summary did not require an absent cache entry",
        )
    preflight = summary.get("cache_preflight")
    require(isinstance(preflight, dict), "release-gate summary is missing cache_preflight")
    require(preflight.get("clean") is True, "cache_preflight.clean is not true")
    entries = preflight.get("entries")
    require(isinstance(entries, list), "cache_preflight.entries must be a list")
    if require_absent:
        require(preflight.get("exists") is False, "cache entry existed before the clean-host gate")
        require(entries == [], "absent cache entry must not report entries")


def verify_clean_host_preflight(
    evidence_dir: Path,
    evidence: dict[str, Any],
    summary: dict[str, Any],
    artifacts: dict[str, Any],
    *,
    require_absent: bool,
    require_apfs: bool,
    require_macos_arm64: bool,
) -> None:
    path = verify_artifact(
        evidence_dir,
        artifacts,
        "clean_host_preflight_json",
        "clean-host-preflight.json",
    )
    preflight = load_json(path, "archived clean-host preflight JSON")
    require(summary.get("clean_host_baseline") is True, "release-gate summary did not record clean_host_baseline=true")
    summary_preflight = summary.get("preflight_json")
    require(isinstance(summary_preflight, str) and summary_preflight != "", "summary is missing preflight_json")
    artifact = artifacts.get("clean_host_preflight_json")
    require(isinstance(artifact, dict), "release evidence is missing clean-host preflight artifact metadata")
    source = artifact.get("source")
    require(isinstance(source, str) and source != "", "clean-host preflight artifact is missing source")
    require(
        Path(summary_preflight).expanduser().resolve() == Path(source).expanduser().resolve(),
        "summary preflight_json does not match clean-host preflight artifact source",
    )
    require(preflight.get("schema_version") == 1, "clean-host preflight schema_version must be 1")
    require(preflight.get("ok") is True, "clean-host preflight did not record ok=true")
    require(preflight.get("errors") == [], "clean-host preflight recorded errors")
    require(preflight.get("image_ref") == evidence.get("image_ref"), "preflight image_ref does not match release evidence")
    image_was_explicit = summary.get("image_was_explicit")
    require(isinstance(image_was_explicit, bool), "summary image_was_explicit must be a boolean")
    preflight_artifact = preflight.get("artifact_manifest")
    summary_artifact = summary.get("artifact_manifest")
    if summary_artifact is None:
        require(preflight_artifact is None, "preflight recorded artifact_manifest for registry release evidence")
    else:
        require(isinstance(summary_artifact, str) and summary_artifact != "", "summary artifact_manifest is invalid")
        require(isinstance(preflight_artifact, dict), "preflight is missing artifact_manifest")
        require(preflight_artifact.get("valid") is True, "preflight artifact_manifest.valid is not true")
        require(
            preflight_artifact.get("digest_ref") == evidence.get("image_ref"),
            "preflight artifact_manifest digest_ref does not match release evidence",
        )
        require(
            Path(str(preflight_artifact.get("path"))).expanduser().resolve()
            == Path(summary_artifact).expanduser().resolve(),
            "preflight artifact_manifest path does not match summary",
        )
    preflight_created = parse_utc_timestamp(preflight.get("created_at_utc"), "preflight")
    evidence_created = parse_utc_timestamp(evidence.get("created_at_utc"), "release evidence")
    require(
        preflight_created <= evidence_created,
        "preflight created_at_utc is after release evidence created_at_utc",
    )

    preflight_cache = preflight.get("cache_entry")
    require(isinstance(preflight_cache, dict), "preflight is missing cache_entry")
    summary_cache_path = summary.get("cache_entry")
    require(isinstance(summary_cache_path, str) and summary_cache_path != "", "summary is missing cache_entry")
    require(preflight_cache.get("path") == summary_cache_path, "preflight cache_entry path does not match summary")
    require(preflight_cache.get("clean") is True, "preflight cache_entry.clean is not true")
    preflight_entries = preflight_cache.get("entries")
    require(isinstance(preflight_entries, list), "preflight cache_entry.entries must be a list")
    if require_absent:
        require(preflight_cache.get("exists") is False, "preflight cache entry existed before the clean-host gate")
        require(preflight_entries == [], "preflight absent cache entry must not report entries")

    preflight_output = preflight.get("output_dir")
    require(isinstance(preflight_output, dict), "preflight is missing output_dir")
    require(Path(str(preflight_output.get("path"))).expanduser().resolve() == evidence_dir, "preflight output_dir does not match evidence_dir")
    require(preflight_output.get("exists") is False, "preflight output_dir existed before the clean-host gate")
    require(preflight_output.get("clean") is True, "preflight output_dir.clean is not true")

    release_gate_command = preflight.get("release_gate_command")
    require_command_items(
        release_gate_command,
        ("--clean-host-baseline", "--preflight-json"),
        "preflight release gate command",
    )
    require_command_executable_name(
        release_gate_command,
        "os_mode_release_gate.py",
        "preflight release gate command",
    )
    for forbidden_option in ("--allow-existing-output-dir", "--skip-pull"):
        require(
            forbidden_option not in release_gate_command,
            f"preflight release gate command must not include {forbidden_option}",
        )
    require_release_gate_command_shape(
        release_gate_command,
        "preflight release gate command",
    )
    positional_args = command_positional_args(release_gate_command, "preflight release gate command")
    verify_command_image_refs(
        release_gate_command,
        evidence.get("image_ref"),
        required=summary.get("artifact_manifest") is None,
        label="preflight release gate command",
    )
    require_command_option_path(
        release_gate_command,
        "--output-dir",
        evidence_dir,
        "preflight release gate command",
    )
    require_command_option_path(
        release_gate_command,
        "--preflight-json",
        Path(source),
        "preflight release gate command",
    )
    if summary.get("artifact_manifest") is not None:
        expected_positionals = [evidence.get("image_ref")] if image_was_explicit else []
        require(
            positional_args == expected_positionals,
            "preflight release gate command positional image does not match summary invocation",
        )
        require_command_option_path(
            release_gate_command,
            "--artifact-manifest",
            Path(str(summary.get("artifact_manifest"))),
            "preflight release gate command",
        )
    else:
        require(image_was_explicit is True, "registry release evidence must record image_was_explicit=true")
        require(
            positional_args == [evidence.get("image_ref")],
            "preflight release gate command registry image positional does not match release evidence",
        )
        require("--artifact-manifest" not in release_gate_command, "preflight release gate command unexpectedly includes --artifact-manifest")

    runtime = preflight.get("runtime")
    require(isinstance(runtime, dict), "preflight is missing runtime")
    require(isinstance(runtime.get("selected"), str) and runtime["selected"] != "", "preflight did not select a runtime")
    require(runtime["selected"] in ("docker", "podman"), "preflight selected runtime is invalid")
    requested_runtime = runtime.get("requested")
    require(isinstance(requested_runtime, str) and requested_runtime != "", "preflight runtime requested mode is missing")
    require(
        requested_runtime in ("auto", "docker", "podman"),
        "preflight requested runtime is invalid",
    )
    if requested_runtime in ("docker", "podman"):
        require(
            runtime["selected"] == requested_runtime,
            "preflight selected runtime does not match requested runtime",
        )
    command_runtime = command_optional_value(release_gate_command, "--runtime", "preflight release gate command") or "auto"
    require(command_runtime == requested_runtime, "preflight release gate command runtime does not match preflight runtime")

    command_cache_dir = command_optional_value(release_gate_command, "--cache-dir", "preflight release gate command")
    require(command_cache_dir is not None, "preflight release gate command is missing --cache-dir")
    require(
        Path(command_cache_dir).expanduser().resolve() == Path(summary_cache_path).expanduser().resolve().parent,
        "preflight release gate command cache dir does not match summary cache entry",
    )
    command_cache_name = command_optional_value(release_gate_command, "--name", "preflight release gate command")
    expected_cache_name = krun_os_run.image_cache_name(str(evidence.get("image_ref")))
    if command_cache_name is not None:
        require(
            command_cache_name == Path(summary_cache_path).name,
            "preflight release gate command cache name does not match summary cache entry",
        )
    else:
        require(
            Path(summary_cache_path).name == expected_cache_name,
            "preflight release gate command omitted --name for a non-default cache entry",
        )

    if require_apfs:
        apfs_checks = preflight.get("apfs")
        require(isinstance(apfs_checks, list), "preflight is missing APFS checks")
        labels = {
            item.get("label"): item.get("info")
            for item in apfs_checks
            if isinstance(item, dict) and isinstance(item.get("info"), dict)
        }
        for label in ("bundle_cache_entry", "release_evidence_output"):
            info = labels.get(label)
            require(isinstance(info, dict) and info.get("is_apfs") is True, f"preflight APFS check failed for {label}")

    if require_macos_arm64:
        host = preflight.get("host")
        require(isinstance(host, dict), "preflight is missing host metadata")
        require(host.get("system") == "Darwin", "preflight was not collected on macOS/Darwin")
        require(host.get("machine") == "arm64", "preflight was not collected on arm64")


def verify_artifact_manifest(
    evidence_dir: Path,
    evidence: dict[str, Any],
    summary: dict[str, Any],
    artifacts: dict[str, Any],
) -> tuple[dict[str, Any], Path]:
    path = verify_artifact(
        evidence_dir,
        artifacts,
        "artifact_manifest_json",
        "artifact-manifest.json",
    )
    artifact_manifest = load_json(path, "archived artifact manifest JSON")
    require(artifact_manifest.get("kind") == "libkrun.os-bundle.artifact.v1", "artifact manifest kind is invalid")
    require(
        artifact_manifest.get("digest_ref") == evidence.get("image_ref"),
        "artifact manifest digest_ref does not match release evidence image_ref",
    )
    summary_artifact = summary.get("artifact_manifest")
    require(isinstance(summary_artifact, str) and summary_artifact != "", "summary is missing artifact_manifest")
    artifact_meta = artifacts.get("artifact_manifest_json")
    require(isinstance(artifact_meta, dict), "release evidence is missing artifact manifest metadata")
    source = artifact_meta.get("source")
    require(isinstance(source, str) and source != "", "artifact manifest metadata is missing source")
    archive_path = artifact_manifest_archive_path(path, artifact_manifest, Path(source))
    require(
        Path(summary_artifact).expanduser().resolve() == Path(source).expanduser().resolve(),
        "summary artifact_manifest does not match archived artifact manifest source",
    )
    evidence_summary = evidence.get("artifact_manifest")
    require(isinstance(evidence_summary, dict), "release evidence is missing artifact_manifest summary")
    require(evidence_summary.get("digest_ref") == evidence.get("image_ref"), "release evidence artifact_manifest digest_ref mismatch")
    commands = artifact_manifest.get("commands")
    require(isinstance(commands, dict), "artifact manifest is missing commands")
    baseline = commands.get("clean_host_baseline")
    require_command_items(
        baseline,
        (
            "examples/os_mode_clean_host_baseline.py",
            "--preflight-json",
            "CLEAN_HOST_PREFLIGHT_JSON",
            "--accept-json-output",
            "ACCEPTANCE_JSON",
            "--accept-table-output",
            "ACCEPTED_BASELINE_MD",
        ),
        "artifact manifest clean_host_baseline command",
    )
    verify_optional_design_doc_command_items(
        baseline,
        "artifact manifest clean_host_baseline command",
    )
    baseline_from_artifact = commands.get("clean_host_baseline_from_artifact")
    require_command_items(
        baseline_from_artifact,
        (
            "examples/os_mode_clean_host_baseline.py",
            "--artifact-manifest",
            "ARTIFACT_MANIFEST",
            "--preflight-json",
            "CLEAN_HOST_PREFLIGHT_JSON",
            "--accept-json-output",
            "ACCEPTANCE_JSON",
            "--accept-table-output",
            "ACCEPTED_BASELINE_MD",
        ),
        "artifact manifest clean_host_baseline_from_artifact command",
    )
    verify_optional_design_doc_command_items(
        baseline_from_artifact,
        "artifact manifest clean_host_baseline_from_artifact command",
    )
    return artifact_manifest, archive_path


def verify_artifact_load_command(summary: dict[str, Any], archive_path: Path) -> None:
    command = summary.get("artifact_load_command")
    require_command_items(command, ("load", "-i"), "artifact load command")
    require_command_option_path(command, "-i", archive_path, "artifact load command")


def verify_artifact_load(evidence: dict[str, Any], summary: dict[str, Any], archive_path: Path) -> None:
    verify_artifact_load_command(summary, archive_path)
    artifact = evidence.get("artifact")
    require(isinstance(artifact, dict), "release evidence is missing artifact load summary")
    load_ms = artifact.get("load_ms")
    require(
        isinstance(load_ms, int) and not isinstance(load_ms, bool) and load_ms >= 0,
        "release evidence artifact load_ms is missing or invalid",
    )


def generated_build_command(build_commands: list[str], prefix: str) -> list[str]:
    matches = [command.removeprefix(prefix) for command in build_commands if command.startswith(prefix)]
    require(len(matches) == 1, f"release evidence build_commands must include exactly one {prefix} entry")
    try:
        parsed = json.loads(matches[0])
    except json.JSONDecodeError as err:
        raise VerifyError(f"release evidence {prefix} entry is invalid JSON: {err}") from err
    require(
        isinstance(parsed, list) and all(isinstance(item, str) for item in parsed),
        f"release evidence {prefix} entry must decode to a string list",
    )
    return parsed


def verify_build_provenance(
    evidence: dict[str, Any],
    summary: dict[str, Any],
    *,
    require_artifact_load: bool,
) -> None:
    build_commands = require_string_list(evidence.get("build_commands"), "release evidence build_commands")
    user_build_commands = [
        command
        for command in build_commands
        if not command.startswith(GENERATED_BUILD_COMMAND_PREFIXES)
    ]
    require(user_build_commands, "release evidence build_commands is missing a caller-supplied build command")
    require(all(command != "" for command in user_build_commands), "release evidence build_commands contains an empty build command")

    smoke_importer_command = generated_build_command(build_commands, "smoke_importer_command=")
    require(
        smoke_importer_command == summary.get("smoke_importer_command"),
        "release evidence smoke_importer_command build provenance does not match release-gate summary",
    )
    if require_artifact_load:
        artifact_load_command = generated_build_command(build_commands, "artifact_load_command=")
        require(
            artifact_load_command == summary.get("artifact_load_command"),
            "release evidence artifact_load_command build provenance does not match release-gate summary",
        )


def verify_runtime_markers(evidence: dict[str, Any], smoke: dict[str, Any], bundle_manifest: dict[str, Any]) -> None:
    bundle = evidence.get("bundle")
    require(isinstance(bundle, dict), "release evidence is missing bundle summary")
    expected_root = bundle.get("expected_root")
    expected_console = bundle.get("expected_console")
    expected_pid1 = bundle.get("expected_pid1")
    for key in (
        "kind",
        "manifest_schema_version",
        "platform",
        "source_image",
        "source_digest",
        "root_disk_sha256",
        "kernel_sha256",
        "initramfs_sha256",
    ):
        require(bundle.get(key) == bundle_manifest.get(key), f"evidence bundle {key} does not match bundle manifest")
    require(expected_root == bundle_manifest.get("expected_root"), "evidence expected_root does not match bundle manifest")
    require(expected_console == bundle_manifest.get("console"), "evidence expected_console does not match bundle manifest")
    require(expected_pid1 == bundle_manifest.get("expected_pid1"), "evidence expected_pid1 does not match bundle manifest")

    smoke_summary = evidence.get("smoke")
    require(isinstance(smoke_summary, dict), "release evidence is missing smoke summary")
    require(smoke_summary.get("ready") is True, "smoke summary did not record ready=true")
    require(smoke_summary.get("failure_reason") is None, "smoke summary recorded a failure")
    require(smoke_summary.get("observed_root") == expected_root, "smoke observed_root mismatch")
    require(smoke_summary.get("observed_pid1") == expected_pid1, "smoke observed_pid1 mismatch")
    require(smoke_summary.get("observed_pid1") != "init.krun", "smoke observed init.krun as PID 1")
    consoles = smoke_summary.get("observed_consoles")
    require(isinstance(consoles, list) and expected_console in consoles, "smoke did not observe the expected console")
    require(smoke.get("ready") is True, "archived smoke JSON did not record ready=true")
    require(smoke.get("failure_reason") is None, "archived smoke JSON recorded a failure")
    require(smoke.get("observed_root") == expected_root, "archived smoke observed_root mismatch")
    require(smoke.get("observed_pid1") == expected_pid1, "archived smoke observed_pid1 mismatch")
    archived_consoles = smoke.get("observed_consoles")
    require(isinstance(archived_consoles, list) and expected_console in archived_consoles, "archived smoke did not observe the expected console")
    require(archived_consoles == consoles, "archived smoke observed_consoles mismatch")
    require(smoke.get("observed_network") == smoke_summary.get("observed_network"), "archived smoke observed_network mismatch")
    smoke_timings = smoke.get("timings")
    require(isinstance(smoke_timings, dict), "archived smoke JSON is missing timings")
    launcher_pid = smoke.get("launcher_pid")
    process_parent_pid = smoke.get("process_parent_pid")
    process_pid = smoke.get("process_pid")
    require(positive_int(launcher_pid), "archived smoke JSON is missing launcher_pid")
    require(positive_int(process_parent_pid), "archived smoke JSON is missing process_parent_pid")
    require(positive_int(process_pid), "archived smoke JSON is missing process_pid")
    require(process_parent_pid == launcher_pid, "archived smoke process parent does not match launcher_pid")
    require(process_pid != launcher_pid, "archived smoke process_pid must differ from launcher_pid")
    require(smoke_summary.get("launcher_pid") == launcher_pid, "smoke launcher_pid mismatch")
    require(smoke_summary.get("process_parent_pid") == process_parent_pid, "smoke process_parent_pid mismatch")
    require(smoke_summary.get("process_pid") == process_pid, "smoke process_pid mismatch")
    if smoke_summary.get("child_pid") is not None:
        require(smoke_summary.get("child_pid") == process_pid, "smoke child_pid mismatch")
    output_lines = smoke.get("output_lines")
    require(
        isinstance(output_lines, list)
        and all(isinstance(line, str) for line in output_lines)
        and any(is_early_kernel_line(line) for line in output_lines),
        "archived smoke JSON does not include an early kernel boot log line",
    )
    summary_timings = smoke_summary.get("timings_ms")
    require(isinstance(summary_timings, dict), "smoke summary is missing timings")
    for key in ("first_kernel_log_ms", "root_ms", "pid1_ms", "console_ms", "ready_ms"):
        value = summary_timings.get(key)
        require(isinstance(value, int) and value >= 0, f"smoke timing {key} is missing or invalid")
        require(smoke_timings.get(key) == value, f"archived smoke timing {key} does not match release evidence")


def verify_smoke_commands(evidence: dict[str, Any], smoke: dict[str, Any], bundle_manifest: dict[str, Any]) -> None:
    smoke_summary = evidence.get("smoke")
    require(isinstance(smoke_summary, dict), "release evidence is missing smoke summary")
    smoke_bundle = smoke.get("bundle")
    require(isinstance(smoke_bundle, dict), "archived smoke JSON is missing bundle metadata")
    evidence_bundle = evidence.get("bundle")
    require(isinstance(evidence_bundle, dict), "release evidence is missing bundle summary")
    image_ref = evidence.get("image_ref")
    require(isinstance(image_ref, str) and image_ref != "", "release evidence is missing image_ref")
    bundle_dir = evidence.get("bundle_dir")
    require(isinstance(bundle_dir, str) and bundle_dir != "", "release evidence is missing bundle_dir")

    archived_clone = require_string_list(smoke_bundle.get("apfs_clone_command"), "archived smoke APFS clone command")
    archived_launch = require_string_list(smoke_bundle.get("os_mode_command"), "archived smoke os_mode command")
    archived_smoke = require_string_list(smoke_bundle.get("smoke_command"), "archived smoke command")
    for key, archived in (
        ("apfs_clone_command", archived_clone),
        ("os_mode_command", archived_launch),
        ("smoke_command", archived_smoke),
    ):
        summary_command = require_string_list(smoke_summary.get(key), f"release evidence smoke {key}")
        require(summary_command == archived, f"release evidence smoke {key} does not match archived smoke JSON")

    require(len(archived_clone) >= 3, "archived smoke APFS clone command must include helper, source, and destination")
    require(Path(archived_clone[0]).name == "os_mode_apfs_clone.sh", "archived smoke APFS clone command must use os_mode_apfs_clone.sh")
    root_disk = bundle_manifest.get("root_disk")
    require(isinstance(root_disk, str) and root_disk != "", "bundle manifest root_disk is missing")
    root_disk_sha256 = bundle_manifest.get("root_disk_sha256")
    require(isinstance(root_disk_sha256, str) and root_disk_sha256 != "", "bundle manifest root_disk_sha256 is missing")
    archived_root_disk = smoke_bundle.get("root_disk")
    require(isinstance(archived_root_disk, str) and archived_root_disk != "", "archived smoke bundle root_disk is missing")
    archived_clone_dest = smoke_bundle.get("clone_dest")
    require(isinstance(archived_clone_dest, str) and archived_clone_dest != "", "archived smoke bundle clone_dest is missing")
    archived_bundle_dir = smoke_bundle.get("bundle_dir")
    require(isinstance(archived_bundle_dir, str) and archived_bundle_dir != "", "archived smoke bundle_dir is missing")
    require(smoke_bundle.get("kind") == bundle_manifest.get("kind"), "archived smoke bundle kind mismatch")
    require(
        smoke_bundle.get("manifest_schema_version") == bundle_manifest.get("manifest_schema_version"),
        "archived smoke bundle manifest_schema_version mismatch",
    )
    require(smoke_bundle.get("platform") == bundle_manifest.get("platform"), "archived smoke bundle platform mismatch")
    require(smoke_bundle.get("source_image") == bundle_manifest.get("source_image"), "archived smoke bundle source_image mismatch")
    require(smoke_bundle.get("source_digest") == bundle_manifest.get("source_digest"), "archived smoke bundle source_digest mismatch")
    require(
        smoke_bundle.get("root_disk_sha256") == root_disk_sha256,
        "archived smoke bundle root_disk_sha256 mismatch",
    )
    require(smoke_bundle.get("imported_image") == image_ref, "archived smoke bundle imported_image mismatch")
    require(
        Path(archived_bundle_dir).expanduser().resolve() == Path(bundle_dir).expanduser().resolve(),
        "archived smoke bundle_dir does not match release evidence",
    )
    require(
        Path(archived_root_disk).expanduser().resolve().parent == Path(archived_bundle_dir).expanduser().resolve(),
        "archived smoke bundle root_disk is not in bundle_dir",
    )
    require(
        Path(archived_clone_dest).expanduser().resolve().parent == Path(archived_bundle_dir).expanduser().resolve(),
        "archived smoke bundle clone_dest is not in bundle_dir",
    )
    require(
        Path(archived_root_disk).expanduser().resolve() == Path(archived_clone[1]).expanduser().resolve(),
        "archived smoke APFS clone source does not match bundle root_disk path",
    )
    require(
        Path(archived_root_disk).name == Path(root_disk).name,
        "archived smoke bundle root_disk does not match bundle manifest",
    )
    require(
        Path(archived_clone[1]).name == Path(root_disk).name,
        "archived smoke APFS clone source does not match bundle root_disk",
    )
    require(
        Path(archived_clone_dest).expanduser().resolve() == Path(archived_clone[2]).expanduser().resolve(),
        "archived smoke APFS clone destination does not match bundle clone_dest",
    )
    require_command_option_path(archived_launch, "--root-disk", Path(archived_clone[2]), "archived smoke os_mode command")
    require(Path(archived_launch[0]).name == "os_mode", "archived smoke os_mode command must start with examples/os_mode")
    require(Path(archived_launch[0]).parent.name == "examples", "archived smoke os_mode command must start with examples/os_mode")

    require(Path(archived_smoke[0]).name == "os_mode_smoke.py", "archived smoke command must start with examples/os_mode_smoke.py")
    require(Path(archived_smoke[0]).parent.name == "examples", "archived smoke command must start with examples/os_mode_smoke.py")
    require("--" in archived_smoke, "archived smoke command is missing os_mode separator")
    separator = archived_smoke.index("--")
    embedded_launch = archived_smoke[separator + 1 :]
    actual_launch = require_string_list(smoke.get("command"), "archived smoke executed command")
    require(embedded_launch == actual_launch, "archived smoke command does not match executed os_mode command")
    require(
        actual_launch == archived_launch or actual_launch == [*archived_launch, "--poweroff-after-ready"],
        "archived smoke executed command does not match os_mode command",
    )


def verify_timings(smoke: dict[str, Any], evidence: dict[str, Any]) -> None:
    timings = smoke.get("bundle", {}).get("timings_ms")
    require(isinstance(timings, dict), "smoke JSON is missing bundle timings")
    for key in ("bundle_extraction", "apfs_clone", "post_extraction_run", "smoke", "importer_total"):
        value = timings.get(key)
        require(isinstance(value, int) and value >= 0, f"smoke timing {key} is missing or invalid")
    evidence_timings = evidence.get("smoke", {}).get("bundle_timings_ms")
    require(isinstance(evidence_timings, dict), "release evidence is missing smoke bundle timings")
    for key in ("bundle_extraction", "apfs_clone", "post_extraction_run", "smoke", "importer_total"):
        require(evidence_timings.get(key) == timings.get(key), f"release evidence smoke timing {key} does not match archived smoke JSON")


def verify_perf(
    evidence: dict[str, Any],
    perf_json: dict[str, Any],
    bundle_manifest: dict[str, Any],
) -> None:
    bundle = evidence.get("bundle")
    require(isinstance(bundle, dict), "release evidence is missing bundle summary")
    expected_root = bundle.get("expected_root")
    expected_console = bundle.get("expected_console")
    expected_pid1 = bundle.get("expected_pid1")
    require(expected_root == bundle_manifest.get("expected_root"), "evidence expected_root does not match bundle manifest")
    require(expected_console == bundle_manifest.get("console"), "evidence expected_console does not match bundle manifest")
    require(expected_pid1 == bundle_manifest.get("expected_pid1"), "evidence expected_pid1 does not match bundle manifest")

    perf = evidence.get("perf")
    require(isinstance(perf, dict), "release evidence is missing perf summary")
    require(perf.get("failure_reason") is None, "perf summary recorded a failure")
    require(perf_json.get("failure_reason") is None, "archived perf JSON recorded a failure")
    require(perf.get("observed_root") == expected_root, "perf observed_root mismatch")
    require(perf.get("observed_pid1") == expected_pid1, "perf observed_pid1 mismatch")
    require(perf.get("observed_pid1") != "init.krun", "perf observed init.krun as PID 1")
    consoles = perf.get("observed_consoles")
    require(isinstance(consoles, list) and expected_console in consoles, "perf did not observe the expected console")
    require(perf_json.get("observed_root") == expected_root, "archived perf observed_root mismatch")
    require(perf_json.get("observed_pid1") == expected_pid1, "archived perf observed_pid1 mismatch")
    archived_consoles = perf_json.get("observed_consoles")
    require(isinstance(archived_consoles, list) and expected_console in archived_consoles, "archived perf did not observe the expected console")
    require(archived_consoles == consoles, "archived perf observed_consoles mismatch")
    if "observed_network" in perf or "observed_network" in perf_json:
        require(perf_json.get("observed_network") == perf.get("observed_network"), "archived perf observed_network mismatch")
    timings = perf.get("timings_ms")
    require(isinstance(timings, dict), "perf summary is missing timings")
    archived_timings = perf_json.get("timings")
    require(isinstance(archived_timings, dict), "archived perf JSON is missing timings")
    for key in ("root_ms", "pid1_ms", "console_ms", "ready_ms"):
        value = timings.get(key)
        require(isinstance(value, int) and value >= 0, f"perf timing {key} is missing or invalid")
        require(archived_timings.get(key) == value, f"archived perf timing {key} does not match release evidence")
    if "first_kernel_log_ms" in timings or "first_kernel_log_ms" in archived_timings:
        value = timings.get("first_kernel_log_ms")
        require(isinstance(value, int) and value >= 0, "perf timing first_kernel_log_ms is invalid")
        require(
            archived_timings.get("first_kernel_log_ms") == value,
            "archived perf timing first_kernel_log_ms does not match release evidence",
        )


def verify_perf_commands(summary: dict[str, Any], perf_artifact: dict[str, Any], bundle_manifest: dict[str, Any]) -> None:
    perf_command = summary.get("perf_command")
    require_command_items(perf_command, ("--require-pid1-marker",), "perf command")
    require_command_option_basename(
        perf_command,
        "--output",
        perf_artifact.get("source"),
        "perf command",
    )
    perf_clone_command = summary.get("perf_clone_command")
    require(
        isinstance(perf_clone_command, list) and all(isinstance(item, str) for item in perf_clone_command),
        "perf clone command must be a string list",
    )
    require(len(perf_clone_command) >= 3, "perf clone command must include helper, source, and destination")
    require(Path(perf_clone_command[0]).name == "os_mode_apfs_clone.sh", "perf clone command must use os_mode_apfs_clone.sh")
    root_disk = bundle_manifest.get("root_disk")
    require(isinstance(root_disk, str) and root_disk != "", "bundle manifest root_disk is missing")
    require(
        Path(perf_clone_command[1]).name == Path(root_disk).name,
        "perf clone command source does not match bundle root_disk",
    )
    require_command_option_path(perf_command, "--root-disk", Path(perf_clone_command[2]), "perf command")


def verify_baseline_table(evidence_dir: Path) -> None:
    baseline_path = evidence_dir / "baseline.md"
    require(baseline_path.is_file(), "baseline.md is missing")
    try:
        expected = os_mode_baseline_table.markdown_table(
            os_mode_baseline_table.rows_from_release_evidence([evidence_dir], [])
        )
    except os_mode_baseline_table.BaselineError as err:
        raise VerifyError(f"could not render baseline.md from release evidence: {err}") from err
    actual = baseline_path.read_text(encoding="utf-8")
    require(actual == expected, "baseline.md does not match release evidence")


def verify_evidence(args: argparse.Namespace) -> dict[str, Any]:
    evidence_dir = args.evidence_dir.expanduser().resolve()
    require(evidence_dir.is_dir(), f"evidence directory does not exist: {evidence_dir}")
    evidence = load_json(evidence_dir / "release-evidence.json", "release evidence")
    summary = load_json(evidence_dir / "release-gate-summary.json", "release-gate summary")
    verify_summary_paths(evidence_dir, summary)
    verify_baseline_table(evidence_dir)
    require(evidence.get("schema_version") == 1, "release evidence schema_version must be 1")
    require(summary.get("schema_version") == 1, "release-gate summary schema_version must be 1")
    image_ref = evidence.get("image_ref")
    require(isinstance(image_ref, str) and image_ref != "", "release evidence is missing image_ref")
    require(image_ref == summary.get("image_ref"), "summary image_ref does not match release evidence")
    require(importer.image_reference_is_digest_pinned(image_ref), "release evidence image_ref is not digest-pinned")

    artifacts = evidence.get("artifacts")
    require(isinstance(artifacts, dict), "release evidence is missing artifacts")
    bundle_manifest_path = verify_artifact(evidence_dir, artifacts, "bundle_manifest", "bundle-manifest.json")
    smoke_path = verify_artifact(evidence_dir, artifacts, "smoke_json", "smoke.json")
    bundle_manifest = load_json(bundle_manifest_path, "archived bundle manifest")
    smoke = load_json(smoke_path, "archived smoke JSON")
    if "source_manifest" in artifacts:
        verify_artifact(evidence_dir, artifacts, "source_manifest", "source-manifest.json")
    if args.require_perf:
        perf_artifact = artifacts.get("perf_json")
        require(isinstance(perf_artifact, dict), "release evidence is missing perf_json artifact metadata")
        perf_path = verify_artifact(evidence_dir, artifacts, "perf_json", "perf.json")
        perf_json = load_json(perf_path, "archived perf JSON")
        verify_perf(evidence, perf_json, bundle_manifest)
        verify_perf_commands(summary, perf_artifact, bundle_manifest)

    verify_runtime_markers(evidence, smoke, bundle_manifest)
    verify_smoke_commands(evidence, smoke, bundle_manifest)
    verify_timings(smoke, evidence)
    smoke_importer_command = summary.get("smoke_importer_command")
    require_command_items(smoke_importer_command, ("--strict-digest", "--reuse-extracted-output-dir", "--run"), "smoke importer command")
    require_command_option_value(smoke_importer_command, "--image", image_ref, "smoke importer command")
    cache_entry = summary.get("cache_entry")
    require(isinstance(cache_entry, str) and cache_entry != "", "summary is missing cache_entry")
    require_command_option_path(smoke_importer_command, "--output-dir", Path(cache_entry), "smoke importer command")
    smoke_artifact = artifacts.get("smoke_json")
    require(isinstance(smoke_artifact, dict), "release evidence is missing smoke_json artifact metadata")
    require_command_option_basename(
        smoke_importer_command,
        "--smoke-output",
        smoke_artifact.get("source"),
        "smoke importer command",
    )
    verify_command_image_refs(smoke_importer_command, image_ref, required=True, label="smoke importer command")
    if args.require_pull:
        require_command_items(smoke_importer_command, ("--pull",), "smoke importer command")
    if args.require_clean_cache:
        verify_clean_cache(summary, args.require_cache_entry_absent)
    if args.require_clean_host_preflight:
        verify_clean_host_preflight(
            evidence_dir,
            evidence,
            summary,
            artifacts,
            require_absent=args.require_cache_entry_absent,
            require_apfs=args.require_apfs,
            require_macos_arm64=args.require_macos_arm64,
        )
    artifact_archive_path = None
    if args.require_artifact_manifest or args.require_artifact_load:
        _artifact_manifest, artifact_archive_path = verify_artifact_manifest(evidence_dir, evidence, summary, artifacts)
    if args.require_artifact_load:
        assert artifact_archive_path is not None
        verify_artifact_load(evidence, summary, artifact_archive_path)
    if getattr(args, "require_build_provenance", False):
        verify_build_provenance(
            evidence,
            summary,
            require_artifact_load=args.require_artifact_load,
        )
    if args.require_apfs:
        apfs = evidence.get("apfs")
        require(isinstance(apfs, dict) and apfs.get("is_apfs") is True, "release evidence APFS check did not pass")
    if args.require_macos_arm64:
        host = evidence.get("host")
        require(isinstance(host, dict), "release evidence is missing host metadata")
        require(host.get("system") == "Darwin", "release evidence was not collected on macOS/Darwin")
        require(host.get("machine") == "arm64", "release evidence was not collected on arm64")
    if args.require_clean_poweroff:
        require(smoke.get("exit_code") == 0, "smoke JSON did not record exit_code=0")
        require(smoke.get("failure_reason") is None, "smoke JSON recorded a failure")

    return {
        "evidence_dir": str(evidence_dir),
        "image_ref": image_ref,
        "observed_root": evidence.get("smoke", {}).get("observed_root"),
        "observed_pid1": evidence.get("smoke", {}).get("observed_pid1"),
        "observed_console": evidence.get("smoke", {}).get("observed_consoles"),
        "ready": evidence.get("smoke", {}).get("ready"),
        "verified": True,
    }


def main() -> int:
    args = parse_args()
    try:
        result = verify_evidence(args)
    except VerifyError as err:
        print(err, file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
