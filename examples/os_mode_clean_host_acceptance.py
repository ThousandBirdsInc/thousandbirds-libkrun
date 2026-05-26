#!/usr/bin/env python3
"""Accept a completed clean-host macOS OS-mode release-evidence archive."""

import argparse
import datetime
import json
import sys
from pathlib import Path
from typing import Any

import os_mode_baseline_table
import os_mode_verify_release_evidence


class AcceptanceError(Exception):
    pass


def utc_now_iso() -> str:
    return datetime.datetime.now(datetime.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


BASE_REQUIRED_CHECKS = (
    "clean cache",
    "absent cache entry",
    "APFS output",
    "macOS arm64 host",
    "build provenance",
    "host-side launcher process",
    "host-side launch command binding",
    "bundle provenance",
    "clean-host preflight",
    "release-gate summary",
    "guest OS markers",
    "perf markers",
    "first boot log timing",
    "baseline marker timings",
    "clean poweroff",
    "baseline timing row",
    "image load/pull/export timing",
)


def non_empty_path(value: str) -> Path:
    if value == "":
        raise argparse.ArgumentTypeError("path must be non-empty")
    return Path(value)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Verify a completed clean-host macOS OS-bundle release-evidence "
            "archive and print the baseline table that can be copied into "
            "release notes or the design doc."
        )
    )
    parser.add_argument("evidence_dir", type=non_empty_path)
    parser.add_argument(
        "--artifact",
        action="store_true",
        help="Require archive artifact-manifest and image-load proof.",
    )
    parser.add_argument(
        "--pull",
        action="store_true",
        help="Require an explicit pull phase for registry-delivered evidence.",
    )
    parser.add_argument(
        "--json-output",
        type=non_empty_path,
        default=None,
        help="Write the acceptance result JSON to this path.",
    )
    parser.add_argument(
        "--table-output",
        type=non_empty_path,
        default=None,
        help="Write only the accepted Markdown baseline table to this path.",
    )
    parser.add_argument(
        "--final-release-baseline",
        action="store_true",
        help=(
            "Mark the accepted JSON as the final clean Apple Silicon baseline "
            "source. This is required before the design-doc helper can render "
            "an Implemented audit row."
        ),
    )
    return parser.parse_args()


def verifier_args(evidence_dir: Path, *, artifact: bool, pull: bool) -> argparse.Namespace:
    return argparse.Namespace(
        evidence_dir=evidence_dir,
        require_clean_cache=True,
        require_cache_entry_absent=True,
        require_artifact_manifest=artifact,
        require_artifact_load=artifact,
        require_apfs=True,
        require_macos_arm64=True,
        require_perf=True,
        require_clean_poweroff=True,
        require_pull=pull,
        require_clean_host_preflight=True,
        require_build_provenance=True,
    )


def baseline_table(evidence_dir: Path) -> str:
    try:
        return os_mode_baseline_table.markdown_table(
            os_mode_baseline_table.rows_from_release_evidence([evidence_dir], [])
        )
    except os_mode_baseline_table.BaselineError as err:
        raise AcceptanceError(f"could not render baseline table: {err}") from err


def copied_artifact_json(evidence_dir: Path, evidence: dict[str, Any], key: str, fallback: str) -> dict[str, Any] | None:
    artifacts = evidence.get("artifacts")
    if not isinstance(artifacts, dict) or key not in artifacts:
        return None
    path = evidence_dir / fallback
    if not path.is_file():
        return None
    return load_json(path, fallback)


def checklist_item(name: str, passed: bool, evidence: str) -> dict[str, Any]:
    return {
        "name": name,
        "passed": passed,
        "evidence": evidence,
    }


def required_check_names(*, artifact: bool, pull: bool) -> tuple[str, ...]:
    names = list(BASE_REQUIRED_CHECKS)
    if artifact:
        names.append("artifact delivery")
    if pull:
        names.append("registry pull")
    return tuple(names)


def validate_required_checklist(checklist: list[Any], *, artifact: bool, pull: bool) -> None:
    names: dict[str, dict[str, Any]] = {}
    invalid_items: list[str] = []
    duplicate_names: list[str] = []
    for index, item in enumerate(checklist):
        if not isinstance(item, dict):
            invalid_items.append(f"#{index}")
            continue
        name = item.get("name")
        if not isinstance(name, str) or name == "":
            invalid_items.append(f"#{index}")
            continue
        if not isinstance(item.get("passed"), bool):
            invalid_items.append(name)
            continue
        evidence = item.get("evidence")
        if not isinstance(evidence, str) or evidence == "":
            invalid_items.append(name)
            continue
        if name in names:
            duplicate_names.append(name)
            continue
        names[name] = item
    if invalid_items:
        raise AcceptanceError("acceptance checklist has invalid items: " + ", ".join(invalid_items))
    if duplicate_names:
        raise AcceptanceError("acceptance checklist has duplicate items: " + ", ".join(duplicate_names))

    required = required_check_names(artifact=artifact, pull=pull)
    missing = [name for name in required if name not in names]
    if missing:
        raise AcceptanceError("acceptance checklist is missing required items: " + ", ".join(missing))
    unexpected = [name for name in names if name not in required]
    if unexpected:
        raise AcceptanceError("acceptance checklist has unexpected items: " + ", ".join(unexpected))
    ordered_names = list(names)
    if ordered_names != list(required):
        raise AcceptanceError("acceptance checklist order does not match required items")


def non_negative_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def positive_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def string_list(value: Any) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        return []
    return value


def command_option_value(command: list[str], option: str) -> str | None:
    if option not in command:
        return None
    index = command.index(option)
    if index + 1 >= len(command):
        return None
    return command[index + 1]


def command_positional_args(command: list[str]) -> list[str] | None:
    if not command:
        return None
    positionals: list[str] = []
    for item in command[1:]:
        if item.startswith("--"):
            break
        if item == "":
            return None
        positionals.append(item)
    return positionals


def path_matches(value: Any, expected: Path) -> bool:
    if not isinstance(value, str) or value == "":
        return False
    try:
        return Path(value).expanduser().resolve() == expected.expanduser().resolve()
    except (OSError, RuntimeError, ValueError):
        return False


def acceptance_checklist(
    evidence_dir: Path,
    *,
    artifact: bool,
    pull: bool,
    verification: dict[str, Any],
) -> list[dict[str, Any]]:
    evidence = load_json(evidence_dir / "release-evidence.json", "release evidence")
    summary = load_json(evidence_dir / "release-gate-summary.json", "release-gate summary")
    smoke_json = copied_artifact_json(evidence_dir, evidence, "smoke_json", "smoke.json") or {}
    bundle_manifest = copied_artifact_json(
        evidence_dir,
        evidence,
        "bundle_manifest",
        "bundle-manifest.json",
    ) or {}
    source_manifest = copied_artifact_json(
        evidence_dir,
        evidence,
        "source_manifest",
        "source-manifest.json",
    ) or {}
    preflight_json = (
        copied_artifact_json(
            evidence_dir,
            evidence,
            "clean_host_preflight_json",
            "clean-host-preflight.json",
        )
        or {}
    )

    cache_preflight = summary.get("cache_preflight")
    if not isinstance(cache_preflight, dict):
        cache_preflight = {}
    clean_host_preflight = preflight_json or evidence.get("clean_host_preflight")
    if not isinstance(clean_host_preflight, dict):
        clean_host_preflight = {}
    clean_host_preflight_artifact = {}
    artifacts = evidence.get("artifacts")
    if isinstance(artifacts, dict):
        artifact_value = artifacts.get("clean_host_preflight_json")
        if isinstance(artifact_value, dict):
            clean_host_preflight_artifact = artifact_value
    clean_host_preflight_source = clean_host_preflight_artifact.get("source")
    preflight_release_gate_command = string_list(clean_host_preflight.get("release_gate_command"))
    preflight_release_gate_positionals = command_positional_args(preflight_release_gate_command)
    preflight_cache = clean_host_preflight.get("cache_entry")
    if not isinstance(preflight_cache, dict):
        preflight_cache = {}

    apfs = evidence.get("apfs")
    if not isinstance(apfs, dict):
        apfs = {}
    host = evidence.get("host")
    if not isinstance(host, dict):
        host = {}
    smoke = evidence.get("smoke")
    if not isinstance(smoke, dict):
        smoke = {}
    bundle = evidence.get("bundle")
    if not isinstance(bundle, dict):
        bundle = {}
    perf = evidence.get("perf")
    if not isinstance(perf, dict):
        perf = {}
    artifact_summary = evidence.get("artifact")
    if not isinstance(artifact_summary, dict):
        artifact_summary = {}
    build_commands = string_list(evidence.get("build_commands"))
    generated_build_command_prefixes = (
        "artifact_load_command=",
        "smoke_importer_command=",
    )
    user_build_commands = [
        command
        for command in build_commands
        if not command.startswith(generated_build_command_prefixes)
    ]
    build_provenance_ok = (
        bool(user_build_commands)
        and any(command.startswith("smoke_importer_command=") for command in build_commands)
        and (
            not artifact
            or any(command.startswith("artifact_load_command=") for command in build_commands)
        )
    )
    image_was_explicit = summary.get("image_was_explicit")
    summary_artifact_manifest = summary.get("artifact_manifest")
    smoke_command = summary.get("smoke_importer_command")
    has_pull = isinstance(smoke_command, list) and "--pull" in smoke_command
    bundle_timings = smoke.get("bundle_timings_ms")
    if not isinstance(bundle_timings, dict):
        bundle_timings = {}
    smoke_timings = smoke.get("timings_ms")
    if not isinstance(smoke_timings, dict):
        smoke_timings = {}
    perf_timings = perf.get("timings_ms")
    if not isinstance(perf_timings, dict):
        perf_timings = {}
    source_timings = source_manifest.get("timings_ms")
    if not isinstance(source_timings, dict):
        source_timings = {}
    smoke_bundle = smoke_json.get("bundle")
    if not isinstance(smoke_bundle, dict):
        smoke_bundle = {}
    smoke_output_lines = smoke_json.get("output_lines")
    first_kernel_line = None
    if isinstance(smoke_output_lines, list):
        first_kernel_line = next(
            (
                line
                for line in smoke_output_lines
                if isinstance(line, str) and os_mode_verify_release_evidence.is_early_kernel_line(line)
            ),
            None,
        )
    summary_clone_command = string_list(smoke.get("apfs_clone_command"))
    summary_launch_command = string_list(smoke.get("os_mode_command"))
    summary_smoke_command = string_list(smoke.get("smoke_command"))
    archived_clone_command = string_list(smoke_bundle.get("apfs_clone_command"))
    archived_launch_command = string_list(smoke_bundle.get("os_mode_command"))
    archived_smoke_command = string_list(smoke_bundle.get("smoke_command"))
    archived_executed_command = string_list(smoke_json.get("command"))
    launch_root_disk = command_option_value(archived_launch_command, "--root-disk")
    clone_dest = archived_clone_command[2] if len(archived_clone_command) >= 3 else None
    command_binding_ok = (
        summary_clone_command == archived_clone_command
        and summary_launch_command == archived_launch_command
        and summary_smoke_command == archived_smoke_command
        and len(archived_clone_command) >= 3
        and len(archived_launch_command) >= 1
        and len(archived_smoke_command) >= 1
        and Path(archived_clone_command[0]).name == "os_mode_apfs_clone.sh"
        and Path(archived_launch_command[0]).name == "os_mode"
        and Path(archived_launch_command[0]).parent.name == "examples"
        and Path(archived_smoke_command[0]).name == "os_mode_smoke.py"
        and Path(archived_smoke_command[0]).parent.name == "examples"
        and launch_root_disk is not None
        and clone_dest is not None
        and Path(launch_root_disk).expanduser().resolve() == Path(clone_dest).expanduser().resolve()
        and "--" in archived_smoke_command
        and archived_smoke_command[archived_smoke_command.index("--") + 1 :] == archived_executed_command
        and (
            archived_executed_command == archived_launch_command
            or archived_executed_command == [*archived_launch_command, "--poweroff-after-ready"]
        )
    )
    provenance_keys = (
        "kind",
        "manifest_schema_version",
        "platform",
        "source_image",
        "source_digest",
        "root_disk_sha256",
        "kernel_sha256",
        "initramfs_sha256",
    )
    provenance_ok = (
        bool(bundle_manifest)
        and all(bundle.get(key) == bundle_manifest.get(key) for key in provenance_keys)
        and bundle.get("expected_root") == bundle_manifest.get("expected_root")
        and bundle.get("expected_console") == bundle_manifest.get("console")
        and bundle.get("expected_pid1") == bundle_manifest.get("expected_pid1")
        and smoke_bundle.get("source_image") == bundle_manifest.get("source_image")
        and smoke_bundle.get("source_digest") == bundle_manifest.get("source_digest")
        and smoke_bundle.get("root_disk_sha256") == bundle_manifest.get("root_disk_sha256")
        and smoke_bundle.get("imported_image") == evidence.get("image_ref")
    )
    expected_root = bundle.get("expected_root")
    expected_console = bundle.get("expected_console")
    expected_pid1 = bundle.get("expected_pid1")
    observed_consoles = smoke.get("observed_consoles")
    verified_consoles = verification.get("observed_console")
    guest_markers_ok = (
        verification.get("ready") is True
        and verification.get("observed_root") == expected_root
        and smoke.get("observed_root") == expected_root
        and verification.get("observed_pid1") == expected_pid1
        and smoke.get("observed_pid1") == expected_pid1
        and expected_pid1 != "init.krun"
        and isinstance(verified_consoles, list)
        and expected_console in verified_consoles
        and isinstance(observed_consoles, list)
        and expected_console in observed_consoles
    )
    perf_consoles = perf.get("observed_consoles")
    perf_markers_ok = (
        perf.get("failure_reason") is None
        and perf.get("observed_root") == expected_root
        and perf.get("observed_pid1") == expected_pid1
        and expected_pid1 != "init.krun"
        and isinstance(perf_consoles, list)
        and expected_console in perf_consoles
        and all(non_negative_int(perf_timings.get(key)) for key in ("root_ms", "pid1_ms", "console_ms", "ready_ms"))
    )
    first_boot_log_ok = (
        non_negative_int(smoke_timings.get("first_kernel_log_ms"))
        and isinstance(smoke_output_lines, list)
        and all(isinstance(line, str) for line in smoke_output_lines)
        and first_kernel_line is not None
    )
    clean_poweroff_ok = (
        smoke_json.get("exit_code") == 0
        and smoke_json.get("failure_reason") is None
        and smoke_json.get("timed_out") is False
        and archived_executed_command == [*archived_launch_command, "--poweroff-after-ready"]
    )
    release_gate_image_mode_ok = False
    if isinstance(image_was_explicit, bool) and preflight_release_gate_positionals is not None:
        if summary_artifact_manifest is None:
            release_gate_image_mode_ok = (
                image_was_explicit is True
                and preflight_release_gate_positionals == [evidence.get("image_ref")]
            )
        else:
            release_gate_image_mode_ok = (
                isinstance(summary_artifact_manifest, str)
                and summary_artifact_manifest != ""
                and preflight_release_gate_positionals
                == ([evidence.get("image_ref")] if image_was_explicit else [])
            )
    release_gate_summary_ok = (
        summary.get("schema_version") == 1
        and summary.get("clean_host_baseline") is True
        and summary.get("require_clean_cache") is True
        and summary.get("require_cache_entry_absent") is True
        and release_gate_image_mode_ok
        and path_matches(summary.get("release_evidence"), evidence_dir / "release-evidence.json")
        and path_matches(summary.get("baseline_table"), evidence_dir / "baseline.md")
        and isinstance(clean_host_preflight_source, str)
        and path_matches(summary.get("preflight_json"), Path(clean_host_preflight_source))
    )

    transport_timing_ok = True
    transport_evidence = [
        f"artifact.load_ms={artifact_summary.get('load_ms')}",
        f"bundle_timings_ms.image_pull={bundle_timings.get('image_pull')}",
        f"source.timings_ms.export_rootfs={source_timings.get('export_rootfs')}",
    ]
    if artifact:
        transport_timing_ok = transport_timing_ok and non_negative_int(artifact_summary.get("load_ms"))
    if pull:
        transport_timing_ok = transport_timing_ok and has_pull and non_negative_int(bundle_timings.get("image_pull"))
    if "source_manifest" in (evidence.get("artifacts") or {}):
        transport_timing_ok = transport_timing_ok and non_negative_int(source_timings.get("export_rootfs"))

    items = [
        checklist_item(
            "clean cache",
            cache_preflight.get("clean") is True and preflight_cache.get("clean") is True,
            (
                f"summary.cache_preflight.clean={cache_preflight.get('clean')}, "
                f"preflight.cache_entry.clean={preflight_cache.get('clean')}"
            ),
        ),
        checklist_item(
            "absent cache entry",
            cache_preflight.get("exists") is False and preflight_cache.get("exists") is False,
            (
                f"summary.cache_preflight.exists={cache_preflight.get('exists')}, "
                f"preflight.cache_entry.exists={preflight_cache.get('exists')}"
            ),
        ),
        checklist_item(
            "APFS output",
            apfs.get("is_apfs") is True,
            f"release_evidence.apfs.is_apfs={apfs.get('is_apfs')} filesystem={apfs.get('filesystem')}",
        ),
        checklist_item(
            "macOS arm64 host",
            host.get("system") == "Darwin" and host.get("machine") == "arm64",
            f"host.system={host.get('system')} host.machine={host.get('machine')} macos={host.get('macos')}",
        ),
        checklist_item(
            "build provenance",
            build_provenance_ok,
            (
                f"user_build_commands={user_build_commands} "
                f"generated_command_count={len(build_commands) - len(user_build_commands)}"
            ),
        ),
        checklist_item(
            "host-side launcher process",
            positive_int(smoke.get("launcher_pid"))
            and positive_int(smoke.get("process_parent_pid"))
            and positive_int(smoke.get("process_pid"))
            and smoke.get("process_parent_pid") == smoke.get("launcher_pid")
            and smoke.get("process_pid") != smoke.get("launcher_pid")
            and smoke_json.get("launcher_pid") == smoke.get("launcher_pid")
            and smoke_json.get("process_parent_pid") == smoke.get("process_parent_pid")
            and smoke_json.get("process_pid") == smoke.get("process_pid"),
            (
                f"summary.launcher_pid={smoke.get('launcher_pid')} "
                f"summary.process_parent_pid={smoke.get('process_parent_pid')} "
                f"summary.process_pid={smoke.get('process_pid')}"
            ),
        ),
        checklist_item(
            "host-side launch command binding",
            command_binding_ok,
            (
                f"clone_dest={clone_dest} launch_root_disk={launch_root_disk} "
                f"launch={archived_launch_command[:1]} smoke={archived_smoke_command[:1]}"
            ),
        ),
        checklist_item(
            "bundle provenance",
            provenance_ok,
            (
                f"platform={bundle.get('platform')} "
                f"source_image={bundle.get('source_image')} "
                f"source_digest={bundle.get('source_digest')} "
                f"root_disk_sha256={bundle.get('root_disk_sha256')} "
                f"kernel_sha256={bundle.get('kernel_sha256')} "
                f"initramfs_sha256={bundle.get('initramfs_sha256')} "
                f"expected_root={bundle.get('expected_root')} "
                f"expected_console={bundle.get('expected_console')} "
                f"expected_pid1={bundle.get('expected_pid1')} "
                f"image_ref={evidence.get('image_ref')}"
            ),
        ),
        checklist_item(
            "clean-host preflight",
            clean_host_preflight.get("ok") is True,
            (
                f"clean_host_preflight.ok={clean_host_preflight.get('ok')} "
                f"created_at_utc={clean_host_preflight.get('created_at_utc')}"
            ),
        ),
        checklist_item(
            "release-gate summary",
            release_gate_summary_ok,
            (
                f"schema_version={summary.get('schema_version')} "
                f"clean_host_baseline={summary.get('clean_host_baseline')} "
                f"require_clean_cache={summary.get('require_clean_cache')} "
                f"require_cache_entry_absent={summary.get('require_cache_entry_absent')} "
                f"image_was_explicit={image_was_explicit} "
                f"artifact_manifest={summary_artifact_manifest} "
                f"release_gate_positionals={preflight_release_gate_positionals} "
                f"release_evidence={summary.get('release_evidence')} "
                f"baseline_table={summary.get('baseline_table')} "
                f"preflight_json={summary.get('preflight_json')}"
            ),
        ),
        checklist_item(
            "guest OS markers",
            guest_markers_ok,
            (
                f"ready={verification.get('ready')} root={verification.get('observed_root')} "
                f"expected_root={expected_root} pid1={verification.get('observed_pid1')} "
                f"expected_pid1={expected_pid1} console={verification.get('observed_console')} "
                f"expected_console={expected_console}"
            ),
        ),
        checklist_item(
            "perf markers",
            perf_markers_ok,
            (
                f"root={perf.get('observed_root')} expected_root={expected_root} "
                f"pid1={perf.get('observed_pid1')} expected_pid1={expected_pid1} "
                f"console={perf.get('observed_consoles')} expected_console={expected_console} "
                f"perf.timings_ms={perf_timings}"
            ),
        ),
        checklist_item(
            "first boot log timing",
            first_boot_log_ok,
            (
                f"smoke.timings_ms.first_kernel_log_ms={smoke_timings.get('first_kernel_log_ms')} "
                f"first_kernel_line={first_kernel_line}"
            ),
        ),
        checklist_item(
            "baseline marker timings",
            all(non_negative_int(perf_timings.get(key)) for key in ("root_ms", "pid1_ms", "ready_ms")),
            (
                f"root_ms={perf_timings.get('root_ms')} "
                f"pid1_ms={perf_timings.get('pid1_ms')} "
                f"ready_ms={perf_timings.get('ready_ms')}"
            ),
        ),
        checklist_item(
            "clean poweroff",
            clean_poweroff_ok,
            (
                f"smoke.exit_code={smoke_json.get('exit_code')} "
                f"smoke.failure_reason={smoke_json.get('failure_reason')} "
                f"smoke.timed_out={smoke_json.get('timed_out')} "
                f"used_poweroff_after_ready={'--poweroff-after-ready' in archived_executed_command}"
            ),
        ),
        checklist_item(
            "baseline timing row",
            all(
                non_negative_int(bundle_timings.get(key))
                for key in ("bundle_extraction", "apfs_clone", "importer_total")
            ),
            f"bundle_timings_ms={bundle_timings}",
        ),
        checklist_item(
            "image load/pull/export timing",
            transport_timing_ok,
            ", ".join(transport_evidence),
        ),
    ]
    if artifact:
        items.append(
            checklist_item(
                "artifact delivery",
                isinstance(artifact_summary.get("load_ms"), int) and artifact_summary.get("load_ms") >= 0,
                f"artifact.load_ms={artifact_summary.get('load_ms')}",
            )
        )
    if pull:
        items.append(
            checklist_item(
                "registry pull",
                has_pull and isinstance(bundle_timings.get("image_pull"), int),
                (
                    f"smoke_importer_command_has_pull={has_pull} "
                    f"bundle_timings_ms.image_pull={bundle_timings.get('image_pull')}"
                ),
            )
        )
    return items


def load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        return os_mode_verify_release_evidence.load_json(path, label)
    except os_mode_verify_release_evidence.VerifyError as err:
        raise AcceptanceError(str(err)) from err


def require_matching_flags(evidence_dir: Path, *, artifact: bool, pull: bool) -> None:
    evidence = load_json(evidence_dir / "release-evidence.json", "release evidence")
    summary = load_json(evidence_dir / "release-gate-summary.json", "release-gate summary")

    artifacts = evidence.get("artifacts")
    has_artifact_manifest = (
        isinstance(artifacts, dict)
        and "artifact_manifest_json" in artifacts
    ) or summary.get("artifact_manifest") is not None
    if has_artifact_manifest and not artifact:
        raise AcceptanceError(
            "release evidence contains an artifact manifest; rerun with --artifact "
            "or make os-mode-accept-clean-host ARTIFACT=1"
        )

    smoke_command = summary.get("smoke_importer_command")
    has_pull = isinstance(smoke_command, list) and "--pull" in smoke_command
    if has_pull and not pull:
        raise AcceptanceError(
            "release evidence records an explicit pull phase; rerun with --pull "
            "or make os-mode-accept-clean-host PULL=1"
        )


def accept_evidence(
    evidence_dir: Path,
    *,
    artifact: bool = False,
    pull: bool = False,
    final_release_baseline: bool = False,
) -> dict[str, Any]:
    evidence_dir = evidence_dir.expanduser().resolve()
    require_matching_flags(evidence_dir, artifact=artifact, pull=pull)
    try:
        verification = os_mode_verify_release_evidence.verify_evidence(
            verifier_args(evidence_dir, artifact=artifact, pull=pull)
        )
    except os_mode_verify_release_evidence.VerifyError as err:
        raise AcceptanceError(str(err)) from err

    table = baseline_table(evidence_dir)
    checklist = acceptance_checklist(
        evidence_dir,
        artifact=artifact,
        pull=pull,
        verification=verification,
    )
    validate_required_checklist(checklist, artifact=artifact, pull=pull)
    failed_checks = [
        str(item["name"])
        for item in checklist
        if item.get("passed") is not True
    ]
    if failed_checks:
        raise AcceptanceError(
            "acceptance checklist did not pass: " + ", ".join(failed_checks)
        )
    required_checks = list(required_check_names(artifact=artifact, pull=pull))
    return {
        "schema_version": 1,
        "accepted": True,
        "accepted_at_utc": utc_now_iso(),
        "final_release_baseline": final_release_baseline,
        "evidence_dir": str(evidence_dir),
        "requirements": {
            "clean_cache": True,
            "cache_entry_absent": True,
            "apfs": True,
            "macos_arm64": True,
            "perf": True,
            "clean_poweroff": True,
            "clean_host_preflight": True,
            "build_provenance": True,
            "artifact_manifest": artifact,
            "artifact_load": artifact,
            "pull": pull,
        },
        "required_checklist": required_checks,
        "evidence_checklist": checklist,
        "verification": verification,
        "baseline_table": table,
    }


def validate_output_path(path: Path, option: str) -> Path:
    path = path.expanduser().resolve()
    if not path.parent.is_dir():
        raise AcceptanceError(f"{option} parent directory does not exist: {path.parent}")
    if path.exists():
        raise AcceptanceError(f"{option} already exists: {path}")
    return path


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path = validate_output_path(path, "--json-output")
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_table(path: Path, table: str) -> None:
    path = validate_output_path(path, "--table-output")
    path.write_text(table, encoding="utf-8")


def validate_output_args(json_output: Path | None, table_output: Path | None) -> None:
    if json_output is not None and table_output is not None:
        json_path = json_output.expanduser().resolve()
        table_path = table_output.expanduser().resolve()
        if json_path == table_path:
            raise AcceptanceError("--json-output and --table-output must be different paths")
    if json_output is not None:
        validate_output_path(json_output, "--json-output")
    if table_output is not None:
        validate_output_path(table_output, "--table-output")


def same_output_path(json_output: Path | None, table_output: Path | None) -> bool:
    if json_output is None or table_output is None:
        return False
    return json_output.expanduser().resolve() == table_output.expanduser().resolve()


def main() -> int:
    args = parse_args()
    try:
        if args.final_release_baseline and args.json_output is None:
            raise AcceptanceError("--json-output is required with --final-release-baseline")
        if args.final_release_baseline and args.table_output is None:
            raise AcceptanceError("--table-output is required with --final-release-baseline")
        validate_output_args(args.json_output, args.table_output)
        result = accept_evidence(
            args.evidence_dir,
            artifact=args.artifact,
            pull=args.pull,
            final_release_baseline=args.final_release_baseline,
        )
        if args.json_output is not None:
            write_json(args.json_output, result)
        if args.table_output is not None:
            write_table(args.table_output, result["baseline_table"])
    except AcceptanceError as err:
        failure = {
            "schema_version": 1,
            "accepted": False,
            "evidence_dir": str(args.evidence_dir.expanduser().resolve()),
            "error": str(err),
        }
        if args.json_output is not None and not same_output_path(args.json_output, args.table_output):
            try:
                write_json(args.json_output, failure)
            except AcceptanceError as write_err:
                print(f"{err}; additionally failed to write JSON output: {write_err}", file=sys.stderr)
                return 1
        print(str(err), file=sys.stderr)
        return 1

    print(json.dumps(result, indent=2, sort_keys=True))
    print(result["baseline_table"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
