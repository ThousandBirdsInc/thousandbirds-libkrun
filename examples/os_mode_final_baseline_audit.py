#!/usr/bin/env python3
"""Audit the final clean-host OS-mode baseline artifact set."""

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import os_mode_clean_host_acceptance
import os_mode_design_doc_baseline


class FinalBaselineAuditError(Exception):
    pass


def non_empty_path(value: str) -> Path:
    if value == "":
        raise argparse.ArgumentTypeError("path must be non-empty")
    return Path(value)


def non_empty_arg(value: str) -> str:
    if value == "":
        raise argparse.ArgumentTypeError("value must be non-empty")
    return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Verify that the final clean Apple Silicon baseline evidence dir, "
            "accepted JSON, accepted Markdown table, and design-doc snippet "
            "all describe the same final-release baseline."
        )
    )
    parser.add_argument(
        "acceptance_json",
        type=non_empty_path,
        help="Accepted JSON from os_mode_clean_host_acceptance.py.",
    )
    parser.add_argument(
        "--table",
        type=non_empty_path,
        required=True,
        help="Standalone accepted Markdown table artifact.",
    )
    parser.add_argument(
        "--design-doc",
        type=non_empty_path,
        required=True,
        help="Rendered design-doc snippet artifact.",
    )
    parser.add_argument(
        "--evidence-dir",
        type=non_empty_path,
        default=None,
        help=(
            "Release-evidence archive to reverify. Defaults to evidence_dir "
            "recorded in the accepted JSON."
        ),
    )
    parser.add_argument(
        "--evidence-label",
        type=non_empty_arg,
        default=None,
        help="Evidence label used when rendering the design-doc snippet.",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise FinalBaselineAuditError(f"acceptance JSON is invalid: {err}") from err
    if not isinstance(payload, dict):
        raise FinalBaselineAuditError("acceptance JSON must be an object")
    return payload


def read_text_file(path: Path, label: str) -> str:
    if not path.is_file():
        raise FinalBaselineAuditError(f"{label} does not exist: {path}")
    return path.read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise FinalBaselineAuditError(message)


def normalized_table(payload: dict[str, Any]) -> str:
    try:
        return os_mode_design_doc_baseline.validate_baseline_table(payload.get("baseline_table"))
    except os_mode_design_doc_baseline.DesignDocBaselineError as err:
        raise FinalBaselineAuditError(str(err)) from err


def evidence_dir_from_payload(payload: dict[str, Any], override: Path | None) -> Path:
    if override is not None:
        path = override.expanduser().resolve()
    else:
        recorded = payload.get("evidence_dir")
        require(isinstance(recorded, str) and recorded != "", "accepted JSON is missing evidence_dir")
        path = Path(recorded).expanduser().resolve()
    require(path.is_dir(), f"evidence dir does not exist: {path}")
    recorded = payload.get("evidence_dir")
    if isinstance(recorded, str) and recorded != "":
        require(
            Path(recorded).expanduser().resolve() == path,
            f"--evidence-dir does not match accepted JSON evidence_dir: {path} != {recorded}",
        )
    return path


def requirements_mode(payload: dict[str, Any]) -> tuple[bool, bool]:
    requirements = payload.get("requirements")
    require(isinstance(requirements, dict), "accepted JSON is missing requirements")
    artifact = requirements.get("artifact_manifest")
    pull = requirements.get("pull")
    require(isinstance(artifact, bool), "requirements.artifact_manifest must be a boolean")
    require(isinstance(pull, bool), "requirements.pull must be a boolean")
    return artifact, pull


def comparable_acceptance(payload: dict[str, Any]) -> dict[str, Any]:
    comparable = dict(payload)
    comparable.pop("accepted_at_utc", None)
    return comparable


def audit_final_baseline(
    acceptance_path: Path,
    table_path: Path,
    design_doc_path: Path,
    *,
    evidence_dir: Path | None = None,
    evidence_label: str | None = None,
) -> dict[str, Any]:
    acceptance_path = acceptance_path.expanduser().resolve()
    table_path = table_path.expanduser().resolve()
    design_doc_path = design_doc_path.expanduser().resolve()

    if not acceptance_path.is_file():
        raise FinalBaselineAuditError(f"acceptance JSON does not exist: {acceptance_path}")
    payload = load_json(acceptance_path)
    require(payload.get("schema_version") == 1, "accepted JSON schema_version must be 1")
    require(payload.get("accepted") is True, "accepted JSON does not record accepted=true")
    require(
        payload.get("final_release_baseline") is True,
        "accepted JSON was not created with final_release_baseline=true",
    )

    artifact, pull = requirements_mode(payload)
    evidence = evidence_dir_from_payload(payload, evidence_dir)

    try:
        os_mode_design_doc_baseline.render_snippet(
            payload,
            acceptance_path,
            evidence_label,
            final_release_baseline=True,
        )
    except os_mode_design_doc_baseline.DesignDocBaselineError as err:
        raise FinalBaselineAuditError(str(err)) from err

    current = os_mode_clean_host_acceptance.accept_evidence(
        evidence,
        artifact=artifact,
        pull=pull,
        final_release_baseline=True,
    )
    if comparable_acceptance(current) != comparable_acceptance(payload):
        raise FinalBaselineAuditError("accepted JSON no longer matches strict re-verification of evidence_dir")

    expected_table = normalized_table(payload)
    actual_table = read_text_file(table_path, "--table")
    if actual_table != expected_table:
        raise FinalBaselineAuditError("--table does not match accepted JSON baseline_table")

    expected_snippet = os_mode_design_doc_baseline.render_snippet(
        payload,
        acceptance_path,
        evidence_label,
        final_release_baseline=True,
    )
    actual_snippet = read_text_file(design_doc_path, "--design-doc")
    if actual_snippet != expected_snippet:
        raise FinalBaselineAuditError("--design-doc does not match accepted JSON and evidence label")

    checklist = payload.get("required_checklist")
    require(isinstance(checklist, list), "accepted JSON is missing required_checklist")
    return {
        "accepted_json": str(acceptance_path),
        "accepted_table": str(table_path),
        "design_doc": str(design_doc_path),
        "evidence_dir": str(evidence),
        "evidence_label": evidence_label,
        "artifact": artifact,
        "pull": pull,
        "required_check_count": len(checklist),
        "final_release_baseline": True,
        "audited": True,
    }


def main() -> int:
    args = parse_args()
    try:
        result = audit_final_baseline(
            args.acceptance_json,
            args.table,
            args.design_doc,
            evidence_dir=args.evidence_dir,
            evidence_label=args.evidence_label,
        )
    except (FinalBaselineAuditError, os_mode_clean_host_acceptance.AcceptanceError) as err:
        print(err, file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
