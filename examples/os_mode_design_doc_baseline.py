#!/usr/bin/env python3
"""Render an accepted clean-host OS-mode baseline as a design-doc snippet."""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

import os_mode_clean_host_acceptance


class DesignDocBaselineError(Exception):
    pass


STRICT_TRUE_REQUIREMENTS = (
    "clean_cache",
    "cache_entry_absent",
    "apfs",
    "macos_arm64",
    "perf",
    "clean_poweroff",
    "clean_host_preflight",
    "build_provenance",
)

UTC_TIMESTAMP_RE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z")


def non_empty_path(value: str) -> Path:
    if value == "":
        raise argparse.ArgumentTypeError("path must be non-empty")
    return Path(value)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Read os_mode_clean_host_acceptance.py JSON output and print the "
            "Markdown snippet that can close the design-doc clean-host "
            "baseline row."
        )
    )
    parser.add_argument(
        "acceptance_json",
        type=non_empty_path,
        help="Accepted clean-host JSON produced by os_mode_clean_host_acceptance.py.",
    )
    parser.add_argument(
        "--final-release-baseline",
        action="store_true",
        help=(
            "Print the completion-audit row as Implemented. Without this flag "
            "the row remains Open so local rehearsal evidence is not "
            "accidentally presented as the final clean-host baseline."
        ),
    )
    parser.add_argument(
        "--evidence-label",
        default=None,
        help="Optional short label to show in the audit-row validation text.",
    )
    parser.add_argument(
        "--output",
        type=non_empty_path,
        default=None,
        help=(
            "Write the rendered Markdown snippet to this path after validation. "
            "The parent directory must already exist and the file must not exist."
        ),
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    path = path.expanduser().resolve()
    if not path.is_file():
        raise DesignDocBaselineError(f"acceptance JSON does not exist: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise DesignDocBaselineError(f"acceptance JSON is invalid: {err}") from err
    if not isinstance(payload, dict):
        raise DesignDocBaselineError("acceptance JSON must be an object")
    return payload


def require(condition: bool, message: str) -> None:
    if not condition:
        raise DesignDocBaselineError(message)


def validate_output_path(path: Path) -> Path:
    output = path.expanduser().resolve()
    if not output.parent.is_dir():
        raise DesignDocBaselineError(f"--output parent directory does not exist: {output.parent}")
    if output.exists():
        raise DesignDocBaselineError(f"--output already exists: {output}")
    return output


def requirement_bool(requirements: dict[str, Any], key: str) -> bool:
    value = requirements.get(key)
    require(isinstance(value, bool), f"requirements.{key} must be a boolean")
    return value


def validate_requirements(payload: dict[str, Any]) -> tuple[bool, bool]:
    requirements = payload.get("requirements")
    require(isinstance(requirements, dict), "accepted JSON is missing requirements")
    for key in STRICT_TRUE_REQUIREMENTS:
        require(requirement_bool(requirements, key) is True, f"requirements.{key} must be true")
    artifact = requirement_bool(requirements, "artifact_manifest")
    artifact_load = requirement_bool(requirements, "artifact_load")
    require(artifact_load is artifact, "requirements.artifact_load must match requirements.artifact_manifest")
    pull = requirement_bool(requirements, "pull")
    return artifact, pull


def validate_checklist(payload: dict[str, Any]) -> list[str]:
    artifact, pull = validate_requirements(payload)
    expected = list(os_mode_clean_host_acceptance.required_check_names(artifact=artifact, pull=pull))

    required = payload.get("required_checklist")
    require(required == expected, "required_checklist does not match current acceptance contract")
    checklist = payload.get("evidence_checklist")
    require(isinstance(checklist, list), "accepted JSON is missing evidence_checklist")
    names: list[str] = []
    for index, item in enumerate(checklist):
        require(isinstance(item, dict), f"evidence_checklist item #{index} must be an object")
        name = item.get("name")
        require(isinstance(name, str) and name != "", f"evidence_checklist item #{index} has invalid name")
        require(item.get("passed") is True, f"evidence_checklist item did not pass: {name}")
        evidence = item.get("evidence")
        require(isinstance(evidence, str) and evidence != "", f"evidence_checklist item lacks evidence: {name}")
        names.append(name)
    require(names == expected, "evidence_checklist order does not match current acceptance contract")
    return expected


def validate_baseline_table(value: Any) -> str:
    require(isinstance(value, str) and value != "", "accepted JSON is missing baseline_table")
    lines = [line for line in value.strip().splitlines() if line.strip()]
    required_headers = (
        "Image load/pull/export ms",
        "Bundle extraction ms",
        "APFS clone ms",
        "First log ms",
        "Root marker ms",
        "PID 1 marker ms",
        "Ready marker ms",
        "Clean poweroff",
        "Total ms",
    )
    require(len(lines) >= 3, "baseline_table must include a header and at least one data row")
    header = lines[0]
    for required_header in required_headers:
        require(required_header in header, f"baseline_table is missing column: {required_header}")
    return value if value.endswith("\n") else value + "\n"


def validate_accepted_at(payload: dict[str, Any]) -> None:
    value = payload.get("accepted_at_utc")
    require(
        isinstance(value, str) and UTC_TIMESTAMP_RE.fullmatch(value) is not None,
        "accepted JSON is missing valid accepted_at_utc",
    )


def accepted_evidence_path(payload: dict[str, Any], acceptance_path: Path) -> str:
    evidence_dir = payload.get("evidence_dir")
    if isinstance(evidence_dir, str) and evidence_dir != "":
        return evidence_dir
    return str(acceptance_path.expanduser().resolve())


def render_snippet(
    payload: dict[str, Any],
    acceptance_path: Path,
    evidence_label: str | None = None,
    *,
    final_release_baseline: bool = False,
) -> str:
    require(payload.get("schema_version") == 1, "accepted JSON schema_version must be 1")
    require(payload.get("accepted") is True, "accepted JSON does not record accepted=true")
    validate_accepted_at(payload)
    if final_release_baseline:
        require(
            payload.get("final_release_baseline") is True,
            "accepted JSON was not created with final_release_baseline=true",
        )
    checklist = validate_checklist(payload)
    table = validate_baseline_table(payload.get("baseline_table"))
    evidence = evidence_label or accepted_evidence_path(payload, acceptance_path)
    checklist_text = ", ".join(checklist)
    status = "Implemented" if final_release_baseline else "Open"
    validation = (
        f"Accepted final clean-host evidence `{evidence}` produced the baseline table below"
        if final_release_baseline
        else (
            f"Accepted clean-host evidence `{evidence}` produced the rehearsal baseline table below; "
            "rerun on the final clean Apple Silicon host before marking this row complete"
        )
    )
    audit_row = (
        f"| Clean-host baseline table on a fresh Apple Silicon host | {status} | "
        f"{validation}; checklist: {checklist_text}. |\n"
    )
    return (
        "### Clean-Host Baseline Table\n\n"
        f"{table}\n"
        "### Completion Audit Row\n\n"
        f"{audit_row}"
    )


def main() -> int:
    args = parse_args()
    acceptance_path = args.acceptance_json.expanduser().resolve()
    try:
        payload = load_json(acceptance_path)
        snippet = render_snippet(
            payload,
            acceptance_path,
            args.evidence_label,
            final_release_baseline=args.final_release_baseline,
        )
        if args.output is not None:
            validate_output_path(args.output).write_text(snippet, encoding="utf-8")
        else:
            print(snippet, end="")
    except DesignDocBaselineError as err:
        print(err, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
