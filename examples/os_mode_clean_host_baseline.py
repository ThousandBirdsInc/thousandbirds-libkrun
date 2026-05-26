#!/usr/bin/env python3
"""Run clean-host preflight followed by the macOS OS-bundle release gate."""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import os_mode_import_container_bundle as importer


class BaselineError(Exception):
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
            "Run os_mode_clean_host_preflight.py and then os_mode_release_gate.py "
            "with matching image, cache, output, runtime, and preflight paths."
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
        help="libkrun.os-bundle.artifact.v1 JSON manifest for archive-delivered samples.",
    )
    parser.add_argument("--output-dir", type=non_empty_path, required=True, help="Release evidence archive directory.")
    parser.add_argument(
        "--preflight-json",
        type=non_empty_path,
        default=None,
        help="Path for preflight JSON. Defaults to OUTPUT_DIR.preflight.json next to --output-dir.",
    )
    parser.add_argument(
        "--cache-dir",
        type=non_empty_path,
        default=None,
        help="Bundle cache root shared by preflight and release gate.",
    )
    parser.add_argument("--name", type=non_empty_arg, default=None, help="Cache entry name.")
    parser.add_argument(
        "--runtime",
        choices=("auto", "docker", "podman"),
        default="auto",
        help="Container runtime used for extraction or artifact load.",
    )
    parser.add_argument(
        "--build-command",
        action="append",
        default=[],
        type=non_empty_arg,
        help="Build or install command to record in release evidence. May be repeated.",
    )
    parser.add_argument(
        "--accept-json-output",
        type=non_empty_path,
        default=None,
        help="Run clean-host acceptance after the release gate and write acceptance JSON.",
    )
    parser.add_argument(
        "--accept-table-output",
        type=non_empty_path,
        default=None,
        help="Run clean-host acceptance after the release gate and write the accepted Markdown table.",
    )
    parser.add_argument(
        "--design-doc-output",
        type=non_empty_path,
        default=None,
        help=(
            "After strict acceptance, render the design-doc baseline snippet to "
            "this path. Requires --accept-json-output."
        ),
    )
    parser.add_argument(
        "--evidence-label",
        type=non_empty_arg,
        default=None,
        help="Evidence label to pass to os_mode_design_doc_baseline.py.",
    )
    parser.add_argument(
        "--final-release-baseline",
        action="store_true",
        help="Pass --final-release-baseline to the design-doc snippet helper.",
    )
    parser.add_argument(
        "--print-only",
        action="store_true",
        help="Print the preflight and release-gate commands without running them.",
    )
    return parser.parse_args()


def default_preflight_json(output_dir: Path) -> Path:
    output = output_dir.expanduser()
    return output.parent / f"{output.name}.preflight.json"


def common_source_args(args: argparse.Namespace) -> list[str]:
    command: list[str] = []
    if args.artifact_manifest is not None:
        if args.image is not None:
            command.append(args.image)
        command.extend(["--artifact-manifest", str(args.artifact_manifest.expanduser().resolve())])
    elif args.image is not None:
        command.append(args.image)
    else:
        raise BaselineError("image is required unless --artifact-manifest is provided")
    return command


def shared_options(args: argparse.Namespace) -> list[str]:
    command: list[str] = []
    if args.cache_dir is not None:
        command.extend(["--cache-dir", str(args.cache_dir.expanduser().resolve())])
    if args.name is not None:
        command.extend(["--name", args.name])
    if args.runtime != "auto":
        command.extend(["--runtime", args.runtime])
    return command


def build_commands(args: argparse.Namespace) -> tuple[list[str], list[str], list[str] | None, list[str] | None, Path]:
    preflight_json = (args.preflight_json or default_preflight_json(args.output_dir)).expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()

    preflight = [
        sys.executable,
        str(importer.REPO_ROOT / "examples" / "os_mode_clean_host_preflight.py"),
        *common_source_args(args),
        "--output-dir",
        str(output_dir),
        *shared_options(args),
        "--json-output",
        str(preflight_json),
    ]
    release_gate = [
        sys.executable,
        str(importer.REPO_ROOT / "examples" / "os_mode_release_gate.py"),
        *common_source_args(args),
        "--output-dir",
        str(output_dir),
        *shared_options(args),
        "--preflight-json",
        str(preflight_json),
        "--clean-host-baseline",
    ]
    for build_command in args.build_command:
        release_gate.extend(["--build-command", build_command])
    acceptance = None
    if args.accept_json_output is not None or args.accept_table_output is not None:
        acceptance = [
            sys.executable,
            str(importer.REPO_ROOT / "examples" / "os_mode_clean_host_acceptance.py"),
            str(output_dir),
        ]
        if args.artifact_manifest is not None:
            acceptance.append("--artifact")
        elif args.image is not None:
            acceptance.append("--pull")
        if args.accept_json_output is not None:
            acceptance.extend(["--json-output", str(args.accept_json_output.expanduser().resolve())])
        if args.accept_table_output is not None:
            acceptance.extend(["--table-output", str(args.accept_table_output.expanduser().resolve())])
        if args.final_release_baseline:
            acceptance.append("--final-release-baseline")
    design_doc = None
    if args.final_release_baseline and args.accept_table_output is None:
        raise BaselineError("--final-release-baseline requires --accept-table-output")
    if args.design_doc_output is not None:
        if args.accept_json_output is None:
            raise BaselineError("--design-doc-output requires --accept-json-output")
        design_doc = [
            sys.executable,
            str(importer.REPO_ROOT / "examples" / "os_mode_design_doc_baseline.py"),
            str(args.accept_json_output.expanduser().resolve()),
            "--output",
            str(args.design_doc_output.expanduser().resolve()),
        ]
        if args.evidence_label is not None:
            design_doc.extend(["--evidence-label", args.evidence_label])
        if args.final_release_baseline:
            design_doc.append("--final-release-baseline")
    elif args.evidence_label is not None or args.final_release_baseline:
        raise BaselineError("--evidence-label and --final-release-baseline require --design-doc-output")
    return preflight, release_gate, acceptance, design_doc, preflight_json


def run_command(command: list[str]) -> None:
    proc = subprocess.run(command)
    if proc.returncode != 0:
        raise BaselineError(f"command failed with status {proc.returncode}: {importer.command_quote(command)}")


def validate_acceptance_outputs(args: argparse.Namespace, preflight_json: Path, output_dir: Path) -> None:
    candidates: list[tuple[str, Path]] = []
    if args.accept_json_output is not None:
        candidates.append(("--accept-json-output", args.accept_json_output.expanduser().resolve()))
    if args.accept_table_output is not None:
        candidates.append(("--accept-table-output", args.accept_table_output.expanduser().resolve()))
    if args.design_doc_output is not None:
        candidates.append(("--design-doc-output", args.design_doc_output.expanduser().resolve()))
    seen: dict[Path, str] = {}
    for option, path in candidates:
        other = seen.get(path)
        if other is not None:
            raise BaselineError(f"{option} must differ from {other}: {path}")
        seen[path] = option
        if path == preflight_json:
            raise BaselineError(f"{option} must differ from --preflight-json: {path}")
        if path == output_dir:
            raise BaselineError(f"{option} must differ from --output-dir: {path}")
        if not path.parent.is_dir():
            raise BaselineError(f"{option} parent directory does not exist: {path.parent}")
        if path.exists():
            raise BaselineError(f"{option} already exists: {path}")


def run_baseline(args: argparse.Namespace) -> dict[str, object]:
    preflight, release_gate, acceptance, design_doc, preflight_json = build_commands(args)
    output_dir = args.output_dir.expanduser().resolve()
    result = {
        "output_dir": str(output_dir),
        "preflight_json": str(preflight_json),
        "preflight_command": preflight,
        "release_gate_command": release_gate,
    }
    if acceptance is not None:
        result["acceptance_command"] = acceptance
    if args.accept_json_output is not None:
        result["accept_json_output"] = str(args.accept_json_output.expanduser().resolve())
    if args.accept_table_output is not None:
        result["accept_table_output"] = str(args.accept_table_output.expanduser().resolve())
    if design_doc is not None:
        result["design_doc_command"] = design_doc
        result["design_doc_output"] = str(args.design_doc_output.expanduser().resolve())
    if args.print_only:
        result["ran"] = False
        return result
    validate_acceptance_outputs(args, preflight_json, output_dir)
    run_command(preflight)
    run_command(release_gate)
    if acceptance is not None:
        run_command(acceptance)
    if design_doc is not None:
        run_command(design_doc)
    result["ran"] = True
    return result


def main() -> int:
    args = parse_args()
    try:
        result = run_baseline(args)
    except BaselineError as err:
        print(err, file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
