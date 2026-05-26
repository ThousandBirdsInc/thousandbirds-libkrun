#!/usr/bin/env python3
"""Render OS-mode smoke/perf evidence as a product-path baseline table."""

import argparse
import json
import sys
from pathlib import Path
from typing import Any


class BaselineError(Exception):
    pass


def non_empty_path(value: str) -> Path:
    if value == "":
        raise argparse.ArgumentTypeError("path must be non-empty")
    return Path(value)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build a Markdown performance baseline table from release evidence "
            "archives or smoke/perf JSON. Missing timings are rendered as '-' "
            "so clean-host gaps are visible."
        )
    )
    parser.add_argument(
        "--release-evidence",
        type=non_empty_path,
        action="append",
        default=[],
        help=(
            "Path to release-evidence.json or a directory containing it. May "
            "be repeated; associated smoke/perf/source manifests are loaded "
            "from the archive when present."
        ),
    )
    parser.add_argument(
        "--smoke-json",
        type=non_empty_path,
        action="append",
        default=[],
        help="Smoke JSON to summarize. May be repeated.",
    )
    parser.add_argument(
        "--perf-json",
        type=non_empty_path,
        action="append",
        default=[],
        help="Optional perf JSON, matched by index with --smoke-json.",
    )
    parser.add_argument(
        "--source-manifest",
        type=non_empty_path,
        action="append",
        default=[],
        help="Optional source manifest, matched by index with --smoke-json.",
    )
    parser.add_argument(
        "--label",
        action="append",
        default=[],
        help="Optional row label, matched by input order.",
    )
    return parser.parse_args()


def load_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file():
        raise BaselineError(f"{label} does not exist or is not a file: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise BaselineError(f"{label} is invalid JSON: {err}") from err
    if not isinstance(payload, dict):
        raise BaselineError(f"{label} must be a JSON object")
    return payload


def resolve_release_evidence(path: Path) -> tuple[Path, dict[str, Any]]:
    path = path.expanduser().resolve()
    summary_path = path / "release-evidence.json" if path.is_dir() else path
    return summary_path, load_json(summary_path, "release evidence")


def archived_artifact_path(summary_path: Path, summary: dict[str, Any], key: str) -> Path | None:
    artifact = summary.get("artifacts", {}).get(key)
    if not isinstance(artifact, dict):
        return None
    archive = artifact.get("archive")
    if not isinstance(archive, str) or archive == "":
        return None
    path = Path(archive)
    if not path.is_absolute():
        path = summary_path.parent / path
    return path


def nested_get(payload: dict[str, Any], *keys: str) -> Any:
    current: Any = payload
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def int_ms(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int) and value >= 0:
        return value
    if isinstance(value, float) and value >= 0 and value.is_integer():
        return int(value)
    return None


def ms_cell(value: Any) -> str:
    parsed = int_ms(value)
    return "-" if parsed is None else str(parsed)


def first_kernel_log_ms(perf_timings: dict[str, Any]) -> Any:
    value = perf_timings.get("first_kernel_log_ms")
    if int_ms(value) is not None:
        return value
    return perf_timings.get("first_output_ms")


def first_log_ms(smoke_timings: dict[str, Any], perf_timings: dict[str, Any]) -> Any:
    value = first_kernel_log_ms(smoke_timings)
    if int_ms(value) is not None:
        return value
    return first_kernel_log_ms(perf_timings)


def load_pull_export_cell(
    artifact_load: Any,
    image_pull: Any,
    source_manifest: dict[str, Any] | None,
) -> str:
    load = ms_cell(artifact_load)
    pull = ms_cell(image_pull)
    export = "-"
    if source_manifest is not None:
        export = ms_cell(nested_get(source_manifest, "timings_ms", "export_rootfs"))
    if load == "-" and pull == "-" and export == "-":
        return "-"
    return f"{load}/{pull}/{export}"


def clean_poweroff_cell(smoke: dict[str, Any]) -> str:
    waited = smoke.get("wait_exit_after_ready_sec")
    if waited is None:
        return "not checked"
    if smoke.get("ready") is True and smoke.get("failure_reason") is None and smoke.get("exit_code") == 0:
        return "yes"
    return "no"


def evidence_label(
    fallback: str,
    smoke: dict[str, Any],
    perf: dict[str, Any] | None,
    release_summary: dict[str, Any] | None,
) -> str:
    if release_summary is not None:
        image_ref = release_summary.get("image_ref")
        if isinstance(image_ref, str) and image_ref:
            return image_ref
    label = smoke.get("label")
    if isinstance(label, str) and label:
        return label
    if perf is not None:
        label = perf.get("label")
        if isinstance(label, str) and label:
            return label
    return fallback


def row_from_payloads(
    label: str,
    smoke: dict[str, Any],
    perf: dict[str, Any] | None,
    source_manifest: dict[str, Any] | None,
    release_summary: dict[str, Any] | None = None,
) -> dict[str, str]:
    bundle_timings = smoke.get("bundle", {}).get("timings_ms")
    if not isinstance(bundle_timings, dict):
        bundle_timings = {}
    perf_timings = perf.get("timings") if isinstance(perf, dict) else None
    if not isinstance(perf_timings, dict):
        perf_timings = nested_get(release_summary or {}, "perf", "timings_ms")
    if not isinstance(perf_timings, dict):
        perf_timings = {}
    smoke_timings = smoke.get("timings")
    if not isinstance(smoke_timings, dict):
        smoke_timings = nested_get(release_summary or {}, "smoke", "timings_ms")
    if not isinstance(smoke_timings, dict):
        smoke_timings = {}

    total = bundle_timings.get("importer_total")
    if int_ms(total) is None:
        total = smoke.get("elapsed_ms")

    return {
        "Label": evidence_label(label, smoke, perf, release_summary),
        "Image load/pull/export ms": load_pull_export_cell(
            nested_get(release_summary or {}, "artifact", "load_ms"),
            bundle_timings.get("image_pull"),
            source_manifest,
        ),
        "Bundle extraction ms": ms_cell(bundle_timings.get("bundle_extraction")),
        "APFS clone ms": ms_cell(bundle_timings.get("apfs_clone")),
        "First log ms": ms_cell(first_log_ms(smoke_timings, perf_timings)),
        "Root marker ms": ms_cell(perf_timings.get("root_ms")),
        "PID 1 marker ms": ms_cell(perf_timings.get("pid1_ms")),
        "Ready marker ms": ms_cell(perf_timings.get("ready_ms")),
        "Clean poweroff": clean_poweroff_cell(smoke),
        "Total ms": ms_cell(total),
    }


def rows_from_release_evidence(paths: list[Path], labels: list[str]) -> list[dict[str, str]]:
    rows = []
    for index, path in enumerate(paths):
        summary_path, summary = resolve_release_evidence(path)
        smoke_path = archived_artifact_path(summary_path, summary, "smoke_json")
        if smoke_path is None:
            raise BaselineError(f"release evidence is missing smoke_json artifact: {summary_path}")
        smoke = load_json(smoke_path, "smoke JSON")
        perf = None
        perf_path = archived_artifact_path(summary_path, summary, "perf_json")
        if perf_path is not None and perf_path.is_file():
            perf = load_json(perf_path, "perf JSON")
        source_manifest = None
        source_manifest_path = archived_artifact_path(summary_path, summary, "source_manifest")
        if source_manifest_path is not None and source_manifest_path.is_file():
            source_manifest = load_json(source_manifest_path, "source manifest")
        fallback = labels[index] if index < len(labels) else summary_path.parent.name
        rows.append(row_from_payloads(fallback, smoke, perf, source_manifest, summary))
    return rows


def rows_from_direct_inputs(args: argparse.Namespace, label_offset: int) -> list[dict[str, str]]:
    rows = []
    if args.perf_json and len(args.perf_json) not in (1, len(args.smoke_json)):
        raise BaselineError("--perf-json must be supplied once or once per --smoke-json")
    if args.source_manifest and len(args.source_manifest) not in (1, len(args.smoke_json)):
        raise BaselineError("--source-manifest must be supplied once or once per --smoke-json")
    for index, smoke_path in enumerate(args.smoke_json):
        smoke = load_json(smoke_path.expanduser().resolve(), "smoke JSON")
        perf = None
        if args.perf_json:
            perf_index = index if len(args.perf_json) > 1 else 0
            perf = load_json(args.perf_json[perf_index].expanduser().resolve(), "perf JSON")
        source_manifest = None
        if args.source_manifest:
            source_index = index if len(args.source_manifest) > 1 else 0
            source_manifest = load_json(
                args.source_manifest[source_index].expanduser().resolve(),
                "source manifest",
            )
        label_index = label_offset + index
        fallback = args.label[label_index] if label_index < len(args.label) else smoke_path.stem
        rows.append(row_from_payloads(fallback, smoke, perf, source_manifest))
    return rows


def markdown_table(rows: list[dict[str, str]]) -> str:
    headers = [
        "Label",
        "Image load/pull/export ms",
        "Bundle extraction ms",
        "APFS clone ms",
        "First log ms",
        "Root marker ms",
        "PID 1 marker ms",
        "Ready marker ms",
        "Clean poweroff",
        "Total ms",
    ]
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(row.get(header, "-") for header in headers) + " |")
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    try:
        if not args.release_evidence and not args.smoke_json:
            raise BaselineError("provide --release-evidence or --smoke-json")
        rows = rows_from_release_evidence(args.release_evidence, args.label)
        rows.extend(rows_from_direct_inputs(args, len(args.release_evidence)))
    except BaselineError as err:
        print(err, file=sys.stderr)
        return 1
    print(markdown_table(rows), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
