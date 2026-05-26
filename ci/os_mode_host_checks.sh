#!/bin/sh
set -eu

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/krun-osmode-host-checks.XXXXXX")
cleanup() {
    rm -rf "$tmpdir"
}
trap cleanup EXIT HUP INT TERM

echo "==> Python helper syntax"
python3 -m py_compile \
    examples/os_mode_build_container_rootfs.py \
    examples/os_mode_baseline_table.py \
    examples/os_mode_design_doc_baseline.py \
    examples/os_mode_final_baseline_audit.py \
    examples/os_mode_collect_release_evidence.py \
    examples/os_mode_verify_release_evidence.py \
    examples/os_mode_clean_host_acceptance.py \
    examples/os_mode_clean_host_preflight.py \
    examples/os_mode_clean_host_baseline.py \
    examples/os_mode_release_gate.py \
    examples/krun_os_run.py \
    examples/os_mode_import_container_bundle.py \
    examples/os_mode_manifest_check.py \
    examples/os_mode_publish_container_bundle.py \
    examples/os_mode_smoke.py \
    examples/os_mode_perf.py

echo "==> Python helper import checks"
python3 examples/os_mode_build_container_rootfs.py --help >/dev/null
python3 examples/os_mode_baseline_table.py --help >/dev/null
python3 examples/os_mode_design_doc_baseline.py --help >/dev/null
python3 examples/os_mode_final_baseline_audit.py --help >/dev/null
python3 examples/os_mode_collect_release_evidence.py --help >/dev/null
python3 examples/os_mode_verify_release_evidence.py --help >/dev/null
python3 examples/os_mode_clean_host_acceptance.py --help >/dev/null
examples/os_mode_clean_host_acceptance.py --help >/dev/null
python3 examples/os_mode_clean_host_preflight.py --help >/dev/null
python3 examples/os_mode_clean_host_baseline.py --help >/dev/null
python3 examples/os_mode_release_gate.py --help >/dev/null
python3 examples/krun_os_run.py --help >/dev/null
python3 examples/os_mode_import_container_bundle.py --help >/dev/null
python3 examples/os_mode_manifest_check.py --help >/dev/null
python3 examples/os_mode_publish_container_bundle.py --help >/dev/null
python3 - "$tmpdir" <<'PY'
import argparse
import copy
import hashlib
import importlib.util
import json
import os
import pathlib
import re
import subprocess
import sys

repo = pathlib.Path.cwd()
sys.path.insert(0, str(repo / "examples"))
spec = importlib.util.spec_from_file_location(
    "os_mode_build_container_rootfs",
    repo / "examples" / "os_mode_build_container_rootfs.py",
)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
manifest_spec = importlib.util.spec_from_file_location(
    "os_mode_manifest_check",
    repo / "examples" / "os_mode_manifest_check.py",
)
manifest_module = importlib.util.module_from_spec(manifest_spec)
assert manifest_spec.loader is not None
manifest_spec.loader.exec_module(manifest_module)
bundle_spec = importlib.util.spec_from_file_location(
    "os_mode_import_container_bundle",
    repo / "examples" / "os_mode_import_container_bundle.py",
)
bundle_module = importlib.util.module_from_spec(bundle_spec)
assert bundle_spec.loader is not None
bundle_spec.loader.exec_module(bundle_module)
runner_spec = importlib.util.spec_from_file_location(
    "krun_os_run",
    repo / "examples" / "krun_os_run.py",
)
runner_module = importlib.util.module_from_spec(runner_spec)
assert runner_spec.loader is not None
runner_spec.loader.exec_module(runner_module)
evidence_spec = importlib.util.spec_from_file_location(
    "os_mode_collect_release_evidence",
    repo / "examples" / "os_mode_collect_release_evidence.py",
)
evidence_module = importlib.util.module_from_spec(evidence_spec)
assert evidence_spec.loader is not None
evidence_spec.loader.exec_module(evidence_module)
verify_evidence_spec = importlib.util.spec_from_file_location(
    "os_mode_verify_release_evidence",
    repo / "examples" / "os_mode_verify_release_evidence.py",
)
verify_evidence_module = importlib.util.module_from_spec(verify_evidence_spec)
assert verify_evidence_spec.loader is not None
verify_evidence_spec.loader.exec_module(verify_evidence_module)
acceptance_spec = importlib.util.spec_from_file_location(
    "os_mode_clean_host_acceptance",
    repo / "examples" / "os_mode_clean_host_acceptance.py",
)
acceptance_module = importlib.util.module_from_spec(acceptance_spec)
assert acceptance_spec.loader is not None
acceptance_spec.loader.exec_module(acceptance_module)
baseline_table_spec = importlib.util.spec_from_file_location(
    "os_mode_baseline_table",
    repo / "examples" / "os_mode_baseline_table.py",
)
baseline_table_module = importlib.util.module_from_spec(baseline_table_spec)
assert baseline_table_spec.loader is not None
baseline_table_spec.loader.exec_module(baseline_table_module)
design_doc_baseline_spec = importlib.util.spec_from_file_location(
    "os_mode_design_doc_baseline",
    repo / "examples" / "os_mode_design_doc_baseline.py",
)
design_doc_baseline_module = importlib.util.module_from_spec(design_doc_baseline_spec)
assert design_doc_baseline_spec.loader is not None
design_doc_baseline_spec.loader.exec_module(design_doc_baseline_module)
final_baseline_audit_spec = importlib.util.spec_from_file_location(
    "os_mode_final_baseline_audit",
    repo / "examples" / "os_mode_final_baseline_audit.py",
)
final_baseline_audit_module = importlib.util.module_from_spec(final_baseline_audit_spec)
assert final_baseline_audit_spec.loader is not None
final_baseline_audit_spec.loader.exec_module(final_baseline_audit_module)
release_gate_spec = importlib.util.spec_from_file_location(
    "os_mode_release_gate",
    repo / "examples" / "os_mode_release_gate.py",
)
release_gate_module = importlib.util.module_from_spec(release_gate_spec)
assert release_gate_spec.loader is not None
release_gate_spec.loader.exec_module(release_gate_module)
preflight_spec = importlib.util.spec_from_file_location(
    "os_mode_clean_host_preflight",
    repo / "examples" / "os_mode_clean_host_preflight.py",
)
preflight_module = importlib.util.module_from_spec(preflight_spec)
assert preflight_spec.loader is not None
preflight_spec.loader.exec_module(preflight_module)
baseline_runner_spec = importlib.util.spec_from_file_location(
    "os_mode_clean_host_baseline",
    repo / "examples" / "os_mode_clean_host_baseline.py",
)
baseline_runner_module = importlib.util.module_from_spec(baseline_runner_spec)
assert baseline_runner_spec.loader is not None
baseline_runner_spec.loader.exec_module(baseline_runner_module)

base_required_checks = list(acceptance_module.BASE_REQUIRED_CHECKS)
expected_checklists = {
    (False, False): base_required_checks,
    (True, False): [*base_required_checks, "artifact delivery"],
    (False, True): [*base_required_checks, "registry pull"],
    (True, True): [*base_required_checks, "artifact delivery", "registry pull"],
}
for (artifact_required, pull_required), expected_names in expected_checklists.items():
    actual_names = list(
        acceptance_module.required_check_names(
            artifact=artifact_required,
            pull=pull_required,
        )
    )
    if actual_names != expected_names:
        raise SystemExit(
            "clean-host acceptance required checklist names were wrong for "
            f"artifact={artifact_required} pull={pull_required}: {actual_names}"
        )
    acceptance_module.validate_required_checklist(
        [
            {
                "name": name,
                "passed": True,
                "evidence": f"synthetic {name}",
            }
            for name in actual_names
        ],
        artifact=artifact_required,
        pull=pull_required,
    )
if "registry pull" in acceptance_module.required_check_names(artifact=True, pull=False):
    raise SystemExit("artifact-only clean-host checklist unexpectedly requires registry pull")
if "artifact delivery" in acceptance_module.required_check_names(artifact=False, pull=True):
    raise SystemExit("pull-only clean-host checklist unexpectedly requires artifact delivery")
try:
    acceptance_module.validate_required_checklist(
        [
            {
                "name": name,
                "passed": True,
                "evidence": f"synthetic {name}",
            }
            for name in expected_checklists[(True, True)]
        ],
        artifact=True,
        pull=False,
    )
except acceptance_module.AcceptanceError as exc:
    if "unexpected items" not in str(exc):
        raise SystemExit(f"artifact-only checklist contamination error was unexpected: {exc}")
else:
    raise SystemExit("artifact-only clean-host checklist accepted registry pull evidence")
try:
    acceptance_module.validate_required_checklist(
        [
            {
                "name": name,
                "passed": True,
                "evidence": f"synthetic {name}",
            }
            for name in expected_checklists[(True, True)]
        ],
        artifact=False,
        pull=True,
    )
except acceptance_module.AcceptanceError as exc:
    if "unexpected items" not in str(exc):
        raise SystemExit(f"pull-only checklist contamination error was unexpected: {exc}")
else:
    raise SystemExit("pull-only clean-host checklist accepted artifact delivery evidence")

durable_artifact_manifest = repo / "os_mode_artifacts" / "debian-systemd-bookworm-arm64" / "libkrun-osmode-debian-systemd-bundle-bookworm-arm64.artifact.json"
if durable_artifact_manifest.is_file():
    durable_artifact = json.loads(durable_artifact_manifest.read_text(encoding="utf-8"))
    durable_commands = durable_artifact.get("commands", {})
    for key in ("clean_host_baseline", "clean_host_baseline_from_artifact"):
        command = durable_commands.get(key)
        if not isinstance(command, list):
            raise SystemExit(f"durable artifact manifest command {key} is missing")
        for required in ("--accept-json-output", "ACCEPTANCE_JSON", "--accept-table-output", "ACCEPTED_BASELINE_MD"):
            if required not in command:
                raise SystemExit(f"durable artifact manifest command {key} missed {required}")
        if "--design-doc-output" in command:
            for required in (
                "DESIGN_DOC_SNIPPET_MD",
                "--evidence-label",
                "RELEASE_EVIDENCE_LABEL",
                "--final-release-baseline",
            ):
                if required not in command:
                    raise SystemExit(f"durable artifact manifest command {key} has incomplete design-doc items")

make_baseline = subprocess.run(
    [
        "make",
        "-n",
        "os-mode-clean-host-baseline",
        "IMAGE=registry.example.com/os@sha256:" + "d" * 64,
        f"OUTPUT_DIR={pathlib.Path(sys.argv[1]) / 'make-baseline-evidence'}",
        f"CACHE_DIR={pathlib.Path(sys.argv[1]) / 'make-baseline-cache'}",
        f"PREFLIGHT_JSON={pathlib.Path(sys.argv[1]) / 'make-baseline-preflight.json'}",
        f"ACCEPT_JSON_OUTPUT={pathlib.Path(sys.argv[1]) / 'make-baseline-acceptance.json'}",
        f"ACCEPT_TABLE_OUTPUT={pathlib.Path(sys.argv[1]) / 'make-baseline.md'}",
        f"DESIGN_DOC_OUTPUT={pathlib.Path(sys.argv[1]) / 'make-baseline-design-doc.md'}",
        "EVIDENCE_LABEL=make-baseline",
        "FINAL_RELEASE_BASELINE=1",
        "RUNTIME=docker",
        "BUILD_COMMAND=make BLK=1 NET=1",
        "PRINT_ONLY=1",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if make_baseline.returncode != 0:
    raise SystemExit(f"make os-mode-clean-host-baseline dry-run failed: {make_baseline.stderr}")
if "examples/os_mode_clean_host_baseline.py" not in make_baseline.stdout:
    raise SystemExit("make os-mode-clean-host-baseline did not invoke the baseline helper")
for required in (
    "--output-dir",
    "--cache-dir",
    "--preflight-json",
    "--accept-json-output",
    "--accept-table-output",
    "--design-doc-output",
    "--evidence-label",
    "--final-release-baseline",
    "--runtime",
    "--build-command",
    "--print-only",
):
    if required not in make_baseline.stdout:
        raise SystemExit(f"make os-mode-clean-host-baseline did not forward {required}")
make_baseline_bad_design_doc = subprocess.run(
    [
        "make",
        "os-mode-clean-host-baseline",
        "IMAGE=registry.example.com/os@sha256:" + "d" * 64,
        f"OUTPUT_DIR={pathlib.Path(sys.argv[1]) / 'make-baseline-evidence'}",
        "EVIDENCE_LABEL=make-baseline",
        "FINAL_RELEASE_BASELINE=1",
        "PRINT_ONLY=1",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if make_baseline_bad_design_doc.returncode == 0:
    raise SystemExit("make os-mode-clean-host-baseline accepted final design-doc options without DESIGN_DOC_OUTPUT")
if "DESIGN_DOC_OUTPUT is required" not in make_baseline_bad_design_doc.stdout:
    raise SystemExit("make os-mode-clean-host-baseline did not explain missing DESIGN_DOC_OUTPUT")
make_baseline_bad_design_doc_acceptance = subprocess.run(
    [
        "make",
        "os-mode-clean-host-baseline",
        "IMAGE=registry.example.com/os@sha256:" + "d" * 64,
        f"OUTPUT_DIR={pathlib.Path(sys.argv[1]) / 'make-baseline-evidence'}",
        f"DESIGN_DOC_OUTPUT={pathlib.Path(sys.argv[1]) / 'make-baseline-design-doc.md'}",
        "PRINT_ONLY=1",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if make_baseline_bad_design_doc_acceptance.returncode == 0:
    raise SystemExit("make os-mode-clean-host-baseline accepted DESIGN_DOC_OUTPUT without ACCEPT_JSON_OUTPUT")
if "ACCEPT_JSON_OUTPUT is required" not in make_baseline_bad_design_doc_acceptance.stdout:
    raise SystemExit("make os-mode-clean-host-baseline did not explain missing ACCEPT_JSON_OUTPUT")
make_baseline_bad_final_table = subprocess.run(
    [
        "make",
        "os-mode-clean-host-baseline",
        "IMAGE=registry.example.com/os@sha256:" + "d" * 64,
        f"OUTPUT_DIR={pathlib.Path(sys.argv[1]) / 'make-baseline-evidence'}",
        f"ACCEPT_JSON_OUTPUT={pathlib.Path(sys.argv[1]) / 'make-baseline-acceptance.json'}",
        f"DESIGN_DOC_OUTPUT={pathlib.Path(sys.argv[1]) / 'make-baseline-design-doc.md'}",
        "FINAL_RELEASE_BASELINE=1",
        "PRINT_ONLY=1",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if make_baseline_bad_final_table.returncode == 0:
    raise SystemExit("make os-mode-clean-host-baseline accepted FINAL_RELEASE_BASELINE=1 without ACCEPT_TABLE_OUTPUT")
if "ACCEPT_TABLE_OUTPUT is required" not in make_baseline_bad_final_table.stdout:
    raise SystemExit("make os-mode-clean-host-baseline did not explain missing ACCEPT_TABLE_OUTPUT")
make_baseline_artifact = subprocess.run(
    [
        "make",
        "-n",
        "os-mode-clean-host-baseline",
        "IMAGE=registry.example.com/os@sha256:" + "e" * 64,
        f"ARTIFACT_MANIFEST={pathlib.Path(sys.argv[1]) / 'make-baseline-artifact.json'}",
        f"OUTPUT_DIR={pathlib.Path(sys.argv[1]) / 'make-baseline-artifact-evidence'}",
        "PRINT_ONLY=1",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if make_baseline_artifact.returncode != 0:
    raise SystemExit(f"make os-mode-clean-host-baseline artifact dry-run failed: {make_baseline_artifact.stderr}")
if "--artifact-manifest" not in make_baseline_artifact.stdout:
    raise SystemExit("make os-mode-clean-host-baseline did not forward ARTIFACT_MANIFEST")
if "registry.example.com/os@sha256:" + "e" * 64 not in make_baseline_artifact.stdout:
    raise SystemExit("make os-mode-clean-host-baseline dropped IMAGE when ARTIFACT_MANIFEST was set")

make_acceptance = subprocess.run(
    [
        "make",
        "-n",
        "os-mode-accept-clean-host",
        f"EVIDENCE_DIR={pathlib.Path(sys.argv[1]) / 'make-acceptance-evidence'}",
        "ARTIFACT=1",
        "PULL=1",
        f"JSON_OUTPUT={pathlib.Path(sys.argv[1]) / 'make-acceptance.json'}",
        f"TABLE_OUTPUT={pathlib.Path(sys.argv[1]) / 'make-acceptance.md'}",
        "FINAL_RELEASE_BASELINE=1",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if make_acceptance.returncode != 0:
    raise SystemExit(f"make os-mode-accept-clean-host dry-run failed: {make_acceptance.stderr}")
if "examples/os_mode_clean_host_acceptance.py" not in make_acceptance.stdout:
    raise SystemExit("make os-mode-accept-clean-host did not invoke the acceptance helper")
if "--artifact" not in make_acceptance.stdout or "--pull" not in make_acceptance.stdout:
    raise SystemExit("make os-mode-accept-clean-host did not forward ARTIFACT/PULL requirements")
if "--json-output" not in make_acceptance.stdout or "--table-output" not in make_acceptance.stdout:
    raise SystemExit("make os-mode-accept-clean-host did not forward output paths")
if "--final-release-baseline" not in make_acceptance.stdout:
    raise SystemExit("make os-mode-accept-clean-host did not forward FINAL_RELEASE_BASELINE")
make_acceptance_bad_final = subprocess.run(
    [
        "make",
        "os-mode-accept-clean-host",
        f"EVIDENCE_DIR={pathlib.Path(sys.argv[1]) / 'make-acceptance-evidence'}",
        "FINAL_RELEASE_BASELINE=1",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if make_acceptance_bad_final.returncode == 0:
    raise SystemExit("make os-mode-accept-clean-host accepted FINAL_RELEASE_BASELINE=1 without JSON_OUTPUT")
if "JSON_OUTPUT is required" not in make_acceptance_bad_final.stdout:
    raise SystemExit("make os-mode-accept-clean-host did not explain missing JSON_OUTPUT for final baseline")
make_acceptance_bad_final_table = subprocess.run(
    [
        "make",
        "os-mode-accept-clean-host",
        f"EVIDENCE_DIR={pathlib.Path(sys.argv[1]) / 'make-acceptance-evidence'}",
        f"JSON_OUTPUT={pathlib.Path(sys.argv[1]) / 'make-acceptance.json'}",
        "FINAL_RELEASE_BASELINE=1",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if make_acceptance_bad_final_table.returncode == 0:
    raise SystemExit("make os-mode-accept-clean-host accepted FINAL_RELEASE_BASELINE=1 without TABLE_OUTPUT")
if "TABLE_OUTPUT is required" not in make_acceptance_bad_final_table.stdout:
    raise SystemExit("make os-mode-accept-clean-host did not explain missing TABLE_OUTPUT for final baseline")
make_design_doc = subprocess.run(
    [
        "make",
        "-n",
        "os-mode-design-doc-baseline",
        f"ACCEPTANCE_JSON={pathlib.Path(sys.argv[1]) / 'make-acceptance.json'}",
        "EVIDENCE_LABEL=synthetic-clean-host",
        f"DESIGN_DOC_OUTPUT={pathlib.Path(sys.argv[1]) / 'make-design-doc-snippet.md'}",
        "FINAL_RELEASE_BASELINE=1",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if make_design_doc.returncode != 0:
    raise SystemExit(f"make os-mode-design-doc-baseline dry-run failed: {make_design_doc.stderr}")
if "examples/os_mode_design_doc_baseline.py" not in make_design_doc.stdout:
    raise SystemExit("make os-mode-design-doc-baseline did not invoke the design-doc helper")
if "--evidence-label" not in make_design_doc.stdout:
    raise SystemExit("make os-mode-design-doc-baseline did not forward EVIDENCE_LABEL")
if "--final-release-baseline" not in make_design_doc.stdout:
    raise SystemExit("make os-mode-design-doc-baseline did not forward FINAL_RELEASE_BASELINE")
if "--output" not in make_design_doc.stdout:
    raise SystemExit("make os-mode-design-doc-baseline did not forward DESIGN_DOC_OUTPUT")
make_final_audit = subprocess.run(
    [
        "make",
        "-n",
        "os-mode-audit-final-baseline",
        f"ACCEPTANCE_JSON={pathlib.Path(sys.argv[1]) / 'make-acceptance.json'}",
        f"TABLE_OUTPUT={pathlib.Path(sys.argv[1]) / 'make-baseline.md'}",
        f"DESIGN_DOC_OUTPUT={pathlib.Path(sys.argv[1]) / 'make-design-doc-snippet.md'}",
        f"EVIDENCE_DIR={pathlib.Path(sys.argv[1]) / 'make-release-evidence'}",
        "EVIDENCE_LABEL=synthetic-clean-host",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if make_final_audit.returncode != 0:
    raise SystemExit(f"make os-mode-audit-final-baseline dry-run failed: {make_final_audit.stderr}")
if "examples/os_mode_final_baseline_audit.py" not in make_final_audit.stdout:
    raise SystemExit("make os-mode-audit-final-baseline did not invoke the final audit helper")
for required in ("--table", "--design-doc", "--evidence-dir", "--evidence-label"):
    if required not in make_final_audit.stdout:
        raise SystemExit(f"make os-mode-audit-final-baseline did not forward {required}")

cache_name = runner_module.image_cache_name("registry.example.com/libkrun-os/debian:bookworm@sha256:" + "a" * 64)
if not re.fullmatch(r"[A-Za-z0-9_.-]+-[0-9a-f]{16}", cache_name):
    raise SystemExit(f"krun_os_run image_cache_name returned an unsafe cache name: {cache_name}")
if not runner_module.image_is_digest_pinned("registry.example.com/os@sha256:" + "b" * 64):
    raise SystemExit("krun_os_run did not detect a digest-pinned image")
if runner_module.image_is_digest_pinned("registry.example.com/os:latest"):
    raise SystemExit("krun_os_run treated a mutable tag as digest-pinned")
release_cache_entry = release_gate_module.cache_entry_for_image(
    "registry.example.com/os@sha256:" + "b" * 64,
    pathlib.Path(sys.argv[1]) / "release-cache",
    None,
)
if release_cache_entry.name != runner_module.image_cache_name("registry.example.com/os@sha256:" + "b" * 64):
    raise SystemExit("release gate did not use the product wrapper cache naming")
clean_report = release_gate_module.require_clean_cache_entry(release_cache_entry)
if clean_report.get("clean") is not True or clean_report.get("exists") is not False:
    raise SystemExit("release gate clean-cache report did not accept an absent cache entry")
release_cache_entry.mkdir(parents=True)
clean_report = release_gate_module.require_clean_cache_entry(release_cache_entry)
if clean_report.get("clean") is not True or clean_report.get("exists") is not True:
    raise SystemExit("release gate clean-cache report did not accept an empty cache entry")
try:
    release_gate_module.require_absent_cache_entry(release_cache_entry)
except release_gate_module.ReleaseGateError as exc:
    if "--require-cache-entry-absent" not in str(exc):
        raise SystemExit(f"release gate absent-cache rejection reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted an empty existing cache entry with --require-cache-entry-absent")
(release_cache_entry / "libkrun-os-bundle").mkdir()
try:
    release_gate_module.require_clean_cache_entry(release_cache_entry)
except release_gate_module.ReleaseGateError as exc:
    if "--require-clean-cache" not in str(exc):
        raise SystemExit(f"release gate clean-cache rejection reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted a non-empty cache entry with --require-clean-cache")
clean_host_args = argparse.Namespace(
    image="registry.example.com/os@sha256:" + "b" * 64,
    artifact_manifest=None,
    output_dir=pathlib.Path(sys.argv[1]) / "clean-host-args",
    cache_dir=pathlib.Path(sys.argv[1]) / "clean-host-cache",
    name=None,
    runtime="auto",
    build_command=[],
    allow_existing_output_dir=False,
    skip_pull=True,
    require_clean_cache=False,
    require_cache_entry_absent=False,
    clean_host_baseline=True,
    preflight_json=None,
)
try:
    release_gate_module.run_release_gate(clean_host_args)
except release_gate_module.ReleaseGateError as exc:
    if "--clean-host-baseline cannot be combined with --skip-pull" not in str(exc):
        raise SystemExit(f"release gate clean-host skip-pull guard reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted --clean-host-baseline with --skip-pull")
clean_host_existing_output_args = copy.copy(clean_host_args)
clean_host_existing_output_args.allow_existing_output_dir = True
clean_host_existing_output_args.skip_pull = False
try:
    release_gate_module.run_release_gate(clean_host_existing_output_args)
except release_gate_module.ReleaseGateError as exc:
    if "requires a fresh output directory" not in str(exc):
        raise SystemExit(f"release gate clean-host output freshness guard reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted --clean-host-baseline with --allow-existing-output-dir")
try:
    release_gate_module.require_digest_pinned("registry.example.com/os:latest")
except release_gate_module.ReleaseGateError:
    pass
else:
    raise SystemExit("release gate accepted a mutable image tag")
release_smoke_command, release_bundle_dir, release_clone, release_smoke = release_gate_module.importer_smoke_command(
    "registry.example.com/os@sha256:" + "b" * 64,
    release_cache_entry,
    "auto",
    "1234-99",
    pull=True,
)
for required in ("--pull", "--run", "--strict-digest", "--reuse-extracted-output-dir"):
    if required not in release_smoke_command:
        raise SystemExit(f"release gate smoke command missed {required}")
if release_bundle_dir != release_cache_entry / "libkrun-os-bundle":
    raise SystemExit("release gate smoke command returned unexpected bundle dir")
if release_clone.name != "release-vm-root-smoke-1234-99.raw":
    raise SystemExit("release gate smoke command returned unexpected clone path")
if release_smoke.name != "release-smoke-1234-99.json":
    raise SystemExit("release gate smoke command returned unexpected smoke path")
release_artifact_dir = pathlib.Path(sys.argv[1]) / "release-artifact"
release_artifact_dir.mkdir()
release_archive = release_artifact_dir / "bundle.tar"
release_archive.write_bytes(b"bundle-archive")
release_artifact_path = release_artifact_dir / "artifact.json"
release_artifact = {
    "schema_version": 1,
    "kind": "libkrun.os-bundle.artifact.v1",
    "digest_ref": "registry.example.com/os@sha256:" + "b" * 64,
    "archive": {
        "path": "/stale/absolute/bundle.tar",
        "sha256": hashlib.sha256(b"bundle-archive").hexdigest(),
        "size_bytes": release_archive.stat().st_size,
        "load_command": ["docker", "load", "-i", "/stale/absolute/bundle.tar"],
    },
    "commands": {
        "clean_host_baseline": [
            "examples/os_mode_clean_host_baseline.py",
            "registry.example.com/os@sha256:" + "b" * 64,
            "--output-dir",
            "RELEASE_EVIDENCE_DIR",
            "--preflight-json",
            "CLEAN_HOST_PREFLIGHT_JSON",
            "--accept-json-output",
            "ACCEPTANCE_JSON",
            "--accept-table-output",
            "ACCEPTED_BASELINE_MD",
            "--design-doc-output",
            "DESIGN_DOC_SNIPPET_MD",
            "--evidence-label",
            "RELEASE_EVIDENCE_LABEL",
            "--final-release-baseline",
        ],
        "clean_host_baseline_from_artifact": [
            "examples/os_mode_clean_host_baseline.py",
            "--artifact-manifest",
            "ARTIFACT_MANIFEST",
            "--output-dir",
            "RELEASE_EVIDENCE_DIR",
            "--preflight-json",
            "CLEAN_HOST_PREFLIGHT_JSON",
            "--accept-json-output",
            "ACCEPTANCE_JSON",
            "--accept-table-output",
            "ACCEPTED_BASELINE_MD",
            "--design-doc-output",
            "DESIGN_DOC_SNIPPET_MD",
            "--evidence-label",
            "RELEASE_EVIDENCE_LABEL",
            "--final-release-baseline",
        ],
    },
}
release_artifact_path.write_text(json.dumps(release_artifact, indent=2) + "\n", encoding="utf-8")
loaded_artifact, loaded_archive = release_gate_module.load_artifact_manifest(release_artifact_path)
if loaded_archive != release_archive.resolve():
    raise SystemExit("release gate did not resolve moved archive next to artifact manifest")
if release_gate_module.artifact_image_reference(loaded_artifact) != "registry.example.com/os@sha256:" + "b" * 64:
    raise SystemExit("release gate did not read digest_ref from artifact manifest")
if release_gate_module.artifact_load_command(loaded_artifact, loaded_archive, "podman") != [
    "podman",
    "load",
    "-i",
    str(loaded_archive),
]:
    raise SystemExit("release gate did not rewrite artifact load command for requested runtime/archive path")
captured_artifact_loads = []
old_release_gate_run_command = release_gate_module.run_command
try:
    release_gate_module.run_command = lambda command: captured_artifact_loads.append(command)
    _artifact, artifact_load_command = release_gate_module.load_artifact_image(release_artifact_path, "docker")
finally:
    release_gate_module.run_command = old_release_gate_run_command
if captured_artifact_loads != [["docker", "load", "-i", str(loaded_archive)]]:
    raise SystemExit(f"release gate did not run expected artifact load command: {captured_artifact_loads}")
if artifact_load_command != captured_artifact_loads[0]:
    raise SystemExit("release gate did not return the artifact load command it ran")
try:
    mismatched_release_args = argparse.Namespace(
        image="registry.example.com/os@sha256:" + "c" * 64,
        artifact_manifest=release_artifact_path,
        output_dir=pathlib.Path(sys.argv[1]) / "release-mismatched-artifact",
        cache_dir=pathlib.Path(sys.argv[1]) / "release-mismatched-cache",
        name=None,
        runtime="auto",
        build_command=[],
        allow_existing_output_dir=False,
        skip_pull=False,
        require_clean_cache=False,
        require_cache_entry_absent=False,
        clean_host_baseline=False,
        preflight_json=None,
    )
    release_gate_module.run_release_gate(mismatched_release_args)
except release_gate_module.ReleaseGateError as exc:
    if "does not match artifact manifest digest_ref" not in str(exc):
        raise SystemExit(f"release gate image/artifact mismatch reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted an IMAGE that disagrees with artifact manifest digest_ref")
bad_release_artifact = dict(release_artifact)
bad_release_artifact["archive"] = dict(release_artifact["archive"])
bad_release_artifact["archive"]["sha256"] = "0" * 64
bad_release_artifact_path = release_artifact_dir / "bad-artifact.json"
bad_release_artifact_path.write_text(json.dumps(bad_release_artifact) + "\n", encoding="utf-8")
try:
    release_gate_module.load_artifact_manifest(bad_release_artifact_path)
except release_gate_module.ReleaseGateError as exc:
    if "SHA-256 mismatch" not in str(exc):
        raise SystemExit(f"release gate artifact SHA mismatch reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted an artifact archive with the wrong SHA-256")
preflight_cache = pathlib.Path(sys.argv[1]) / "preflight-cache"
preflight_output = pathlib.Path(sys.argv[1]) / "preflight-output"
preflight_args = argparse.Namespace(
    image=None,
    artifact_manifest=release_artifact_path,
    output_dir=preflight_output,
    cache_dir=preflight_cache,
    name=None,
    runtime="auto",
    allow_existing_output_dir=False,
    allow_existing_empty_cache_entry=False,
    json_output=pathlib.Path(sys.argv[1]) / "preflight.json",
    require_macos_arm64=False,
    require_apfs=False,
    require_runtime=False,
)
def make_release_gate_preflight(payload):
    payload["host"] = {"system": "Darwin", "machine": "arm64", "macos": {"productVersion": "test"}}
    payload["runtime"]["selected"] = "docker"
    payload["apfs"] = [
        {"label": "bundle_cache_entry", "info": {"is_apfs": True}},
        {"label": "release_evidence_output", "info": {"is_apfs": True}},
    ]
    return payload
def remove_command_option(command, option):
    result = []
    skip_next = False
    for item in command:
        if skip_next:
            skip_next = False
            continue
        if item == option:
            skip_next = True
            continue
        result.append(item)
    return result
def move_command_option_pair_before(command, option, before_option):
    result = list(command)
    option_index = result.index(option)
    pair = result[option_index:option_index + 2]
    del result[option_index:option_index + 2]
    before_index = result.index(before_option)
    result[before_index:before_index] = pair
    return result
preflight = preflight_module.run_preflight(preflight_args)
if preflight.get("ok") is not True:
    raise SystemExit(f"clean-host preflight rejected an absent cache/output setup: {preflight.get('errors')}")
make_release_gate_preflight(preflight)
if preflight.get("image_ref") != release_artifact["digest_ref"]:
    raise SystemExit("clean-host preflight did not use the artifact manifest digest_ref")
if preflight.get("artifact_manifest", {}).get("archive") != str(release_archive.resolve()):
    raise SystemExit("clean-host preflight did not resolve the artifact archive")
if preflight.get("cache_entry", {}).get("exists") is not False:
    raise SystemExit("clean-host preflight did not report the absent cache entry")
if "--clean-host-baseline" not in preflight.get("release_gate_command", []):
    raise SystemExit("clean-host preflight did not emit a clean-host release gate command")
if "--preflight-json" not in preflight.get("release_gate_command", []):
    raise SystemExit("clean-host preflight did not emit a release gate command bound to --preflight-json")
if str(preflight_args.json_output.resolve()) not in preflight.get("release_gate_command", []):
    raise SystemExit("clean-host preflight release gate command did not include the preflight JSON path")
if "--cache-dir" not in preflight.get("release_gate_command", []):
    raise SystemExit("clean-host preflight release gate command did not include an explicit cache dir")
preflight_command_cache_index = preflight["release_gate_command"].index("--cache-dir")
if preflight["release_gate_command"][preflight_command_cache_index + 1] != str(preflight_cache.resolve()):
    raise SystemExit("clean-host preflight release gate command did not include the resolved cache dir")
preflight_args.json_output.write_text(json.dumps(preflight, indent=2) + "\n", encoding="utf-8")
validated_artifact_only_preflight_path = release_gate_module.validate_clean_host_preflight(
    preflight_args.json_output,
    image=release_artifact["digest_ref"],
    cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
    output_dir=preflight_output.resolve(),
    artifact_manifest=release_artifact_path,
    image_was_explicit=False,
)
if validated_artifact_only_preflight_path != preflight_args.json_output.resolve():
    raise SystemExit("release gate returned unexpected artifact-only validated preflight path")
bad_artifact_only_preflight = copy.deepcopy(preflight)
bad_artifact_only_preflight["release_gate_command"] = list(preflight["release_gate_command"])
bad_artifact_only_path = pathlib.Path(sys.argv[1]) / "preflight-artifact-only-with-image.json"
preflight_option_index = bad_artifact_only_preflight["release_gate_command"].index("--preflight-json")
bad_artifact_only_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_artifact_only_path
)
bad_artifact_only_preflight["release_gate_command"].insert(1, release_artifact["digest_ref"])
bad_artifact_only_path.write_text(json.dumps(bad_artifact_only_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_artifact_only_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
        image_was_explicit=False,
    )
except release_gate_module.ReleaseGateError as exc:
    if "positional image does not match release gate invocation" not in str(exc):
        raise SystemExit(f"release gate artifact-only positional image error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted an artifact-only preflight command with a positional image")
missing_json_preflight_args = copy.copy(preflight_args)
missing_json_preflight_args.json_output = None
missing_json_preflight = preflight_module.run_preflight(missing_json_preflight_args)
if missing_json_preflight.get("ok") is not False or not any(
    "--json-output is required" in error for error in missing_json_preflight.get("errors", [])
):
    raise SystemExit("clean-host preflight accepted a run without reusable JSON output")
preflight_args_with_image = copy.copy(preflight_args)
preflight_args_with_image.image = release_artifact["digest_ref"]
preflight_args_with_image.json_output = pathlib.Path(sys.argv[1]) / "preflight-with-image.json"
preflight_with_image = preflight_module.run_preflight(preflight_args_with_image)
if preflight_with_image.get("ok") is not True:
    raise SystemExit(
        "clean-host preflight rejected matching IMAGE plus artifact manifest: "
        f"{preflight_with_image.get('errors')}"
    )
make_release_gate_preflight(preflight_with_image)
if release_artifact["digest_ref"] not in preflight_with_image.get("release_gate_command", []):
    raise SystemExit("clean-host preflight release-gate command dropped explicit IMAGE")
preflight_args_with_image.json_output.write_text(json.dumps(preflight_with_image, indent=2) + "\n", encoding="utf-8")
validated_preflight_path = release_gate_module.validate_clean_host_preflight(
    preflight_args_with_image.json_output,
    image=release_artifact["digest_ref"],
    cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
    output_dir=preflight_output.resolve(),
    artifact_manifest=release_artifact_path,
)
if validated_preflight_path != preflight_args_with_image.json_output.resolve():
    raise SystemExit("release gate returned unexpected validated preflight path")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["schema_version"] = 2
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-wrong-schema.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "schema_version must be 1" not in str(exc):
        raise SystemExit(f"release gate preflight schema-version error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight with the wrong schema version")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["errors"] = ["forced preflight error"]
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-recorded-errors.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "recorded errors" not in str(exc):
        raise SystemExit(f"release gate preflight recorded-errors error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight with recorded errors")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["created_at_utc"] = "2026-05-18 01:00:00"
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-bad-created-at.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "created_at_utc must be an ISO 8601 UTC timestamp ending in Z" not in str(exc):
        raise SystemExit(f"release gate preflight timestamp error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight with a malformed timestamp")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-wrong-command-helper.json"
bad_command_preflight["release_gate_command"][0] = str(repo / "examples" / "not_release_gate.py")
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "executable is not os_mode_release_gate.py" not in str(exc):
        raise SystemExit(f"release gate preflight command/helper mismatch reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command bound to a different helper")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-wrong-command-image.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight["release_gate_command"][1] = "registry.example.com/os@sha256:" + "1" * 64
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "positional image does not match" not in str(exc):
        raise SystemExit(f"release gate preflight command/image mismatch reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command bound to a different positional image")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    pathlib.Path(sys.argv[1]) / "other-preflight.json"
)
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-wrong-command-preflight.json"
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "--preflight-json does not match" not in str(exc):
        raise SystemExit(f"release gate preflight command/preflight mismatch reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command bound to a different preflight JSON")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-wrong-command-output.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
output_option_index = bad_command_preflight["release_gate_command"].index("--output-dir")
bad_command_preflight["release_gate_command"][output_option_index + 1] = str(
    pathlib.Path(sys.argv[1]) / "other-output"
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "--output-dir does not match" not in str(exc):
        raise SystemExit(f"release gate preflight command/output mismatch reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command bound to a different output directory")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-allows-existing-output.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight["release_gate_command"].append("--allow-existing-output-dir")
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "must not include --allow-existing-output-dir" not in str(exc):
        raise SystemExit(f"release gate preflight allow-existing-output error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command that allowed an existing output directory")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-skips-pull.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight["release_gate_command"].append("--skip-pull")
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "must not include --skip-pull" not in str(exc):
        raise SystemExit(f"release gate preflight skip-pull error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command that skipped registry pulls")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-unknown-option.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
baseline_option_index = bad_command_preflight["release_gate_command"].index("--clean-host-baseline")
bad_command_preflight["release_gate_command"][baseline_option_index:baseline_option_index] = [
    "--build-command",
    "make BLK=1 NET=1",
]
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "unexpected option: --build-command" not in str(exc):
        raise SystemExit(f"release gate preflight unknown-option error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command with an unexpected option")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-trailing-positional.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
baseline_option_index = bad_command_preflight["release_gate_command"].index("--clean-host-baseline")
bad_command_preflight["release_gate_command"].insert(baseline_option_index, "trailing-positional")
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "unexpected positional argument after options" not in str(exc):
        raise SystemExit(f"release gate preflight trailing positional error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command with a trailing positional")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-repeated-clean-host-flag.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight["release_gate_command"].append("--clean-host-baseline")
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "repeats option: --clean-host-baseline" not in str(exc):
        raise SystemExit(f"release gate preflight repeated-baseline-flag error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command with repeated --clean-host-baseline")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-baseline-not-last.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight["release_gate_command"].extend(["--name", "after-baseline"])
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "must end with --clean-host-baseline" not in str(exc):
        raise SystemExit(f"release gate preflight baseline-last error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command with arguments after --clean-host-baseline")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = move_command_option_pair_before(
    preflight_with_image["release_gate_command"],
    "--cache-dir",
    "--output-dir",
)
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-wrong-command-order.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "options are not in preflight-generated order" not in str(exc):
        raise SystemExit(f"release gate preflight option-order error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command with reordered options")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["host"] = dict(preflight_with_image["host"])
bad_command_preflight["host"]["system"] = "Linux"
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-wrong-host-system.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "not collected on macOS/Darwin" not in str(exc):
        raise SystemExit(f"release gate preflight host-system error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a non-macOS preflight")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["host"] = dict(preflight_with_image["host"])
bad_command_preflight["host"]["machine"] = "x86_64"
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-wrong-host-machine.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "not collected on arm64" not in str(exc):
        raise SystemExit(f"release gate preflight host-machine error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a non-arm64 preflight")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["apfs"] = [
    {"label": "bundle_cache_entry", "info": {"is_apfs": False}},
    {"label": "release_evidence_output", "info": {"is_apfs": True}},
]
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-failed-apfs.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "APFS check failed" not in str(exc):
        raise SystemExit(f"release gate preflight APFS error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight with failed APFS evidence")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight.pop("runtime", None)
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-missing-runtime.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "missing runtime" not in str(exc):
        raise SystemExit(f"release gate preflight missing-runtime error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight without runtime metadata")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["runtime"] = dict(preflight_with_image["runtime"])
bad_command_preflight["runtime"]["requested"] = "podman"
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-wrong-runtime-metadata.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "runtime requested mode does not match" not in str(exc):
        raise SystemExit(f"release gate preflight runtime metadata mismatch reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted a preflight with different runtime metadata")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["runtime"] = dict(preflight_with_image["runtime"])
bad_command_preflight["runtime"]["selected"] = ""
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-empty-selected-runtime.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "selected runtime" not in str(exc):
        raise SystemExit(f"release gate preflight selected-runtime error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight without a selected runtime")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["runtime"] = dict(preflight_with_image["runtime"])
bad_command_preflight["runtime"]["selected"] = "containerd"
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-invalid-selected-runtime.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "selected mode is invalid" not in str(exc):
        raise SystemExit(f"release gate preflight invalid selected-runtime error was unexpected: {exc}")
else:
    raise SystemExit("release gate accepted a preflight with an invalid selected runtime")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["runtime"] = dict(preflight_with_image["runtime"])
bad_command_preflight["runtime"]["requested"] = "docker"
bad_command_preflight["runtime"]["selected"] = "podman"
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index:preflight_option_index] = ["--runtime", "docker"]
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-selected-runtime-mismatch.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
        runtime="docker",
    )
except release_gate_module.ReleaseGateError as exc:
    if "selected mode does not match" not in str(exc):
        raise SystemExit(f"release gate preflight selected-runtime mismatch reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted a selected runtime that disagreed with explicit runtime")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-wrong-command-runtime.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
bad_command_preflight["release_gate_command"][preflight_option_index:preflight_option_index] = ["--runtime", "podman"]
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "--runtime does not match" not in str(exc):
        raise SystemExit(f"release gate preflight command/runtime mismatch reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command bound to a different runtime")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-wrong-command-cache.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
cache_option_index = bad_command_preflight["release_gate_command"].index("--cache-dir")
bad_command_preflight["release_gate_command"][cache_option_index + 1] = str(
    pathlib.Path(sys.argv[1]) / "other-cache"
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "cache options do not match" not in str(exc):
        raise SystemExit(f"release gate preflight command/cache mismatch reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command bound to a different cache entry")
bad_command_preflight = copy.deepcopy(preflight_with_image)
bad_command_preflight["release_gate_command"] = list(preflight_with_image["release_gate_command"])
bad_command_preflight_path = pathlib.Path(sys.argv[1]) / "preflight-wrong-command-artifact.json"
preflight_option_index = bad_command_preflight["release_gate_command"].index("--preflight-json")
bad_command_preflight["release_gate_command"][preflight_option_index + 1] = str(
    bad_command_preflight_path
)
artifact_option_index = bad_command_preflight["release_gate_command"].index("--artifact-manifest")
bad_command_preflight["release_gate_command"][artifact_option_index + 1] = str(
    release_artifact_dir / "other-artifact.json"
)
bad_command_preflight_path.write_text(json.dumps(bad_command_preflight, indent=2) + "\n", encoding="utf-8")
try:
    release_gate_module.validate_clean_host_preflight(
        bad_command_preflight_path,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_path,
    )
except release_gate_module.ReleaseGateError as exc:
    if "--artifact-manifest does not match" not in str(exc):
        raise SystemExit(f"release gate preflight command/artifact mismatch reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted a preflight command bound to a different artifact manifest")
try:
    release_gate_module.validate_clean_host_preflight(
        preflight_args_with_image.json_output,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=release_artifact_dir / "other-artifact.json",
    )
except release_gate_module.ReleaseGateError as exc:
    if "artifact_manifest path does not match" not in str(exc):
        raise SystemExit(f"release gate preflight artifact mismatch reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted a preflight for a different artifact manifest")
try:
    release_gate_module.validate_clean_host_preflight(
        preflight_args_with_image.json_output,
        image=release_artifact["digest_ref"],
        cache_entry=release_gate_module.cache_entry_for_image(release_artifact["digest_ref"], preflight_cache, None),
        output_dir=preflight_output.resolve(),
        artifact_manifest=None,
    )
except release_gate_module.ReleaseGateError as exc:
    if "artifact manifest for registry release gate" not in str(exc):
        raise SystemExit(f"release gate registry/artifact preflight guard reported unexpected error: {exc}")
else:
    raise SystemExit("release gate accepted artifact preflight for registry release gate")
preflight_args_bad_image = copy.copy(preflight_args)
preflight_args_bad_image.image = "registry.example.com/os@sha256:" + "0" * 64
preflight_bad_image = preflight_module.run_preflight(preflight_args_bad_image)
if preflight_bad_image.get("ok") is not False or not any(
    "IMAGE does not match artifact manifest digest_ref" in error
    for error in preflight_bad_image.get("errors", [])
):
    raise SystemExit("clean-host preflight accepted IMAGE/artifact digest mismatch")
preflight_json_path = pathlib.Path(sys.argv[1]) / "preflight-existing.json"
preflight_json_path.write_text("{}\n", encoding="utf-8")
preflight_args.json_output = preflight_json_path
preflight_existing_json = preflight_module.run_preflight(preflight_args)
if preflight_existing_json.get("ok") is not False or not any(
    "--json-output destination already exists" in error for error in preflight_existing_json.get("errors", [])
):
    raise SystemExit("clean-host preflight accepted an existing JSON output path")
preflight_args.json_output = pathlib.Path(sys.argv[1]) / "preflight-cache-tests.json"
empty_preflight_cache_entry = release_gate_module.cache_entry_for_image(
    release_artifact["digest_ref"],
    preflight_cache,
    None,
)
empty_preflight_cache_entry.mkdir(parents=True)
preflight_existing_cache = preflight_module.run_preflight(preflight_args)
if preflight_existing_cache.get("ok") is not False or not any(
    "cache entry to be absent" in error for error in preflight_existing_cache.get("errors", [])
):
    raise SystemExit("clean-host preflight accepted an existing cache entry without explicit allowance")
preflight_args.allow_existing_empty_cache_entry = True
preflight_existing_empty_cache = preflight_module.run_preflight(preflight_args)
if preflight_existing_empty_cache.get("ok") is not False or not any(
    "cannot be used for clean-host baseline preflight" in error
    for error in preflight_existing_empty_cache.get("errors", [])
):
    raise SystemExit(
        "clean-host preflight accepted --allow-existing-empty-cache-entry: "
        f"{preflight_existing_empty_cache.get('errors')}"
    )
(empty_preflight_cache_entry / "libkrun-os-bundle").mkdir()
preflight_nonempty_cache = preflight_module.run_preflight(preflight_args)
if preflight_nonempty_cache.get("ok") is not False or not any(
    "cache entry to be absent" in error for error in preflight_nonempty_cache.get("errors", [])
):
    raise SystemExit("clean-host preflight accepted a non-empty cache entry")
preflight_args.allow_existing_empty_cache_entry = False
preflight_args.output_dir.mkdir()
preflight_existing_output = preflight_module.run_preflight(preflight_args)
if preflight_existing_output.get("ok") is not False or not any(
    "requires --output-dir to be absent" in error for error in preflight_existing_output.get("errors", [])
):
    raise SystemExit("clean-host preflight accepted an existing output dir without explicit allowance")
(preflight_args.output_dir / "stale.json").write_text("{}\n", encoding="utf-8")
preflight_args.allow_existing_output_dir = True
preflight_nonempty_output = preflight_module.run_preflight(preflight_args)
if preflight_nonempty_output.get("ok") is not False or not any(
    "--output-dir already contains files" in error for error in preflight_nonempty_output.get("errors", [])
):
    raise SystemExit("clean-host preflight accepted a non-empty output dir")
mutable_preflight_args = copy.copy(preflight_args)
mutable_preflight_args.image = "registry.example.com/os:latest"
mutable_preflight_args.artifact_manifest = None
mutable_preflight_args.output_dir = pathlib.Path(sys.argv[1]) / "mutable-preflight-output"
mutable_preflight_args.cache_dir = pathlib.Path(sys.argv[1]) / "mutable-preflight-cache"
mutable_preflight_args.allow_existing_output_dir = False
mutable_preflight_args.allow_existing_empty_cache_entry = False
preflight_mutable = preflight_module.run_preflight(mutable_preflight_args)
if preflight_mutable.get("ok") is not False or not any(
    "digest-pinned" in error for error in preflight_mutable.get("errors", [])
):
    raise SystemExit("clean-host preflight accepted a mutable image reference")
baseline_output = pathlib.Path(sys.argv[1]) / "baseline-runner-output"
baseline_args = argparse.Namespace(
    image=None,
    artifact_manifest=release_artifact_path,
    output_dir=baseline_output,
    preflight_json=None,
    cache_dir=pathlib.Path(sys.argv[1]) / "baseline-runner-cache",
    name="sample",
    runtime="podman",
    build_command=["make BLK=1 NET=1"],
    accept_json_output=pathlib.Path(sys.argv[1]) / "baseline-acceptance.json",
    accept_table_output=pathlib.Path(sys.argv[1]) / "baseline-acceptance.md",
    design_doc_output=pathlib.Path(sys.argv[1]) / "baseline-design-doc.md",
    evidence_label="baseline-runner",
    final_release_baseline=True,
    print_only=True,
)
preflight_command, release_gate_command, acceptance_command, design_doc_command, baseline_preflight_json = baseline_runner_module.build_commands(baseline_args)
if baseline_preflight_json != (baseline_output.parent / f"{baseline_output.name}.preflight.json").resolve():
    raise SystemExit("clean-host baseline runner chose an unexpected default preflight path")
for command, label in ((preflight_command, "preflight"), (release_gate_command, "release gate")):
    for required in ("--artifact-manifest", str(release_artifact_path.resolve()), "--output-dir", str(baseline_output.resolve()), "--cache-dir", str((pathlib.Path(sys.argv[1]) / "baseline-runner-cache").resolve()), "--name", "sample", "--runtime", "podman"):
        if required not in command:
            raise SystemExit(f"clean-host baseline runner {label} command missed {required}")
baseline_args_with_image = copy.copy(baseline_args)
baseline_args_with_image.image = "registry.example.com/os@sha256:" + "f" * 64
preflight_with_image, release_with_image, _, _, _ = baseline_runner_module.build_commands(baseline_args_with_image)
for command, label in ((preflight_with_image, "preflight"), (release_with_image, "release gate")):
    if baseline_args_with_image.image not in command:
        raise SystemExit(
            "clean-host baseline runner dropped explicit IMAGE for "
            f"{label} when --artifact-manifest was set"
        )
if "--json-output" not in preflight_command:
    raise SystemExit("clean-host baseline runner preflight command missed --json-output")
if "--preflight-json" not in release_gate_command or "--clean-host-baseline" not in release_gate_command:
    raise SystemExit("clean-host baseline runner release gate command missed preflight/baseline options")
if "--build-command" not in release_gate_command or "make BLK=1 NET=1" not in release_gate_command:
    raise SystemExit("clean-host baseline runner release gate command missed build command")
if acceptance_command is None:
    raise SystemExit("clean-host baseline runner did not build an acceptance command")
for required in (str(baseline_output.resolve()), "--artifact", "--json-output", str((pathlib.Path(sys.argv[1]) / "baseline-acceptance.json").resolve()), "--table-output", str((pathlib.Path(sys.argv[1]) / "baseline-acceptance.md").resolve()), "--final-release-baseline"):
    if required not in acceptance_command:
        raise SystemExit(f"clean-host baseline runner acceptance command missed {required}")
if design_doc_command is None:
    raise SystemExit("clean-host baseline runner did not build a design-doc command")
for required in (
    str((pathlib.Path(sys.argv[1]) / "baseline-acceptance.json").resolve()),
    "--output",
    str((pathlib.Path(sys.argv[1]) / "baseline-design-doc.md").resolve()),
    "--evidence-label",
    "baseline-runner",
    "--final-release-baseline",
):
    if required not in design_doc_command:
        raise SystemExit(f"clean-host baseline runner design-doc command missed {required}")
captured_baseline_commands = []
baseline_args.print_only = False
old_baseline_run_command = baseline_runner_module.run_command
baseline_design_doc_output = pathlib.Path(sys.argv[1]) / "baseline-design-doc.md"
try:
    def fake_baseline_run_command(command):
        captured_baseline_commands.append(command)
        if command == design_doc_command:
            baseline_design_doc_output.write_text("design doc snippet\n", encoding="utf-8")

    baseline_runner_module.run_command = fake_baseline_run_command
    baseline_result = baseline_runner_module.run_baseline(baseline_args)
finally:
    baseline_runner_module.run_command = old_baseline_run_command
if captured_baseline_commands != [preflight_command, release_gate_command, acceptance_command, design_doc_command]:
    raise SystemExit(f"clean-host baseline runner executed unexpected commands: {captured_baseline_commands}")
if baseline_result.get("ran") is not True:
    raise SystemExit("clean-host baseline runner did not report ran=true")
if baseline_result.get("output_dir") != str(baseline_output.resolve()):
    raise SystemExit("clean-host baseline runner did not report output_dir")
if "acceptance_command" not in baseline_result:
    raise SystemExit("clean-host baseline runner did not report the acceptance command")
if "design_doc_command" not in baseline_result:
    raise SystemExit("clean-host baseline runner did not report the design-doc command")
if baseline_result.get("accept_json_output") != str((pathlib.Path(sys.argv[1]) / "baseline-acceptance.json").resolve()):
    raise SystemExit("clean-host baseline runner did not report accept_json_output")
if baseline_result.get("accept_table_output") != str((pathlib.Path(sys.argv[1]) / "baseline-acceptance.md").resolve()):
    raise SystemExit("clean-host baseline runner did not report accept_table_output")
if baseline_result.get("design_doc_output") != str(baseline_design_doc_output.resolve()):
    raise SystemExit("clean-host baseline runner did not report design_doc_output")
if baseline_design_doc_output.read_text(encoding="utf-8") != "design doc snippet\n":
    raise SystemExit("clean-host baseline runner did not write design-doc output after helper success")
failed_design_doc_output = pathlib.Path(sys.argv[1]) / "baseline-design-doc-failed.md"
failed_design_doc_args = copy.copy(baseline_args)
failed_design_doc_args.design_doc_output = failed_design_doc_output
captured_failed_design_doc_commands = []
try:
    def fake_failed_design_doc_run_command(command):
        captured_failed_design_doc_commands.append(command)
        if "--output" in command and str(failed_design_doc_output.resolve()) in command:
            raise baseline_runner_module.BaselineError("synthetic design-doc failure")

    baseline_runner_module.run_command = fake_failed_design_doc_run_command
    try:
        baseline_runner_module.run_baseline(failed_design_doc_args)
    except baseline_runner_module.BaselineError as exc:
        if "synthetic design-doc failure" not in str(exc):
            raise SystemExit(f"clean-host baseline runner reported unexpected design-doc failure: {exc}")
    else:
        raise SystemExit("clean-host baseline runner accepted a failing design-doc helper")
finally:
    baseline_runner_module.run_command = old_baseline_run_command
if failed_design_doc_output.exists():
    raise SystemExit("clean-host baseline runner wrote design-doc output after helper failure")
bad_baseline_args = copy.copy(baseline_args)
bad_baseline_args.accept_table_output = bad_baseline_args.accept_json_output
try:
    baseline_runner_module.run_baseline(bad_baseline_args)
except baseline_runner_module.BaselineError as exc:
    if "must differ" not in str(exc):
        raise SystemExit(f"clean-host baseline runner same-output rejection reported unexpected error: {exc}")
else:
    raise SystemExit("clean-host baseline runner accepted identical acceptance output paths")
bad_baseline_args = copy.copy(baseline_args)
bad_baseline_args.design_doc_output = bad_baseline_args.accept_json_output
try:
    baseline_runner_module.run_baseline(bad_baseline_args)
except baseline_runner_module.BaselineError as exc:
    if "must differ" not in str(exc):
        raise SystemExit(f"clean-host baseline runner design-doc collision reported unexpected error: {exc}")
else:
    raise SystemExit("clean-host baseline runner accepted design-doc output colliding with acceptance JSON")
bad_baseline_args = copy.copy(baseline_args)
bad_baseline_args.accept_table_output = baseline_preflight_json
try:
    baseline_runner_module.run_baseline(bad_baseline_args)
except baseline_runner_module.BaselineError as exc:
    if "must differ from --preflight-json" not in str(exc):
        raise SystemExit(f"clean-host baseline runner preflight collision reported unexpected error: {exc}")
else:
    raise SystemExit("clean-host baseline runner accepted acceptance output colliding with preflight JSON")
existing_acceptance_output = pathlib.Path(sys.argv[1]) / "baseline-existing-acceptance.json"
existing_acceptance_output.write_text("{}\n", encoding="utf-8")
bad_baseline_args = copy.copy(baseline_args)
bad_baseline_args.accept_json_output = existing_acceptance_output
try:
    baseline_runner_module.run_baseline(bad_baseline_args)
except baseline_runner_module.BaselineError as exc:
    if "already exists" not in str(exc):
        raise SystemExit(f"clean-host baseline runner existing acceptance output reported unexpected error: {exc}")
else:
    raise SystemExit("clean-host baseline runner accepted an existing acceptance output path")
bad_baseline_args = copy.copy(baseline_args)
bad_baseline_args.accept_json_output = pathlib.Path(sys.argv[1]) / "missing-acceptance-parent" / "acceptance.json"
try:
    baseline_runner_module.run_baseline(bad_baseline_args)
except baseline_runner_module.BaselineError as exc:
    if "parent directory does not exist" not in str(exc):
        raise SystemExit(f"clean-host baseline runner missing parent reported unexpected error: {exc}")
else:
    raise SystemExit("clean-host baseline runner accepted an acceptance output path with a missing parent")
bad_baseline_args = copy.copy(baseline_args)
bad_baseline_args.accept_json_output = None
try:
    baseline_runner_module.build_commands(bad_baseline_args)
except baseline_runner_module.BaselineError as exc:
    if "--design-doc-output requires --accept-json-output" not in str(exc):
        raise SystemExit(f"clean-host baseline runner missing acceptance JSON reported unexpected error: {exc}")
else:
    raise SystemExit("clean-host baseline runner accepted design-doc output without acceptance JSON")
bad_baseline_args = copy.copy(baseline_args)
bad_baseline_args.accept_table_output = None
try:
    baseline_runner_module.build_commands(bad_baseline_args)
except baseline_runner_module.BaselineError as exc:
    if "--final-release-baseline requires --accept-table-output" not in str(exc):
        raise SystemExit(f"clean-host baseline runner final-table guard reported unexpected error: {exc}")
else:
    raise SystemExit("clean-host baseline runner accepted final baseline without an accepted table output")
bad_baseline_args = copy.copy(baseline_args)
bad_baseline_args.design_doc_output = None
try:
    baseline_runner_module.build_commands(bad_baseline_args)
except baseline_runner_module.BaselineError as exc:
    if "--evidence-label and --final-release-baseline require --design-doc-output" not in str(exc):
        raise SystemExit(f"clean-host baseline runner orphan design-doc options reported unexpected error: {exc}")
else:
    raise SystemExit("clean-host baseline runner accepted design-doc-only options without design-doc output")
registry_baseline_args = argparse.Namespace(
    image="registry.example.com/os@sha256:" + "e" * 64,
    artifact_manifest=None,
    output_dir=pathlib.Path(sys.argv[1]) / "baseline-registry-output",
    preflight_json=None,
    cache_dir=None,
    name=None,
    runtime="auto",
    build_command=[],
    accept_json_output=None,
    accept_table_output=pathlib.Path(sys.argv[1]) / "baseline-registry.md",
    design_doc_output=None,
    evidence_label=None,
    final_release_baseline=False,
    print_only=True,
)
_registry_preflight, _registry_gate, registry_acceptance, _registry_design_doc, _registry_preflight_json = baseline_runner_module.build_commands(registry_baseline_args)
if registry_acceptance is None or "--pull" not in registry_acceptance:
    raise SystemExit("clean-host baseline runner registry acceptance command missed --pull")
if "--artifact" in registry_acceptance:
    raise SystemExit("clean-host baseline runner registry acceptance command incorrectly required --artifact")
verify_dir = pathlib.Path(sys.argv[1]) / "verify-release-evidence"
verify_dir.mkdir()
verify_bundle_dir = verify_dir / "bundle"
verify_bundle_dir.mkdir()
verify_perf_root = verify_bundle_dir / "release-vm-root-perf-test.raw"
verify_bundle_manifest = {
    "kind": "libkrun.os-bundle.v1",
    "manifest_schema_version": 1,
    "platform": "linux/arm64",
    "source_image": "example-os:latest",
    "source_digest": "example-os@sha256:" + ("e" * 64),
    "root_disk": "root.raw",
    "root_disk_sha256": "f" * 64,
    "kernel_sha256": "a" * 64,
    "initramfs_sha256": None,
    "expected_root": "/dev/vda",
    "console": "ttyAMA0",
    "expected_pid1": "systemd",
}
verify_smoke_clone_command = [
    "examples/os_mode_apfs_clone.sh",
    str(verify_bundle_dir / "root.raw"),
    str(verify_bundle_dir / "release-vm-root-smoke-test.raw"),
]
verify_smoke_os_mode_command = [
    "examples/os_mode",
    "--root-disk",
    str(verify_bundle_dir / "release-vm-root-smoke-test.raw"),
]
verify_smoke_executed_command = [*verify_smoke_os_mode_command, "--poweroff-after-ready"]
verify_smoke_command = [
    "examples/os_mode_smoke.py",
    "--output",
    "smoke.json",
    "--",
    *verify_smoke_executed_command,
]
verify_smoke = {
    "ready": True,
    "failure_reason": None,
    "exit_code": 0,
    "timed_out": False,
    "command": verify_smoke_executed_command,
    "timings": {
        "first_kernel_log_ms": 3,
        "root_ms": 5,
        "pid1_ms": 6,
        "console_ms": 7,
        "ready_ms": 8,
    },
    "observed_root": "/dev/vda",
    "observed_pid1": "systemd",
    "observed_consoles": ["ttyAMA0"],
    "launcher_pid": 123,
    "process_parent_pid": 123,
    "process_pid": 124,
    "output_lines": [
        "[    0.000000] Booting Linux on physical CPU 0x0000000000",
        "KRUN_OSMODE: root=/dev/vda ext4 rw,relatime",
        "KRUN_OSMODE: pid1=systemd /usr/lib/systemd/systemd",
        "KRUN_OSMODE: console=ttyAMA0",
        "KRUN_OSMODE: ready",
    ],
    "bundle": {
        "kind": verify_bundle_manifest["kind"],
        "manifest_schema_version": verify_bundle_manifest["manifest_schema_version"],
        "bundle_dir": str(verify_bundle_dir),
        "platform": verify_bundle_manifest["platform"],
        "source_image": verify_bundle_manifest["source_image"],
        "source_digest": verify_bundle_manifest["source_digest"],
        "root_disk": str(verify_bundle_dir / "root.raw"),
        "root_disk_sha256": verify_bundle_manifest["root_disk_sha256"],
        "clone_dest": str(verify_bundle_dir / "release-vm-root-smoke-test.raw"),
        "imported_image": "registry.example.com/os@sha256:" + "d" * 64,
        "apfs_clone_command": verify_smoke_clone_command,
        "os_mode_command": verify_smoke_os_mode_command,
        "smoke_command": verify_smoke_command,
        "timings_ms": {
            "image_pull": 9,
            "bundle_extraction": 10,
            "apfs_clone": 2,
            "post_extraction_run": 20,
            "smoke": 18,
            "importer_total": 33,
        }
    },
}
verify_perf = {
    "failure_reason": None,
    "observed_root": "/dev/vda",
    "observed_pid1": "systemd",
    "observed_consoles": ["ttyAMA0"],
    "timings": {
        "first_kernel_log_ms": 4,
        "root_ms": 5,
        "pid1_ms": 6,
        "console_ms": 7,
        "ready_ms": 8,
    },
}
verify_image = "registry.example.com/os@sha256:" + "d" * 64
verify_artifact_manifest_payload = dict(release_artifact)
verify_artifact_manifest_payload["digest_ref"] = verify_image
for filename, payload in (
    ("bundle-manifest.json", verify_bundle_manifest),
    ("smoke.json", verify_smoke),
    ("perf.json", verify_perf),
    ("artifact-manifest.json", verify_artifact_manifest_payload),
):
    (verify_dir / filename).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
def verify_artifact_entry(filename):
    path = verify_dir / filename
    return {
        "source": str(path),
        "archive": filename,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "size_bytes": path.stat().st_size,
    }
verify_cache_entry = verify_dir / "cache-entry"
verify_preflight = {
    "schema_version": 1,
    "created_at_utc": "2026-05-18T01:00:00Z",
    "ok": True,
    "errors": [],
    "image_ref": verify_image,
    "host": {"system": "Darwin", "machine": "arm64", "macos": {"productVersion": "test"}},
    "runtime": {"requested": "auto", "selected": "docker"},
    "artifact_manifest": {
        "path": str(release_artifact_path),
        "valid": True,
        "digest_ref": verify_image,
        "archive": str(release_archive),
        "archive_sha256": release_artifact["archive"]["sha256"],
        "archive_size_bytes": release_archive.stat().st_size,
    },
    "cache_entry": {
        "path": str(verify_cache_entry),
        "exists": False,
        "clean": True,
        "entries": [],
    },
    "output_dir": {
        "path": str(verify_dir),
        "exists": False,
        "clean": True,
        "entries": [],
    },
    "apfs": [
        {"label": "bundle_cache_entry", "info": {"is_apfs": True}},
        {"label": "release_evidence_output", "info": {"is_apfs": True}},
    ],
    "release_gate_command": [
        "examples/os_mode_release_gate.py",
        "--artifact-manifest",
        str(release_artifact_path),
        "--output-dir",
        str(verify_dir),
        "--cache-dir",
        str(verify_dir),
        "--name",
        "cache-entry",
        "--preflight-json",
        str(verify_dir / "clean-host-preflight.json"),
        "--clean-host-baseline",
    ],
}
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_artifact_manifest_entry = verify_artifact_entry("artifact-manifest.json")
verify_artifact_manifest_entry["source"] = str(release_artifact_path)
verify_release_evidence = {
    "schema_version": 1,
    "created_at_utc": "2026-05-18T01:00:01Z",
    "image_ref": verify_image,
    "bundle_dir": str(verify_bundle_dir),
    "host": {"system": "Darwin", "machine": "arm64"},
    "apfs": {"is_apfs": True},
    "build_commands": [],
    "bundle": {
        "kind": "libkrun.os-bundle.v1",
        "manifest_schema_version": 1,
        "platform": "linux/arm64",
        "source_image": verify_bundle_manifest["source_image"],
        "source_digest": verify_bundle_manifest["source_digest"],
        "root_disk_sha256": verify_bundle_manifest["root_disk_sha256"],
        "kernel_sha256": verify_bundle_manifest["kernel_sha256"],
        "initramfs_sha256": verify_bundle_manifest["initramfs_sha256"],
        "expected_root": "/dev/vda",
        "expected_console": "ttyAMA0",
        "expected_pid1": "systemd",
    },
    "smoke": {
        "ready": True,
        "failure_reason": None,
        "timings_ms": verify_smoke["timings"],
        "observed_root": "/dev/vda",
        "observed_pid1": "systemd",
        "observed_consoles": ["ttyAMA0"],
        "launcher_pid": verify_smoke["launcher_pid"],
        "process_parent_pid": verify_smoke["process_parent_pid"],
        "process_pid": verify_smoke["process_pid"],
        "child_pid": verify_smoke["process_pid"],
        "bundle_timings_ms": verify_smoke["bundle"]["timings_ms"],
        "apfs_clone_command": verify_smoke["bundle"]["apfs_clone_command"],
        "os_mode_command": verify_smoke["bundle"]["os_mode_command"],
        "smoke_command": verify_smoke["bundle"]["smoke_command"],
    },
    "perf": {
        "failure_reason": None,
        "observed_root": "/dev/vda",
        "observed_pid1": "systemd",
        "observed_consoles": ["ttyAMA0"],
        "timings_ms": {
            "first_kernel_log_ms": 4,
            "root_ms": 5,
            "pid1_ms": 6,
            "console_ms": 7,
            "ready_ms": 8,
        },
    },
    "artifacts": {
        "bundle_manifest": verify_artifact_entry("bundle-manifest.json"),
        "smoke_json": verify_artifact_entry("smoke.json"),
        "perf_json": verify_artifact_entry("perf.json"),
        "clean_host_preflight_json": verify_artifact_entry("clean-host-preflight.json"),
        "artifact_manifest_json": verify_artifact_manifest_entry,
    },
    "artifact_manifest": {
        "kind": "libkrun.os-bundle.artifact.v1",
        "digest_ref": verify_image,
    },
    "artifact": {
        "load_ms": 11,
    },
}
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
verify_gate_summary = {
    "schema_version": 1,
    "image_ref": verify_image,
    "image_was_explicit": False,
    "cache_entry": str(verify_cache_entry),
    "release_evidence": str(verify_dir / "release-evidence.json"),
    "baseline_table": str(verify_dir / "baseline.md"),
    "smoke_importer_command": [
        "python3",
        "examples/os_mode_import_container_bundle.py",
        "--image",
        verify_image,
        "--output-dir",
        str(verify_cache_entry),
        "--smoke-output",
        "smoke.json",
        "--strict-digest",
        "--reuse-extracted-output-dir",
        "--run",
        "--pull",
    ],
    "require_clean_cache": True,
    "require_cache_entry_absent": True,
    "clean_host_baseline": True,
    "cache_preflight": {
        "path": str(verify_cache_entry),
        "exists": False,
        "clean": True,
        "entries": [],
    },
    "artifact_manifest": str(release_artifact_path),
    "artifact_load_command": ["docker", "load", "-i", str(release_archive)],
    "perf_clone_command": [
        "examples/os_mode_apfs_clone.sh",
        str(verify_bundle_dir / "root.raw"),
        str(verify_perf_root),
    ],
    "perf_command": [
        "examples/os_mode_perf.py",
        "--output",
        "perf.json",
        "--require-pid1-marker",
        "--",
        "examples/os_mode",
        "--root-disk",
        str(verify_perf_root),
    ],
    "preflight_json": str(verify_dir / "clean-host-preflight.json"),
}
verify_release_evidence["build_commands"] = [
    "make BLK=1 NET=1 CLANG=/opt/homebrew/opt/llvm/bin/clang",
    "artifact_load_command=" + json.dumps(verify_gate_summary["artifact_load_command"]),
    "smoke_importer_command=" + json.dumps(verify_gate_summary["smoke_importer_command"]),
]
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(verify_gate_summary, indent=2) + "\n", encoding="utf-8")
verify_args = argparse.Namespace(
    evidence_dir=verify_dir,
    require_clean_cache=True,
    require_cache_entry_absent=True,
    require_artifact_manifest=True,
    require_artifact_load=True,
    require_apfs=True,
    require_macos_arm64=True,
    require_perf=True,
    require_clean_poweroff=True,
    require_pull=True,
    require_clean_host_preflight=True,
    require_build_provenance=True,
)
verify_result = verify_evidence_module.verify_evidence(verify_args)
if verify_result.get("observed_pid1") != "systemd":
    raise SystemExit("release evidence verifier returned the wrong observed PID 1")
bad_verify_build = copy.deepcopy(verify_release_evidence)
bad_verify_build["build_commands"] = [
    command
    for command in bad_verify_build["build_commands"]
    if command.startswith(("artifact_load_command=", "smoke_importer_command="))
]
(verify_dir / "release-evidence.json").write_text(json.dumps(bad_verify_build, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "missing a caller-supplied build command" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected build provenance error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted build provenance without a user build command")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_smoke = copy.deepcopy(verify_smoke)
bad_verify_smoke.pop("process_pid", None)
(verify_dir / "smoke.json").write_text(json.dumps(bad_verify_smoke, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["smoke_json"] = verify_artifact_entry("smoke.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "archived smoke JSON is missing process_pid" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected missing process_pid error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted smoke evidence without process_pid")
(verify_dir / "smoke.json").write_text(json.dumps(verify_smoke, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["smoke_json"] = verify_artifact_entry("smoke.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_smoke = copy.deepcopy(verify_smoke)
bad_verify_smoke["bundle"]["os_mode_command"] = [
    "examples/os_mode",
    "--root-disk",
    str(verify_bundle_dir / "other-smoke-root.raw"),
]
(verify_dir / "smoke.json").write_text(json.dumps(bad_verify_smoke, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["smoke_json"] = verify_artifact_entry("smoke.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "release evidence smoke os_mode_command does not match archived smoke JSON" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected smoke command mismatch error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted mismatched archived smoke os_mode_command")
(verify_dir / "smoke.json").write_text(json.dumps(verify_smoke, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["smoke_json"] = verify_artifact_entry("smoke.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_smoke = copy.deepcopy(verify_smoke)
bad_root = str(verify_dir / "root.raw")
bad_verify_smoke["bundle"]["root_disk"] = bad_root
bad_verify_smoke["bundle"]["apfs_clone_command"] = [
    *verify_smoke["bundle"]["apfs_clone_command"][:1],
    bad_root,
    verify_smoke["bundle"]["apfs_clone_command"][2],
]
bad_verify_evidence = copy.deepcopy(verify_release_evidence)
bad_verify_evidence["smoke"]["apfs_clone_command"] = bad_verify_smoke["bundle"]["apfs_clone_command"]
(verify_dir / "smoke.json").write_text(json.dumps(bad_verify_smoke, indent=2) + "\n", encoding="utf-8")
bad_verify_evidence["artifacts"]["smoke_json"] = verify_artifact_entry("smoke.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(bad_verify_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "archived smoke bundle root_disk is not in bundle_dir" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected smoke root path error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted smoke root_disk outside bundle_dir")
(verify_dir / "smoke.json").write_text(json.dumps(verify_smoke, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["smoke_json"] = verify_artifact_entry("smoke.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_evidence = copy.deepcopy(verify_release_evidence)
bad_verify_evidence.pop("artifact", None)
(verify_dir / "release-evidence.json").write_text(json.dumps(bad_verify_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "artifact load summary" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected missing artifact load timing error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted artifact evidence without load timing")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
bad_verify_smoke = copy.deepcopy(verify_smoke)
bad_verify_smoke["bundle"]["source_digest"] = "example-os@sha256:" + ("b" * 64)
(verify_dir / "smoke.json").write_text(json.dumps(bad_verify_smoke, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["smoke_json"] = verify_artifact_entry("smoke.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "archived smoke bundle source_digest mismatch" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected smoke source_digest error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted smoke bundle source_digest mismatch")
(verify_dir / "smoke.json").write_text(json.dumps(verify_smoke, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["smoke_json"] = verify_artifact_entry("smoke.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_evidence = copy.deepcopy(verify_release_evidence)
bad_verify_evidence["bundle"]["kernel_sha256"] = "c" * 64
(verify_dir / "release-evidence.json").write_text(json.dumps(bad_verify_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "evidence bundle kernel_sha256 does not match bundle manifest" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected kernel_sha256 error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted bundle kernel_sha256 mismatch")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
bad_verify_evidence = copy.deepcopy(verify_release_evidence)
bad_verify_evidence["artifact"]["load_ms"] = -1
(verify_dir / "release-evidence.json").write_text(json.dumps(bad_verify_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "artifact load_ms is missing or invalid" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected bad artifact load timing error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted invalid artifact load timing")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
bad_verify_summary = copy.deepcopy(verify_gate_summary)
load_path_index = bad_verify_summary["artifact_load_command"].index("-i")
bad_verify_summary["artifact_load_command"][load_path_index + 1] = str(verify_dir / "other-bundle.tar")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "artifact load command option -i does not match expected path" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected artifact load path error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted artifact load command for a different archive")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(verify_gate_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_perf = copy.deepcopy(verify_perf)
bad_verify_perf["timings"] = dict(verify_perf["timings"])
bad_verify_perf["timings"]["ready_ms"] = 99
(verify_dir / "perf.json").write_text(json.dumps(bad_verify_perf, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["perf_json"] = verify_artifact_entry("perf.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "archived perf timing ready_ms does not match release evidence" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected archived perf timing error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted perf JSON that disagrees with release evidence")
(verify_dir / "perf.json").write_text(json.dumps(verify_perf, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["perf_json"] = verify_artifact_entry("perf.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
bad_verify_perf = copy.deepcopy(verify_perf)
bad_verify_perf["observed_pid1"] = "init.krun"
(verify_dir / "perf.json").write_text(json.dumps(bad_verify_perf, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["perf_json"] = verify_artifact_entry("perf.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "archived perf observed_pid1 mismatch" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected archived perf PID 1 error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted perf JSON with init.krun PID 1")
(verify_dir / "perf.json").write_text(json.dumps(verify_perf, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["perf_json"] = verify_artifact_entry("perf.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
bad_verify_smoke = copy.deepcopy(verify_smoke)
bad_verify_smoke["observed_consoles"] = ["ttyS0"]
(verify_dir / "smoke.json").write_text(json.dumps(bad_verify_smoke, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["smoke_json"] = verify_artifact_entry("smoke.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "archived smoke did not observe the expected console" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected archived smoke console error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted smoke JSON with the wrong console")
(verify_dir / "smoke.json").write_text(json.dumps(verify_smoke, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["smoke_json"] = verify_artifact_entry("smoke.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_smoke = copy.deepcopy(verify_smoke)
bad_verify_smoke["output_lines"] = ["KRUN_OSMODE: ready"]
(verify_dir / "smoke.json").write_text(json.dumps(bad_verify_smoke, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["smoke_json"] = verify_artifact_entry("smoke.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "archived smoke JSON does not include an early kernel boot log line" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected archived smoke boot-log error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted smoke JSON without an early kernel boot log")
(verify_dir / "smoke.json").write_text(json.dumps(verify_smoke, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["smoke_json"] = verify_artifact_entry("smoke.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
registry_verify_preflight = copy.deepcopy(verify_preflight)
registry_verify_preflight["artifact_manifest"] = None
registry_verify_preflight["release_gate_command"] = [
    "examples/os_mode_release_gate.py",
    verify_image,
    "--output-dir",
    str(verify_dir),
    "--cache-dir",
    str(verify_dir),
    "--name",
    "cache-entry",
    "--preflight-json",
    str(verify_dir / "clean-host-preflight.json"),
    "--clean-host-baseline",
]
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(registry_verify_preflight, indent=2) + "\n", encoding="utf-8")
registry_verify_evidence = copy.deepcopy(verify_release_evidence)
registry_verify_evidence.pop("artifact_manifest", None)
registry_verify_evidence.pop("artifact", None)
registry_verify_evidence["artifacts"].pop("artifact_manifest_json", None)
registry_verify_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(registry_verify_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
registry_verify_summary = copy.deepcopy(verify_gate_summary)
registry_verify_summary["artifact_manifest"] = None
registry_verify_summary["artifact_load_command"] = None
registry_verify_summary["image_was_explicit"] = True
(verify_dir / "release-gate-summary.json").write_text(json.dumps(registry_verify_summary, indent=2) + "\n", encoding="utf-8")
registry_verify_args = copy.copy(verify_args)
registry_verify_args.require_artifact_manifest = False
registry_verify_args.require_artifact_load = False
registry_result = verify_evidence_module.verify_evidence(registry_verify_args)
if registry_result.get("image_ref") != verify_image:
    raise SystemExit("release evidence verifier registry mode returned the wrong image_ref")
bad_verify_summary = copy.deepcopy(registry_verify_summary)
bad_verify_summary["image_was_explicit"] = False
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(registry_verify_args)
except verify_evidence_module.VerifyError as exc:
    if "registry release evidence must record image_was_explicit=true" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected registry image_was_explicit error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted registry evidence with image_was_explicit=false")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(registry_verify_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_summary = copy.deepcopy(registry_verify_summary)
bad_image_index = bad_verify_summary["smoke_importer_command"].index("--image")
bad_verify_summary["smoke_importer_command"][bad_image_index + 1] = "registry.example.com/os@sha256:" + "1" * 64
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(registry_verify_args)
except verify_evidence_module.VerifyError as exc:
    if "smoke importer command option --image does not match expected value" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected smoke importer image error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted smoke importer command with a different image_ref")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(registry_verify_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_summary = copy.deepcopy(registry_verify_summary)
bad_output_index = bad_verify_summary["smoke_importer_command"].index("--output-dir")
bad_verify_summary["smoke_importer_command"][bad_output_index + 1] = str(verify_dir / "other-cache-entry")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(registry_verify_args)
except verify_evidence_module.VerifyError as exc:
    if "smoke importer command option --output-dir does not match expected path" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected smoke importer output-dir error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted smoke importer command with a different output dir")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(registry_verify_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_summary = copy.deepcopy(registry_verify_summary)
bad_smoke_output_index = bad_verify_summary["smoke_importer_command"].index("--smoke-output")
bad_verify_summary["smoke_importer_command"][bad_smoke_output_index + 1] = "other-smoke.json"
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(registry_verify_args)
except verify_evidence_module.VerifyError as exc:
    if "smoke importer command option --smoke-output does not match expected artifact source" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected smoke importer smoke-output error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted smoke importer command with a different smoke output")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(registry_verify_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_summary = copy.deepcopy(registry_verify_summary)
bad_perf_output_index = bad_verify_summary["perf_command"].index("--output")
bad_verify_summary["perf_command"][bad_perf_output_index + 1] = "other-perf.json"
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(registry_verify_args)
except verify_evidence_module.VerifyError as exc:
    if "perf command option --output does not match expected artifact source" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected perf command output error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted perf command with a different output")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(registry_verify_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_summary = copy.deepcopy(registry_verify_summary)
bad_verify_summary["perf_clone_command"] = list(registry_verify_summary["perf_clone_command"])
bad_verify_summary["perf_clone_command"][2] = str(verify_bundle_dir / "other-perf-root.raw")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(registry_verify_args)
except verify_evidence_module.VerifyError as exc:
    if "perf command option --root-disk does not match expected path" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected perf clone/root-disk error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted perf command with a different clone root")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(registry_verify_summary, indent=2) + "\n", encoding="utf-8")
registry_verify_preflight_bad = copy.deepcopy(registry_verify_preflight)
registry_verify_preflight_bad["release_gate_command"] = [
    item for item in registry_verify_preflight_bad["release_gate_command"] if item != verify_image
]
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(registry_verify_preflight_bad, indent=2) + "\n", encoding="utf-8")
registry_verify_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(registry_verify_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(registry_verify_args)
except verify_evidence_module.VerifyError as exc:
    if "preflight release gate command is missing release image_ref" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected registry preflight image error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted registry preflight command without image_ref")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
(verify_dir / "release-gate-summary.json").write_text(json.dumps(verify_gate_summary, indent=2) + "\n", encoding="utf-8")
good_verify_artifact_manifest = (verify_dir / "artifact-manifest.json").read_text(encoding="utf-8")
bad_verify_artifact_manifest = json.loads(good_verify_artifact_manifest)
bad_verify_artifact_manifest["commands"]["clean_host_baseline"] = [
    item
    for item in bad_verify_artifact_manifest["commands"]["clean_host_baseline"]
    if item not in ("--accept-table-output", "ACCEPTED_BASELINE_MD")
]
(verify_dir / "artifact-manifest.json").write_text(
    json.dumps(bad_verify_artifact_manifest, indent=2) + "\n",
    encoding="utf-8",
)
verify_release_evidence["artifacts"]["artifact_manifest_json"] = verify_artifact_entry("artifact-manifest.json")
verify_release_evidence["artifacts"]["artifact_manifest_json"]["source"] = str(release_artifact_path)
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "clean_host_baseline command is missing required items" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected artifact command error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted stale artifact clean-host baseline command templates")
bad_verify_artifact_manifest = json.loads(good_verify_artifact_manifest)
bad_verify_artifact_manifest["commands"]["clean_host_baseline"] = [
    item
    for item in bad_verify_artifact_manifest["commands"]["clean_host_baseline"]
    if item not in ("--evidence-label", "RELEASE_EVIDENCE_LABEL")
]
(verify_dir / "artifact-manifest.json").write_text(
    json.dumps(bad_verify_artifact_manifest, indent=2) + "\n",
    encoding="utf-8",
)
verify_release_evidence["artifacts"]["artifact_manifest_json"] = verify_artifact_entry("artifact-manifest.json")
verify_release_evidence["artifacts"]["artifact_manifest_json"]["source"] = str(release_artifact_path)
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "incomplete design-doc output items" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected partial design-doc command error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted partial artifact design-doc command template")
(verify_dir / "artifact-manifest.json").write_text(good_verify_artifact_manifest, encoding="utf-8")
verify_release_evidence["artifacts"]["artifact_manifest_json"] = verify_artifact_entry("artifact-manifest.json")
verify_release_evidence["artifacts"]["artifact_manifest_json"]["source"] = str(release_artifact_path)
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
(verify_dir / "baseline.md").write_text(
    baseline_table_module.markdown_table(
        baseline_table_module.rows_from_release_evidence([verify_dir], [])
    ),
    encoding="utf-8",
)
acceptance_result = acceptance_module.accept_evidence(verify_dir, artifact=True, pull=True)
if acceptance_result.get("schema_version") != 1:
    raise SystemExit("clean-host acceptance helper did not record schema_version=1")
if acceptance_result.get("accepted") is not True:
    raise SystemExit("clean-host acceptance helper did not accept strict synthetic evidence")
if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", str(acceptance_result.get("accepted_at_utc"))):
    raise SystemExit("clean-host acceptance helper did not record accepted_at_utc")
if acceptance_result.get("final_release_baseline") is not False:
    raise SystemExit("clean-host acceptance helper did not default final_release_baseline to false")
if acceptance_result.get("verification", {}).get("observed_pid1") != "systemd":
    raise SystemExit("clean-host acceptance helper returned the wrong observed PID 1")
if "Clean poweroff" not in acceptance_result.get("baseline_table", ""):
    raise SystemExit("clean-host acceptance helper did not include a baseline table")
required_checklist = acceptance_result.get("required_checklist")
if not isinstance(required_checklist, list) or not all(isinstance(item, str) for item in required_checklist):
    raise SystemExit("clean-host acceptance helper did not record required checklist names")
if "artifact delivery" not in required_checklist or "registry pull" not in required_checklist:
    raise SystemExit("clean-host acceptance helper did not record conditional required checklist names")
acceptance_checklist = acceptance_result.get("evidence_checklist")
if not isinstance(acceptance_checklist, list) or not acceptance_checklist:
    raise SystemExit("clean-host acceptance helper did not include an evidence checklist")
checklist_names = [
    item.get("name")
    for item in acceptance_checklist
    if isinstance(item, dict)
]
if checklist_names != required_checklist:
    raise SystemExit("clean-host acceptance helper required checklist did not match evidence checklist names")
checklist_by_name = {
    item.get("name"): item
    for item in acceptance_checklist
    if isinstance(item, dict)
}
for required_check in (
    "clean cache",
    "absent cache entry",
    "build provenance",
    "host-side launcher process",
    "host-side launch command binding",
    "bundle provenance",
    "release-gate summary",
    "guest OS markers",
    "first boot log timing",
    "baseline marker timings",
    "baseline timing row",
    "image load/pull/export timing",
    "artifact delivery",
    "registry pull",
):
    item = checklist_by_name.get(required_check)
    if not isinstance(item, dict) or item.get("passed") is not True:
        raise SystemExit(f"clean-host acceptance checklist did not pass {required_check}: {item}")
bad_guest_marker_checklist = acceptance_module.acceptance_checklist(
    verify_dir,
    artifact=True,
    pull=True,
    verification={
        "ready": True,
        "observed_root": "/dev/wrong",
        "observed_pid1": "systemd",
        "observed_console": ["ttyAMA0"],
    },
)
bad_guest_marker = next(
    (
        item
        for item in bad_guest_marker_checklist
        if isinstance(item, dict) and item.get("name") == "guest OS markers"
    ),
    None,
)
if not isinstance(bad_guest_marker, dict) or bad_guest_marker.get("passed") is not False:
    raise SystemExit("clean-host acceptance checklist accepted mismatched guest root marker")
bad_perf_evidence = copy.deepcopy(verify_release_evidence)
bad_perf_evidence["perf"]["observed_root"] = "/dev/wrong"
(verify_dir / "release-evidence.json").write_text(json.dumps(bad_perf_evidence, indent=2) + "\n", encoding="utf-8")
bad_perf_marker_checklist = acceptance_module.acceptance_checklist(
    verify_dir,
    artifact=True,
    pull=True,
    verification=acceptance_result["verification"],
)
bad_perf_marker = next(
    (
        item
        for item in bad_perf_marker_checklist
        if isinstance(item, dict) and item.get("name") == "perf markers"
    ),
    None,
)
if not isinstance(bad_perf_marker, dict) or bad_perf_marker.get("passed") is not False:
    raise SystemExit("clean-host acceptance checklist accepted mismatched perf root marker")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_first_log_smoke = copy.deepcopy(verify_smoke)
bad_first_log_smoke["output_lines"] = ["KRUN_OSMODE: ready"]
(verify_dir / "smoke.json").write_text(json.dumps(bad_first_log_smoke, indent=2) + "\n", encoding="utf-8")
bad_first_log_checklist = acceptance_module.acceptance_checklist(
    verify_dir,
    artifact=True,
    pull=True,
    verification=acceptance_result["verification"],
)
bad_first_log = next(
    (
        item
        for item in bad_first_log_checklist
        if isinstance(item, dict) and item.get("name") == "first boot log timing"
    ),
    None,
)
if not isinstance(bad_first_log, dict) or bad_first_log.get("passed") is not False:
    raise SystemExit("clean-host acceptance checklist accepted smoke evidence without an early kernel log")
(verify_dir / "smoke.json").write_text(json.dumps(verify_smoke, indent=2) + "\n", encoding="utf-8")
bad_poweroff_smoke = copy.deepcopy(verify_smoke)
bad_poweroff_smoke["command"] = list(verify_smoke_os_mode_command)
(verify_dir / "smoke.json").write_text(json.dumps(bad_poweroff_smoke, indent=2) + "\n", encoding="utf-8")
bad_poweroff_checklist = acceptance_module.acceptance_checklist(
    verify_dir,
    artifact=True,
    pull=True,
    verification=acceptance_result["verification"],
)
bad_poweroff = next(
    (
        item
        for item in bad_poweroff_checklist
        if isinstance(item, dict) and item.get("name") == "clean poweroff"
    ),
    None,
)
if not isinstance(bad_poweroff, dict) or bad_poweroff.get("passed") is not False:
    raise SystemExit("clean-host acceptance checklist accepted smoke evidence without poweroff-after-ready")
(verify_dir / "smoke.json").write_text(json.dumps(verify_smoke, indent=2) + "\n", encoding="utf-8")
bad_build_evidence = copy.deepcopy(verify_release_evidence)
bad_build_evidence["build_commands"] = [
    command
    for command in bad_build_evidence["build_commands"]
    if command.startswith(("artifact_load_command=", "smoke_importer_command="))
]
(verify_dir / "release-evidence.json").write_text(json.dumps(bad_build_evidence, indent=2) + "\n", encoding="utf-8")
bad_build_checklist = acceptance_module.acceptance_checklist(
    verify_dir,
    artifact=True,
    pull=True,
    verification=acceptance_result["verification"],
)
bad_build = next(
    (
        item
        for item in bad_build_checklist
        if isinstance(item, dict) and item.get("name") == "build provenance"
    ),
    None,
)
if not isinstance(bad_build, dict) or bad_build.get("passed") is not False:
    raise SystemExit("clean-host acceptance checklist accepted evidence without a user build command")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_summary_payload = copy.deepcopy(verify_gate_summary)
bad_summary_payload["clean_host_baseline"] = False
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_summary_payload, indent=2) + "\n", encoding="utf-8")
bad_summary_checklist = acceptance_module.acceptance_checklist(
    verify_dir,
    artifact=True,
    pull=True,
    verification=acceptance_result["verification"],
)
bad_summary = next(
    (
        item
        for item in bad_summary_checklist
        if isinstance(item, dict) and item.get("name") == "release-gate summary"
    ),
    None,
)
if not isinstance(bad_summary, dict) or bad_summary.get("passed") is not False:
    raise SystemExit("clean-host acceptance checklist accepted a non-clean-host release-gate summary")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(verify_gate_summary, indent=2) + "\n", encoding="utf-8")
bad_summary_payload = copy.deepcopy(verify_gate_summary)
bad_summary_payload["image_was_explicit"] = True
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_summary_payload, indent=2) + "\n", encoding="utf-8")
bad_summary_checklist = acceptance_module.acceptance_checklist(
    verify_dir,
    artifact=True,
    pull=True,
    verification=acceptance_result["verification"],
)
bad_summary = next(
    (
        item
        for item in bad_summary_checklist
        if isinstance(item, dict) and item.get("name") == "release-gate summary"
    ),
    None,
)
if not isinstance(bad_summary, dict) or bad_summary.get("passed") is not False:
    raise SystemExit("clean-host acceptance checklist accepted mismatched artifact image_was_explicit evidence")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(verify_gate_summary, indent=2) + "\n", encoding="utf-8")
old_acceptance_checklist = acceptance_module.acceptance_checklist
try:
    failed_checklist = copy.deepcopy(acceptance_result["evidence_checklist"])
    failed_checklist[0] = {
        **failed_checklist[0],
        "passed": False,
        "evidence": "forced failure",
    }
    acceptance_module.acceptance_checklist = lambda *args, **kwargs: failed_checklist
    try:
        acceptance_module.accept_evidence(verify_dir, artifact=True, pull=True)
    except acceptance_module.AcceptanceError as exc:
        if "acceptance checklist did not pass: clean cache" not in str(exc):
            raise SystemExit(f"clean-host acceptance checklist failure reported unexpected error: {exc}")
    else:
        raise SystemExit("clean-host acceptance helper accepted a failed checklist")
finally:
    acceptance_module.acceptance_checklist = old_acceptance_checklist
try:
    acceptance_module.acceptance_checklist = lambda *args, **kwargs: [
        {"name": "clean cache", "passed": True, "evidence": "test"}
    ]
    try:
        acceptance_module.accept_evidence(verify_dir, artifact=True, pull=True)
    except acceptance_module.AcceptanceError as exc:
        if "acceptance checklist is missing required items" not in str(exc):
            raise SystemExit(f"clean-host acceptance missing-checklist error was unexpected: {exc}")
    else:
        raise SystemExit("clean-host acceptance helper accepted a checklist missing required items")
finally:
    acceptance_module.acceptance_checklist = old_acceptance_checklist
try:
    reordered_checklist = copy.deepcopy(acceptance_result["evidence_checklist"])
    reordered_checklist[0], reordered_checklist[1] = reordered_checklist[1], reordered_checklist[0]
    acceptance_module.acceptance_checklist = lambda *args, **kwargs: reordered_checklist
    try:
        acceptance_module.accept_evidence(verify_dir, artifact=True, pull=True)
    except acceptance_module.AcceptanceError as exc:
        if "acceptance checklist order does not match required items" not in str(exc):
            raise SystemExit(f"clean-host acceptance reordered-checklist error was unexpected: {exc}")
    else:
        raise SystemExit("clean-host acceptance helper accepted a reordered checklist")
finally:
    acceptance_module.acceptance_checklist = old_acceptance_checklist
try:
    acceptance_module.acceptance_checklist = lambda *args, **kwargs: [
        *acceptance_result["evidence_checklist"],
        {"name": "unexpected item", "passed": True, "evidence": "extra"},
    ]
    try:
        acceptance_module.accept_evidence(verify_dir, artifact=True, pull=True)
    except acceptance_module.AcceptanceError as exc:
        if "acceptance checklist has unexpected items" not in str(exc):
            raise SystemExit(f"clean-host acceptance unexpected-checklist error was unexpected: {exc}")
    else:
        raise SystemExit("clean-host acceptance helper accepted an unexpected checklist item")
finally:
    acceptance_module.acceptance_checklist = old_acceptance_checklist
try:
    acceptance_module.acceptance_checklist = lambda *args, **kwargs: [
        *acceptance_result["evidence_checklist"],
        {"name": "clean cache", "passed": True, "evidence": "duplicate"},
    ]
    try:
        acceptance_module.accept_evidence(verify_dir, artifact=True, pull=True)
    except acceptance_module.AcceptanceError as exc:
        if "acceptance checklist has duplicate items" not in str(exc):
            raise SystemExit(f"clean-host acceptance duplicate-checklist error was unexpected: {exc}")
    else:
        raise SystemExit("clean-host acceptance helper accepted a duplicate checklist item")
finally:
    acceptance_module.acceptance_checklist = old_acceptance_checklist
try:
    acceptance_module.acceptance_checklist = lambda *args, **kwargs: [
        *acceptance_result["evidence_checklist"],
        {"passed": True, "evidence": "missing name"},
    ]
    try:
        acceptance_module.accept_evidence(verify_dir, artifact=True, pull=True)
    except acceptance_module.AcceptanceError as exc:
        if "acceptance checklist has invalid items" not in str(exc):
            raise SystemExit(f"clean-host acceptance invalid-checklist error was unexpected: {exc}")
    else:
        raise SystemExit("clean-host acceptance helper accepted an invalid checklist item")
finally:
    acceptance_module.acceptance_checklist = old_acceptance_checklist
try:
    acceptance_module.acceptance_checklist = lambda *args, **kwargs: [
        *acceptance_result["evidence_checklist"],
        "not-a-checklist-item",
    ]
    try:
        acceptance_module.accept_evidence(verify_dir, artifact=True, pull=True)
    except acceptance_module.AcceptanceError as exc:
        if "acceptance checklist has invalid items" not in str(exc):
            raise SystemExit(f"clean-host acceptance non-dict checklist error was unexpected: {exc}")
    else:
        raise SystemExit("clean-host acceptance helper accepted a non-dict checklist item")
finally:
    acceptance_module.acceptance_checklist = old_acceptance_checklist
try:
    acceptance_module.acceptance_checklist = lambda *args, **kwargs: [
        *acceptance_result["evidence_checklist"],
        {"name": "bad-passed", "passed": "yes", "evidence": "not boolean"},
    ]
    try:
        acceptance_module.accept_evidence(verify_dir, artifact=True, pull=True)
    except acceptance_module.AcceptanceError as exc:
        if "acceptance checklist has invalid items" not in str(exc):
            raise SystemExit(f"clean-host acceptance non-boolean checklist error was unexpected: {exc}")
    else:
        raise SystemExit("clean-host acceptance helper accepted a non-boolean checklist passed value")
finally:
    acceptance_module.acceptance_checklist = old_acceptance_checklist
try:
    acceptance_module.acceptance_checklist = lambda *args, **kwargs: [
        *acceptance_result["evidence_checklist"],
        {"name": "empty-evidence", "passed": True, "evidence": ""},
    ]
    try:
        acceptance_module.accept_evidence(verify_dir, artifact=True, pull=True)
    except acceptance_module.AcceptanceError as exc:
        if "acceptance checklist has invalid items" not in str(exc):
            raise SystemExit(f"clean-host acceptance empty-evidence checklist error was unexpected: {exc}")
    else:
        raise SystemExit("clean-host acceptance helper accepted a checklist item without evidence")
finally:
    acceptance_module.acceptance_checklist = old_acceptance_checklist
try:
    acceptance_module.accept_evidence(verify_dir, artifact=False, pull=True)
except acceptance_module.AcceptanceError as exc:
    if "--artifact" not in str(exc):
        raise SystemExit(f"clean-host acceptance missing-artifact guard reported unexpected error: {exc}")
else:
    raise SystemExit("clean-host acceptance helper accepted artifact evidence without artifact=True")
try:
    acceptance_module.accept_evidence(verify_dir, artifact=True, pull=False)
except acceptance_module.AcceptanceError as exc:
    if "--pull" not in str(exc):
        raise SystemExit(f"clean-host acceptance missing-pull guard reported unexpected error: {exc}")
else:
    raise SystemExit("clean-host acceptance helper accepted pull evidence without pull=True")
acceptance_json = verify_dir / "acceptance.json"
acceptance_table = verify_dir / "acceptance.md"
acceptance_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_clean_host_acceptance.py"),
        str(verify_dir),
        "--artifact",
        "--pull",
        "--json-output",
        str(acceptance_json),
        "--table-output",
        str(acceptance_table),
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if acceptance_cli.returncode != 0:
    raise SystemExit(f"clean-host acceptance CLI failed: {acceptance_cli.stderr}")
if "| Label |" not in acceptance_cli.stdout or "Clean poweroff" not in acceptance_cli.stdout:
    raise SystemExit("clean-host acceptance CLI did not print the baseline table")
acceptance_payload = json.loads(acceptance_json.read_text(encoding="utf-8"))
if acceptance_payload.get("schema_version") != 1:
    raise SystemExit("clean-host acceptance CLI JSON did not record schema_version=1")
if acceptance_payload.get("accepted") is not True:
    raise SystemExit("clean-host acceptance CLI JSON did not record accepted=true")
if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", str(acceptance_payload.get("accepted_at_utc"))):
    raise SystemExit("clean-host acceptance CLI JSON did not record accepted_at_utc")
if acceptance_payload.get("final_release_baseline") is not False:
    raise SystemExit("clean-host acceptance CLI JSON did not default final_release_baseline to false")
if acceptance_payload.get("requirements", {}).get("artifact_manifest") is not True:
    raise SystemExit("clean-host acceptance CLI JSON did not record artifact requirement")
if acceptance_payload.get("requirements", {}).get("pull") is not True:
    raise SystemExit("clean-host acceptance CLI JSON did not record pull requirement")
if acceptance_payload.get("requirements", {}).get("build_provenance") is not True:
    raise SystemExit("clean-host acceptance CLI JSON did not record build provenance requirement")
cli_required_checklist = acceptance_payload.get("required_checklist")
if cli_required_checklist != required_checklist:
    raise SystemExit("clean-host acceptance CLI JSON did not preserve required checklist names")
cli_checklist_names = [
    item.get("name")
    for item in acceptance_payload.get("evidence_checklist", [])
    if isinstance(item, dict)
]
if cli_checklist_names != cli_required_checklist:
    raise SystemExit("clean-host acceptance CLI JSON required checklist did not match evidence checklist names")
if not any(
    isinstance(item, dict) and item.get("name") == "artifact delivery" and item.get("passed") is True
    for item in acceptance_payload.get("evidence_checklist", [])
):
    raise SystemExit("clean-host acceptance CLI JSON did not include passed artifact delivery evidence")
if not any(
    isinstance(item, dict) and item.get("name") == "registry pull" and item.get("passed") is True
    for item in acceptance_payload.get("evidence_checklist", [])
):
    raise SystemExit("clean-host acceptance CLI JSON did not include passed registry pull evidence")
if "| Label |" not in acceptance_table.read_text(encoding="utf-8"):
    raise SystemExit("clean-host acceptance CLI did not write standalone baseline table")
design_doc_snippet = design_doc_baseline_module.render_snippet(
    acceptance_payload,
    acceptance_json,
    "synthetic-clean-host",
)
if "### Clean-Host Baseline Table" not in design_doc_snippet:
    raise SystemExit("design-doc baseline helper omitted the baseline table heading")
if "### Completion Audit Row" not in design_doc_snippet:
    raise SystemExit("design-doc baseline helper omitted the audit row heading")
if "synthetic-clean-host" not in design_doc_snippet:
    raise SystemExit("design-doc baseline helper omitted the evidence label")
if "release-gate summary" not in design_doc_snippet:
    raise SystemExit("design-doc baseline helper omitted the strict checklist names")
if "| Clean-host baseline table on a fresh Apple Silicon host | Open |" not in design_doc_snippet:
    raise SystemExit("design-doc baseline helper did not keep rehearsal evidence open by default")
try:
    design_doc_baseline_module.render_snippet(
        acceptance_payload,
        acceptance_json,
        "synthetic-clean-host",
        final_release_baseline=True,
    )
except design_doc_baseline_module.DesignDocBaselineError as exc:
    if "final_release_baseline=true" not in str(exc):
        raise SystemExit(f"design-doc baseline helper reported unexpected final-baseline guard error: {exc}")
else:
    raise SystemExit("design-doc baseline helper marked non-final acceptance evidence implemented")
final_acceptance_payload = copy.deepcopy(acceptance_payload)
final_acceptance_payload["final_release_baseline"] = True
final_design_doc_snippet = design_doc_baseline_module.render_snippet(
    final_acceptance_payload,
    acceptance_json,
    "synthetic-clean-host",
    final_release_baseline=True,
)
if "| Clean-host baseline table on a fresh Apple Silicon host | Implemented |" not in final_design_doc_snippet:
    raise SystemExit("design-doc baseline helper did not mark explicit final release evidence implemented")
bad_design_doc_payload = copy.deepcopy(acceptance_payload)
bad_design_doc_payload["accepted"] = False
try:
    design_doc_baseline_module.render_snippet(bad_design_doc_payload, acceptance_json)
except design_doc_baseline_module.DesignDocBaselineError as exc:
    if "accepted=true" not in str(exc):
        raise SystemExit(f"design-doc baseline helper reported unexpected rejected-acceptance error: {exc}")
else:
    raise SystemExit("design-doc baseline helper accepted rejected clean-host evidence")
bad_design_doc_payload = copy.deepcopy(acceptance_payload)
bad_design_doc_payload["requirements"]["clean_poweroff"] = False
try:
    design_doc_baseline_module.render_snippet(bad_design_doc_payload, acceptance_json)
except design_doc_baseline_module.DesignDocBaselineError as exc:
    if "requirements.clean_poweroff must be true" not in str(exc):
        raise SystemExit(f"design-doc baseline helper reported unexpected requirement error: {exc}")
else:
    raise SystemExit("design-doc baseline helper accepted evidence without strict clean-poweroff requirements")
bad_design_doc_payload = copy.deepcopy(acceptance_payload)
bad_design_doc_payload["requirements"]["artifact_load"] = False
try:
    design_doc_baseline_module.render_snippet(bad_design_doc_payload, acceptance_json)
except design_doc_baseline_module.DesignDocBaselineError as exc:
    if "requirements.artifact_load must match" not in str(exc):
        raise SystemExit(f"design-doc baseline helper reported unexpected artifact-load requirement error: {exc}")
else:
    raise SystemExit("design-doc baseline helper accepted mismatched artifact load requirements")
bad_design_doc_payload = copy.deepcopy(acceptance_payload)
bad_design_doc_payload["requirements"].pop("build_provenance", None)
try:
    design_doc_baseline_module.render_snippet(bad_design_doc_payload, acceptance_json)
except design_doc_baseline_module.DesignDocBaselineError as exc:
    if "requirements.build_provenance must be a boolean" not in str(exc):
        raise SystemExit(f"design-doc baseline helper reported unexpected build-provenance requirement error: {exc}")
else:
    raise SystemExit("design-doc baseline helper accepted evidence without a build-provenance requirement")
bad_design_doc_payload = copy.deepcopy(acceptance_payload)
bad_design_doc_payload["evidence_checklist"] = [
    item for item in bad_design_doc_payload["evidence_checklist"] if item.get("name") != "release-gate summary"
]
try:
    design_doc_baseline_module.render_snippet(bad_design_doc_payload, acceptance_json)
except design_doc_baseline_module.DesignDocBaselineError as exc:
    if "evidence_checklist order" not in str(exc):
        raise SystemExit(f"design-doc baseline helper reported unexpected checklist error: {exc}")
else:
    raise SystemExit("design-doc baseline helper accepted evidence without the release-gate summary checklist")
design_doc_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_design_doc_baseline.py"),
        str(acceptance_json),
        "--evidence-label",
        "synthetic-clean-host-cli",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if design_doc_cli.returncode != 0:
    raise SystemExit(f"design-doc baseline CLI failed: {design_doc_cli.stderr}")
if "synthetic-clean-host-cli" not in design_doc_cli.stdout or "| Label |" not in design_doc_cli.stdout:
    raise SystemExit("design-doc baseline CLI did not print the expected snippet")
if "| Clean-host baseline table on a fresh Apple Silicon host | Open |" not in design_doc_cli.stdout:
    raise SystemExit("design-doc baseline CLI did not keep rehearsal evidence open by default")
design_doc_cli_output = verify_dir / "design-doc-snippet.md"
design_doc_output_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_design_doc_baseline.py"),
        str(acceptance_json),
        "--evidence-label",
        "synthetic-clean-host-output",
        "--output",
        str(design_doc_cli_output),
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if design_doc_output_cli.returncode != 0:
    raise SystemExit(f"design-doc baseline output CLI failed: {design_doc_output_cli.stderr}")
if design_doc_output_cli.stdout != "":
    raise SystemExit("design-doc baseline output CLI printed snippet despite --output")
if "synthetic-clean-host-output" not in design_doc_cli_output.read_text(encoding="utf-8"):
    raise SystemExit("design-doc baseline output CLI did not write the expected snippet")
design_doc_existing_output_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_design_doc_baseline.py"),
        str(acceptance_json),
        "--output",
        str(design_doc_cli_output),
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if design_doc_existing_output_cli.returncode == 0:
    raise SystemExit("design-doc baseline output CLI accepted an existing output file")
if "--output already exists" not in design_doc_existing_output_cli.stderr:
    raise SystemExit("design-doc baseline output CLI did not explain an existing output file")
design_doc_final_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_design_doc_baseline.py"),
        str(acceptance_json),
        "--evidence-label",
        "synthetic-clean-host-cli",
        "--final-release-baseline",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if design_doc_final_cli.returncode == 0:
    raise SystemExit("design-doc baseline final CLI accepted non-final acceptance JSON")
if "final_release_baseline=true" not in design_doc_final_cli.stderr:
    raise SystemExit("design-doc baseline final CLI did not explain missing final acceptance attestation")
acceptance_final_json = verify_dir / "acceptance-final.json"
acceptance_final_table = verify_dir / "acceptance-final.md"
acceptance_final_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_clean_host_acceptance.py"),
        str(verify_dir),
        "--artifact",
        "--pull",
        "--json-output",
        str(acceptance_final_json),
        "--table-output",
        str(acceptance_final_table),
        "--final-release-baseline",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if acceptance_final_cli.returncode != 0:
    raise SystemExit(f"clean-host acceptance final CLI failed: {acceptance_final_cli.stderr}")
acceptance_final_payload = json.loads(acceptance_final_json.read_text(encoding="utf-8"))
if acceptance_final_payload.get("final_release_baseline") is not True:
    raise SystemExit("clean-host acceptance final CLI did not record final_release_baseline=true")
if "| Label |" not in acceptance_final_table.read_text(encoding="utf-8"):
    raise SystemExit("clean-host acceptance final CLI did not write the final table output")
design_doc_final_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_design_doc_baseline.py"),
        str(acceptance_final_json),
        "--evidence-label",
        "synthetic-clean-host-cli",
        "--final-release-baseline",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if design_doc_final_cli.returncode != 0:
    raise SystemExit(f"design-doc baseline final CLI failed with final acceptance JSON: {design_doc_final_cli.stderr}")
if "| Clean-host baseline table on a fresh Apple Silicon host | Implemented |" not in design_doc_final_cli.stdout:
    raise SystemExit("design-doc baseline final CLI did not print an implemented audit row")
design_doc_final_output = verify_dir / "design-doc-final.md"
design_doc_final_output_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_design_doc_baseline.py"),
        str(acceptance_final_json),
        "--evidence-label",
        "synthetic-clean-host-cli",
        "--final-release-baseline",
        "--output",
        str(design_doc_final_output),
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if design_doc_final_output_cli.returncode != 0:
    raise SystemExit(f"design-doc baseline final output CLI failed: {design_doc_final_output_cli.stderr}")
final_audit_result = final_baseline_audit_module.audit_final_baseline(
    acceptance_final_json,
    acceptance_final_table,
    design_doc_final_output,
    evidence_label="synthetic-clean-host-cli",
)
if final_audit_result.get("final_release_baseline") is not True:
    raise SystemExit("final-baseline audit did not report final_release_baseline=true")
if final_audit_result.get("required_check_count") != len(acceptance_final_payload.get("required_checklist", [])):
    raise SystemExit("final-baseline audit reported the wrong checklist count")
final_audit_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_final_baseline_audit.py"),
        str(acceptance_final_json),
        "--table",
        str(acceptance_final_table),
        "--design-doc",
        str(design_doc_final_output),
        "--evidence-label",
        "synthetic-clean-host-cli",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if final_audit_cli.returncode != 0:
    raise SystemExit(f"final-baseline audit CLI failed: {final_audit_cli.stderr}")
if '"audited": true' not in final_audit_cli.stdout:
    raise SystemExit("final-baseline audit CLI did not print audited=true")
try:
    final_baseline_audit_module.audit_final_baseline(
        acceptance_json,
        acceptance_table,
        design_doc_cli_output,
        evidence_label="synthetic-clean-host-output",
    )
except final_baseline_audit_module.FinalBaselineAuditError as exc:
    if "final_release_baseline=true" not in str(exc):
        raise SystemExit(f"final-baseline audit non-final rejection was unexpected: {exc}")
else:
    raise SystemExit("final-baseline audit accepted non-final acceptance JSON")
stale_final_table = verify_dir / "acceptance-final-stale.md"
stale_final_table.write_text("stale table\n", encoding="utf-8")
try:
    final_baseline_audit_module.audit_final_baseline(
        acceptance_final_json,
        stale_final_table,
        design_doc_final_output,
        evidence_label="synthetic-clean-host-cli",
    )
except final_baseline_audit_module.FinalBaselineAuditError as exc:
    if "--table does not match" not in str(exc):
        raise SystemExit(f"final-baseline audit stale table rejection was unexpected: {exc}")
else:
    raise SystemExit("final-baseline audit accepted a stale accepted table")
stale_design_doc = verify_dir / "design-doc-final-stale.md"
stale_design_doc.write_text("stale design doc\n", encoding="utf-8")
try:
    final_baseline_audit_module.audit_final_baseline(
        acceptance_final_json,
        acceptance_final_table,
        stale_design_doc,
        evidence_label="synthetic-clean-host-cli",
    )
except final_baseline_audit_module.FinalBaselineAuditError as exc:
    if "--design-doc does not match" not in str(exc):
        raise SystemExit(f"final-baseline audit stale design-doc rejection was unexpected: {exc}")
else:
    raise SystemExit("final-baseline audit accepted a stale design-doc snippet")
acceptance_collision_json = verify_dir / "acceptance-table-collision.json"
acceptance_collision_table = verify_dir / "acceptance-table-collision.md"
acceptance_collision_table.write_text("existing table\n", encoding="utf-8")
acceptance_collision_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_clean_host_acceptance.py"),
        str(verify_dir),
        "--artifact",
        "--pull",
        "--json-output",
        str(acceptance_collision_json),
        "--table-output",
        str(acceptance_collision_table),
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if acceptance_collision_cli.returncode == 0:
    raise SystemExit("clean-host acceptance CLI accepted an existing table output path")
acceptance_collision_payload = json.loads(acceptance_collision_json.read_text(encoding="utf-8"))
if acceptance_collision_payload.get("schema_version") != 1:
    raise SystemExit("clean-host acceptance CLI collision JSON did not record schema_version=1")
if acceptance_collision_payload.get("accepted") is not False:
    raise SystemExit("clean-host acceptance CLI collision JSON did not record accepted=false")
if "--table-output already exists" not in acceptance_collision_payload.get("error", ""):
    raise SystemExit("clean-host acceptance CLI collision JSON did not explain table-output collision")
if acceptance_collision_table.read_text(encoding="utf-8") != "existing table\n":
    raise SystemExit("clean-host acceptance CLI overwrote an existing table output path")
acceptance_same_output = verify_dir / "acceptance-same-output.json"
acceptance_same_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_clean_host_acceptance.py"),
        str(verify_dir),
        "--artifact",
        "--pull",
        "--json-output",
        str(acceptance_same_output),
        "--table-output",
        str(acceptance_same_output),
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if acceptance_same_cli.returncode == 0:
    raise SystemExit("clean-host acceptance CLI accepted the same JSON/table output path")
if acceptance_same_output.exists():
    raise SystemExit("clean-host acceptance CLI wrote an output artifact for a same-path rejection")
if "--json-output and --table-output must be different paths" not in acceptance_same_cli.stderr:
    raise SystemExit("clean-host acceptance CLI did not explain same-path output rejection")
acceptance_final_missing_json_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_clean_host_acceptance.py"),
        str(verify_dir),
        "--artifact",
        "--pull",
        "--final-release-baseline",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if acceptance_final_missing_json_cli.returncode == 0:
    raise SystemExit("clean-host acceptance CLI accepted final baseline without JSON output")
if "--json-output is required with --final-release-baseline" not in acceptance_final_missing_json_cli.stderr:
    raise SystemExit("clean-host acceptance CLI did not explain missing final JSON output")
acceptance_final_missing_table_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_clean_host_acceptance.py"),
        str(verify_dir),
        "--artifact",
        "--pull",
        "--json-output",
        str(verify_dir / "acceptance-final-missing-table.json"),
        "--final-release-baseline",
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if acceptance_final_missing_table_cli.returncode == 0:
    raise SystemExit("clean-host acceptance CLI accepted final baseline without table output")
if "--table-output is required with --final-release-baseline" not in acceptance_final_missing_table_cli.stderr:
    raise SystemExit("clean-host acceptance CLI did not explain missing final table output")
acceptance_early_output = verify_dir / "acceptance-early-output.json"
acceptance_early_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_clean_host_acceptance.py"),
        str(verify_dir / "missing-evidence-dir"),
        "--artifact",
        "--pull",
        "--json-output",
        str(acceptance_early_output),
        "--table-output",
        str(acceptance_early_output),
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if acceptance_early_cli.returncode == 0:
    raise SystemExit("clean-host acceptance CLI accepted same output paths before evidence validation")
if acceptance_early_output.exists():
    raise SystemExit("clean-host acceptance CLI wrote an output artifact for early output validation")
if "--json-output and --table-output must be different paths" not in acceptance_early_cli.stderr:
    raise SystemExit("clean-host acceptance CLI did not validate output arguments before evidence")
acceptance_reject_json = verify_dir / "acceptance-reject.json"
acceptance_reject_table = verify_dir / "acceptance-reject.md"
good_acceptance_baseline = (verify_dir / "baseline.md").read_text(encoding="utf-8")
(verify_dir / "baseline.md").write_text("| stale | baseline |\n| --- | --- |\n", encoding="utf-8")
acceptance_reject_cli = subprocess.run(
    [
        sys.executable,
        str(repo / "examples" / "os_mode_clean_host_acceptance.py"),
        str(verify_dir),
        "--artifact",
        "--pull",
        "--json-output",
        str(acceptance_reject_json),
        "--table-output",
        str(acceptance_reject_table),
    ],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if acceptance_reject_cli.returncode == 0:
    raise SystemExit("clean-host acceptance CLI accepted a stale baseline table")
acceptance_reject_payload = json.loads(acceptance_reject_json.read_text(encoding="utf-8"))
if acceptance_reject_payload.get("schema_version") != 1:
    raise SystemExit("clean-host acceptance CLI rejection JSON did not record schema_version=1")
if acceptance_reject_payload.get("accepted") is not False:
    raise SystemExit("clean-host acceptance CLI rejection JSON did not record accepted=false")
if "baseline.md does not match release evidence" not in acceptance_reject_payload.get("error", ""):
    raise SystemExit("clean-host acceptance CLI rejection JSON did not explain stale baseline")
if acceptance_reject_table.exists():
    raise SystemExit("clean-host acceptance CLI wrote a table for rejected evidence")
(verify_dir / "baseline.md").write_text(good_acceptance_baseline, encoding="utf-8")
release_verify_result = release_gate_module.verify_release_evidence_archive(
    verify_dir,
    require_clean_cache=True,
    require_cache_entry_absent=True,
    require_artifact=True,
    require_pull=True,
    require_clean_host_preflight=True,
)
if release_verify_result.get("verified") is not True:
    raise SystemExit("release gate did not verify its own evidence archive")
good_baseline = (verify_dir / "baseline.md").read_text(encoding="utf-8")
(verify_dir / "baseline.md").write_text("| stale | baseline |\n| --- | --- |\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "baseline.md does not match release evidence" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected baseline error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a stale baseline table")
(verify_dir / "baseline.md").write_text(good_baseline, encoding="utf-8")
bad_verify_summary = dict(verify_gate_summary)
bad_verify_summary["baseline_table"] = str(verify_dir / "stale-baseline.md")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "summary baseline_table does not match archive" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected summary path error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a stale summary baseline_table path")
verify_dir.joinpath("release-gate-summary.json").write_text(json.dumps(verify_gate_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_summary = dict(verify_gate_summary)
bad_verify_summary["preflight_json"] = str(verify_dir / "other-preflight.json")
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "summary preflight_json does not match" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected preflight source error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a mismatched summary preflight_json path")
verify_dir.joinpath("release-gate-summary.json").write_text(json.dumps(verify_gate_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_summary = dict(verify_gate_summary)
bad_verify_summary["clean_host_baseline"] = False
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "clean_host_baseline=true" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected clean-host-baseline summary error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a summary without clean_host_baseline=true")
verify_dir.joinpath("release-gate-summary.json").write_text(json.dumps(verify_gate_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_summary = dict(verify_gate_summary)
bad_verify_summary.pop("image_was_explicit", None)
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "image_was_explicit must be a boolean" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected missing image_was_explicit error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted summary without image_was_explicit")
verify_dir.joinpath("release-gate-summary.json").write_text(json.dumps(verify_gate_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_summary = dict(verify_gate_summary)
bad_verify_summary["image_was_explicit"] = "false"
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "image_was_explicit must be a boolean" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected non-boolean image_was_explicit error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted non-boolean image_was_explicit")
verify_dir.joinpath("release-gate-summary.json").write_text(json.dumps(verify_gate_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_summary = dict(verify_gate_summary)
bad_verify_summary["image_was_explicit"] = True
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "positional image does not match summary invocation" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected explicit-image summary error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted artifact evidence missing the explicit image positional")
verify_dir.joinpath("release-gate-summary.json").write_text(json.dumps(verify_gate_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
bad_verify_preflight["release_gate_command"].insert(1, verify_image)
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "positional image does not match summary invocation" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected artifact-only command image error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted an artifact-only preflight command with a positional image")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["artifact_manifest"] = dict(verify_preflight["artifact_manifest"])
bad_verify_preflight["artifact_manifest"]["path"] = str(verify_dir / "other-artifact-manifest.json")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "preflight artifact_manifest path does not match" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected preflight artifact error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight for a different artifact manifest")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["schema_version"] = 2
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "schema_version must be 1" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected preflight schema-version error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight with the wrong schema version")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["errors"] = ["forced preflight error"]
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "preflight recorded errors" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected preflight recorded-errors error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight with recorded errors")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
bad_verify_preflight["release_gate_command"].extend(
    ["--preflight-json", str(verify_dir / "clean-host-preflight.json")]
)
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "repeats option: --preflight-json" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected repeated preflight option error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command with repeated --preflight-json")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = remove_command_option(verify_preflight["release_gate_command"], "--cache-dir")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "missing --cache-dir" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected missing cache-dir error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command without --cache-dir")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
bad_verify_preflight["release_gate_command"].append("--allow-existing-output-dir")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "must not include --allow-existing-output-dir" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected allow-existing-output error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command that allowed an existing output directory")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
bad_verify_preflight["release_gate_command"].append("--skip-pull")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "must not include --skip-pull" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected skip-pull error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command that skipped registry pulls")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
baseline_option_index = bad_verify_preflight["release_gate_command"].index("--clean-host-baseline")
bad_verify_preflight["release_gate_command"][baseline_option_index:baseline_option_index] = [
    "--build-command",
    "make BLK=1 NET=1",
]
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "unexpected option: --build-command" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected unknown-option error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command with an unexpected option")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
baseline_option_index = bad_verify_preflight["release_gate_command"].index("--clean-host-baseline")
bad_verify_preflight["release_gate_command"].insert(baseline_option_index, "trailing-positional")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "unexpected positional argument after options" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected trailing-positional error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command with a trailing positional")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
bad_verify_preflight["release_gate_command"].append("--clean-host-baseline")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "repeats option: --clean-host-baseline" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected repeated-baseline-flag error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command with repeated --clean-host-baseline")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
bad_verify_preflight["release_gate_command"].extend(["--runtime", "docker"])
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "must end with --clean-host-baseline" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected baseline-last error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command with arguments after --clean-host-baseline")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = move_command_option_pair_before(
    verify_preflight["release_gate_command"],
    "--cache-dir",
    "--output-dir",
)
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "options are not in preflight-generated order" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected option-order error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command with reordered options")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
bad_verify_preflight["release_gate_command"][0] = str(repo / "examples" / "not_release_gate.py")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "executable is not os_mode_release_gate.py" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected preflight command helper error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command for a different helper")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["runtime"] = dict(verify_preflight["runtime"])
bad_verify_preflight["runtime"]["selected"] = "containerd"
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "selected runtime is invalid" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected invalid selected-runtime error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted an invalid selected runtime")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["runtime"] = dict(verify_preflight["runtime"])
bad_verify_preflight["runtime"]["requested"] = "containerd"
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "requested runtime is invalid" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected invalid requested-runtime error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted an invalid requested runtime")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["runtime"] = dict(verify_preflight["runtime"])
bad_verify_preflight["runtime"]["requested"] = "docker"
bad_verify_preflight["runtime"]["selected"] = "podman"
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
preflight_option_index = bad_verify_preflight["release_gate_command"].index("--preflight-json")
bad_verify_preflight["release_gate_command"][preflight_option_index:preflight_option_index] = ["--runtime", "docker"]
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "selected runtime does not match" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected selected-runtime mismatch error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a selected runtime that disagreed with requested runtime")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
preflight_option_index = bad_verify_preflight["release_gate_command"].index("--preflight-json")
bad_verify_preflight["release_gate_command"][preflight_option_index:preflight_option_index] = ["--runtime", "podman"]
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "runtime does not match" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected preflight command runtime error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command for a different runtime")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
cache_dir_index = bad_verify_preflight["release_gate_command"].index("--cache-dir")
bad_verify_preflight["release_gate_command"][cache_dir_index + 1] = str(verify_dir / "other-cache-root")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "cache dir does not match" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected preflight command cache-dir error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command for a different cache dir")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
bad_verify_preflight["release_gate_command"] = remove_command_option(
    bad_verify_preflight["release_gate_command"],
    "--name",
)
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "omitted --name" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected omitted cache-name error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a custom cache entry without --name")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
cache_name_index = bad_verify_preflight["release_gate_command"].index("--name")
bad_verify_preflight["release_gate_command"][cache_name_index + 1] = "other-cache-entry"
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "cache name does not match" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected preflight command cache-name error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command for a different cache name")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
artifact_option_index = bad_verify_preflight["release_gate_command"].index("--artifact-manifest")
bad_verify_preflight["release_gate_command"][artifact_option_index + 1] = str(verify_dir / "other-artifact-manifest.json")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "option --artifact-manifest does not match expected path" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected preflight command artifact error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command for a different artifact manifest")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["release_gate_command"] = list(verify_preflight["release_gate_command"])
bad_verify_preflight["release_gate_command"].insert(1, "registry.example.com/os@sha256:" + "f" * 64)
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "contains unexpected image_ref values" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected preflight command image error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight command with a different image_ref")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
bad_verify_summary = dict(verify_gate_summary)
bad_verify_summary["cache_preflight"] = {
    "path": str(verify_dir / "cache-entry"),
    "exists": True,
    "clean": True,
    "entries": [],
}
(verify_dir / "release-gate-summary.json").write_text(json.dumps(bad_verify_summary, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "cache entry existed" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected clean-cache error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a non-absent clean-host cache entry")
verify_dir.joinpath("release-gate-summary.json").write_text(json.dumps(verify_gate_summary, indent=2) + "\n", encoding="utf-8")
bad_verify_preflight = dict(verify_preflight)
bad_verify_preflight["cache_entry"] = dict(verify_preflight["cache_entry"])
bad_verify_preflight["cache_entry"]["exists"] = True
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "preflight cache entry existed" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected preflight error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted a preflight with an existing cache entry")
bad_verify_preflight_time = dict(verify_preflight)
bad_verify_preflight_time["created_at_utc"] = "2026-05-18T01:00:02Z"
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(bad_verify_preflight_time, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
try:
    verify_evidence_module.verify_evidence(verify_args)
except verify_evidence_module.VerifyError as exc:
    if "after release evidence" not in str(exc):
        raise SystemExit(f"release evidence verifier reported unexpected preflight timestamp error: {exc}")
else:
    raise SystemExit("release evidence verifier accepted preflight evidence newer than release evidence")
(verify_dir / "clean-host-preflight.json").write_text(json.dumps(verify_preflight, indent=2) + "\n", encoding="utf-8")
verify_release_evidence["artifacts"]["clean_host_preflight_json"] = verify_artifact_entry("clean-host-preflight.json")
(verify_dir / "release-evidence.json").write_text(json.dumps(verify_release_evidence, indent=2) + "\n", encoding="utf-8")
runner_args = argparse.Namespace(
    image="registry.example.com/os@sha256:" + "c" * 64,
    cache_dir=pathlib.Path(sys.argv[1]) / "runner-cache",
    runtime="auto",
    name=None,
    clone_dest=None,
    smoke_output=None,
    perf_output=None,
    pull=False,
    no_reuse=False,
    strict_digest=None,
    print_only=False,
)
runner_command = runner_module.build_importer_command(runner_args, "1234-99")
if "--run" not in runner_command:
    raise SystemExit("krun_os_run did not enable run mode by default")
if "--reuse-extracted-output-dir" not in runner_command:
    raise SystemExit("krun_os_run did not enable extracted-bundle reuse by default")
if "--strict-digest" not in runner_command:
    raise SystemExit("krun_os_run did not enable strict digest for digest-pinned images")
if "vm-root-1234-99.raw" not in runner_command:
    raise SystemExit("krun_os_run did not generate a unique APFS clone destination")
if "smoke-1234-99.json" not in runner_command:
    raise SystemExit("krun_os_run did not generate a unique smoke output path")
if not any(str(item).endswith("os_mode_import_container_bundle.py") for item in runner_command):
    raise SystemExit("krun_os_run did not delegate to the bundle importer")
runner_args.pull = True
runner_command = runner_module.build_importer_command(runner_args, "1234-99")
if "--pull" not in runner_command:
    raise SystemExit("krun_os_run did not forward --pull to the importer")
runner_args.pull = False
runner_args.no_reuse = True
runner_args.strict_digest = False
runner_args.print_only = True
runner_command = runner_module.build_importer_command(runner_args, "1234-100")
if "--reuse-extracted-output-dir" in runner_command:
    raise SystemExit("krun_os_run ignored --no-reuse")
if "--strict-digest" in runner_command:
    raise SystemExit("krun_os_run ignored --no-strict-digest")
if "--run" in runner_command:
    raise SystemExit("krun_os_run enabled run mode for --print-only")
runner_cache = pathlib.Path(sys.argv[1]) / "runner-clean-cache"
runner_entry = runner_cache / "os-clean-test"
runner_bundle = runner_entry / "libkrun-os-bundle"
runner_bundle.mkdir(parents=True)
(runner_entry / ".libkrun-os-bundle-import.json").write_text("{}\n", encoding="utf-8")
(runner_bundle / "manifest.json").write_text(
    json.dumps({
        "root_disk": "root.raw",
        "kernel": "kernel",
        "initramfs": None,
    }) + "\n",
    encoding="utf-8",
)
(runner_bundle / "source-manifest.json").write_text("{}\n", encoding="utf-8")
(runner_bundle / "root.raw").write_text("root", encoding="utf-8")
(runner_bundle / "kernel").write_text("kernel", encoding="utf-8")
ephemeral_clone = runner_bundle / "vm-root-1234-99.raw"
ephemeral_smoke = runner_bundle / "smoke-1234-99.json"
persistent_disk = runner_bundle / "persistent.raw"
ephemeral_clone.write_text("clone", encoding="utf-8")
ephemeral_smoke.write_text("smoke", encoding="utf-8")
persistent_disk.write_text("persistent", encoding="utf-8")
runner_clean_args = argparse.Namespace(
    image=None,
    cache_dir=runner_cache,
    name=None,
    clean_cache=True,
    delete_extracted_bundles=False,
    older_than_hours=0.0,
    dry_run=False,
)
if runner_module.clean_cache(runner_clean_args) != 0:
    raise SystemExit("krun_os_run cache cleanup failed for ephemeral files")
if ephemeral_clone.exists() or ephemeral_smoke.exists():
    raise SystemExit("krun_os_run cache cleanup did not remove wrapper-generated ephemeral files")
if not persistent_disk.exists():
    raise SystemExit("krun_os_run cache cleanup removed a persistent VM disk")
runner_clean_args.delete_extracted_bundles = True
if runner_module.clean_cache(runner_clean_args) == 0:
    raise SystemExit("krun_os_run deleted or accepted a cache entry containing an unknown persistent disk")
if not runner_entry.exists():
    raise SystemExit("krun_os_run removed a refused cache entry")
persistent_disk.unlink()
if runner_module.clean_cache(runner_clean_args) != 0:
    raise SystemExit("krun_os_run did not delete a safe extracted bundle cache entry")
if runner_entry.exists():
    raise SystemExit("krun_os_run did not remove a safe extracted bundle cache entry")
diagnostic_cases = {
    "--strict-digest with --image requires image@sha256:<digest>": "image-resolution",
    "failed to copy /libkrun-os-bundle": "image-extraction",
    "root_disk_sha256 does not match": "manifest-validation",
    "--clone-dest destination already exists": "output-path",
    "bundle directory must be on APFS": "apfs-clone",
    "required repo helper does not exist": "host-launcher",
    "smoke evidence observed PID 1 'init.krun'": "guest-readiness",
    "--reuse-extracted-output-dir image reference does not match metadata": "cache-reuse",
}
for message, expected in diagnostic_cases.items():
    actual = bundle_module.diagnostic_category(message)
    if actual != expected:
        raise SystemExit(f"diagnostic category for {message!r} was {actual!r}, expected {expected!r}")
pulled_images = []
old_bundle_run = bundle_module.run
try:
    bundle_module.run = lambda command: pulled_images.append(command)
    bundle_module.pull_image("docker", "example-os@sha256:" + ("d" * 64))
finally:
    bundle_module.run = old_bundle_run
if pulled_images != [["docker", "pull", "example-os@sha256:" + ("d" * 64)]]:
    raise SystemExit(f"bundle importer pull_image used unexpected command: {pulled_images}")

evidence_bundle = pathlib.Path(sys.argv[1]) / "release-evidence-bundle"
evidence_bundle.mkdir()
evidence_root = evidence_bundle / "root.raw"
evidence_kernel = evidence_bundle / "kernel"
evidence_root.write_text("root", encoding="utf-8")
evidence_kernel.write_text("kernel", encoding="utf-8")
evidence_manifest = {
    "kind": "libkrun.os-bundle.v1",
    "manifest_schema_version": 1,
    "platform": "linux/arm64",
    "source_image": "example-os:latest",
    "source_digest": "example-os@sha256:" + ("a" * 64),
    "kernel": "kernel",
    "kernel_sha256": hashlib.sha256(b"kernel").hexdigest(),
    "kernel_format": 2,
    "initramfs": None,
    "initramfs_sha256": None,
    "root_disk": "root.raw",
    "root_disk_sha256": hashlib.sha256(b"root").hexdigest(),
    "root_disk_size_bytes": evidence_root.stat().st_size,
    "root_disk_allocated_bytes": None,
    "root_device": "/dev/vda",
    "expected_root": "/dev/vda",
    "root_fstype": "ext4",
    "root_options": None,
    "init": "/sbin/init",
    "console": "ttyAMA0",
    "expected_pid1": "systemd",
    "expected_markers": [],
    "smoke_timeout_sec": 30,
    "smoke_poweroff_after_ready": True,
    "smoke_wait_exit_after_ready_sec": 60,
    "require_apfs_clone": True,
    "allow_full_copy_fallback": False,
}
(evidence_bundle / "manifest.json").write_text(json.dumps(evidence_manifest, indent=2) + "\n", encoding="utf-8")
(evidence_bundle / "source-manifest.json").write_text(
    json.dumps({"source": "test", "timings_ms": {"export_rootfs": 8}}) + "\n",
    encoding="utf-8",
)
evidence_smoke = {
    "ready": True,
    "exit_code": 0,
    "failure_reason": None,
    "timings": {
        "first_kernel_log_ms": 1,
        "root_ms": 2,
        "pid1_ms": 3,
        "console_ms": 4,
        "ready_ms": 5,
    },
    "observed_root": "/dev/vda",
    "observed_pid1": "systemd",
    "observed_consoles": ["ttyAMA0"],
    "observed_network": "skipped",
    "output_lines": [
        "[    0.000000] Booting Linux on physical CPU 0x0000000000",
        "KRUN_OSMODE: root=/dev/vda ext4 rw,relatime",
        "KRUN_OSMODE: pid1=systemd /usr/lib/systemd/systemd",
        "KRUN_OSMODE: console=ttyAMA0",
        "KRUN_OSMODE: ready",
    ],
    "launcher_pid": 123,
    "process_parent_pid": 123,
    "process_pid": 124,
    "child_pid": 124,
    "wait_exit_after_ready_sec": 60,
    "bundle": {
        "timings_ms": {
            "image_pull": 9,
            "bundle_extraction": 10,
            "apfs_clone": 2,
            "smoke": 30,
            "post_extraction_run": 35,
            "importer_total": 50,
        },
        "apfs_clone_command": ["examples/os_mode_apfs_clone.sh", "root.raw", "vm-root.raw"],
        "os_mode_command": ["examples/os_mode", "--root-disk", "vm-root.raw"],
        "smoke_command": ["examples/os_mode_smoke.py", "--", "examples/os_mode"],
    },
}
evidence_perf = {
    "failure_reason": None,
    "timings": {
        "root_ms": 2,
        "pid1_ms": 3,
        "console_ms": 4,
        "ready_ms": 5,
    },
    "observed_root": "/dev/vda",
    "observed_pid1": "systemd",
    "observed_consoles": ["ttyAMA0"],
    "observed_network": "skipped",
}
evidence_smoke_path = evidence_bundle / "smoke.json"
evidence_perf_path = evidence_bundle / "perf.json"
evidence_smoke_path.write_text(json.dumps(evidence_smoke, indent=2) + "\n", encoding="utf-8")
evidence_perf_path.write_text(json.dumps(evidence_perf, indent=2) + "\n", encoding="utf-8")
evidence_output = pathlib.Path(sys.argv[1]) / "release-evidence-out"
summary = evidence_module.collect_release_evidence(
    argparse.Namespace(
        bundle_dir=evidence_bundle,
        smoke_json=evidence_smoke_path,
        perf_json=evidence_perf_path,
        preflight_json=None,
        artifact_manifest_json=None,
        artifact_load_ms=None,
        image_ref="example-os@sha256:" + ("a" * 64),
        output_dir=evidence_output,
        build_command=["make BLK=1 NET=1"],
        apfs_path=evidence_bundle,
        allow_existing_output_dir=False,
    )
)
if summary.get("image_ref") != "example-os@sha256:" + ("a" * 64):
    raise SystemExit("release evidence did not record image ref")
if summary.get("smoke", {}).get("observed_pid1") != "systemd":
    raise SystemExit("release evidence did not record smoke PID 1")
if summary.get("perf", {}).get("timings_ms", {}).get("ready_ms") != 5:
    raise SystemExit("release evidence did not record perf ready timing")
if summary.get("smoke", {}).get("timings_ms", {}).get("first_kernel_log_ms") != 1:
    raise SystemExit("release evidence did not record smoke first kernel log timing")
if not (evidence_output / "release-evidence.json").is_file():
    raise SystemExit("release evidence summary was not written")
for artifact in ("bundle-manifest.json", "source-manifest.json", "smoke.json", "perf.json"):
    if not (evidence_output / artifact).is_file():
        raise SystemExit(f"release evidence did not copy {artifact}")
bad_smoke = dict(evidence_smoke)
bad_smoke["observed_pid1"] = "init.krun"
bad_smoke_path = evidence_bundle / "bad-smoke.json"
bad_smoke_path.write_text(json.dumps(bad_smoke) + "\n", encoding="utf-8")
try:
    evidence_module.collect_release_evidence(
        argparse.Namespace(
            bundle_dir=evidence_bundle,
            smoke_json=bad_smoke_path,
            perf_json=None,
            preflight_json=None,
            artifact_manifest_json=None,
            artifact_load_ms=None,
            image_ref="example-os@sha256:" + ("a" * 64),
            output_dir=pathlib.Path(sys.argv[1]) / "release-evidence-bad-out",
            build_command=[],
            apfs_path=evidence_bundle,
            allow_existing_output_dir=False,
        )
    )
except evidence_module.EvidenceError as exc:
    if "init.krun" not in str(exc):
        raise SystemExit(f"release evidence bad-smoke test reported unexpected error: {exc}")
else:
    raise SystemExit("release evidence accepted smoke JSON with init.krun PID 1")
bad_smoke = copy.deepcopy(evidence_smoke)
bad_smoke["output_lines"] = ["KRUN_OSMODE: ready"]
bad_smoke_path = evidence_bundle / "bad-smoke-no-boot-log.json"
bad_smoke_path.write_text(json.dumps(bad_smoke) + "\n", encoding="utf-8")
try:
    evidence_module.collect_release_evidence(
        argparse.Namespace(
            bundle_dir=evidence_bundle,
            smoke_json=bad_smoke_path,
            perf_json=None,
            preflight_json=None,
            artifact_manifest_json=None,
            artifact_load_ms=None,
            image_ref="example-os@sha256:" + ("a" * 64),
            output_dir=pathlib.Path(sys.argv[1]) / "release-evidence-bad-no-boot-out",
            build_command=[],
            apfs_path=evidence_bundle,
            allow_existing_output_dir=False,
        )
    )
except evidence_module.EvidenceError as exc:
    if "early kernel boot log line" not in str(exc):
        raise SystemExit(f"release evidence no-boot-log test reported unexpected error: {exc}")
else:
    raise SystemExit("release evidence accepted smoke JSON without an early kernel boot log")

clone_helper = manifest_module.repo_path_string("examples/os_mode_apfs_clone.sh")
if clone_helper is None or not pathlib.Path(clone_helper).is_file():
    raise SystemExit("manifest checker did not resolve the APFS clone helper")
if manifest_module.required_repo_file_error("clone", clone_helper) is not None:
    raise SystemExit("manifest checker reported an existing helper as missing")
missing_helper = pathlib.Path(sys.argv[1]) / "missing-helper.sh"
missing_error = manifest_module.required_repo_file_error("missing_helper", str(missing_helper))
if missing_error is None or "does not exist or is not a file" not in missing_error:
    raise SystemExit("manifest checker did not report a missing helper file")

work = pathlib.Path(sys.argv[1]) / "relative-output-test"
work.mkdir()
old_cwd = pathlib.Path.cwd()
try:
    os.chdir(work)
    output_dir = module.prepare_output_dir(pathlib.Path("out"))
finally:
    os.chdir(old_cwd)

if not output_dir.is_absolute():
    raise SystemExit("prepare_output_dir did not return an absolute path")
if not output_dir.is_dir():
    raise SystemExit("prepare_output_dir did not create the output directory")
if output_dir.name != "out":
    raise SystemExit(f"prepare_output_dir returned an unexpected path: {output_dir}")
artifact_dir = pathlib.Path(sys.argv[1]) / "artifact-preflight"
artifact_dir.mkdir()
artifact_paths = module.output_artifact_paths(artifact_dir)
expected_artifacts = {"rootfs.tar", "overlay.tar", "root.raw", "vm-root.raw", "manifest.json"}
if set(artifact_paths) != expected_artifacts:
    raise SystemExit(f"output_artifact_paths returned unexpected keys: {artifact_paths}")
if module.existing_output_artifacts(artifact_dir):
    raise SystemExit("existing_output_artifacts reported conflicts for an empty output directory")
(artifact_dir / "root.raw").write_text("old-root", encoding="utf-8")
(artifact_dir / "vm-root.raw").write_text("old-clone", encoding="utf-8")
conflicts = {path.name for path in module.existing_output_artifacts(artifact_dir)}
if conflicts != {"root.raw", "vm-root.raw"}:
    raise SystemExit(f"existing_output_artifacts missed stale output artifacts: {conflicts}")
try:
    module.ensure_output_artifacts_absent(artifact_dir)
except SystemExit as exc:
    if "already contains OS-mode output artifacts" not in str(exc):
        raise SystemExit(f"ensure_output_artifacts_absent reported an unexpected error: {exc}")
else:
    raise SystemExit("ensure_output_artifacts_absent accepted stale output artifacts")
preflight_order_dir = pathlib.Path(sys.argv[1]) / "artifact-preflight-order"
preflight_order_dir.mkdir()
(preflight_order_dir / "rootfs.tar").write_text("old-rootfs", encoding="utf-8")
old_argv = sys.argv[:]
old_choose_runtime = module.choose_runtime
old_apfs_output_info = module.apfs_output_info
try:
    sys.argv = [
        "os_mode_build_container_rootfs.py",
        "--image",
        "alpine:3.23",
        "--output-dir",
        str(preflight_order_dir),
    ]
    module.apfs_output_info = lambda path: {
        "checked": False,
        "reason": "test",
        "is_apfs": None,
        "filesystem": None,
        "device": None,
    }
    module.choose_runtime = lambda requested: (_ for _ in ()).throw(
        SystemExit("runtime probe reached before artifact preflight")
    )
    try:
        module.main()
    except SystemExit as exc:
        if "already contains OS-mode output artifacts" not in str(exc):
            raise SystemExit(f"artifact preflight did not run before runtime probing: {exc}")
    else:
        raise SystemExit("main accepted stale output artifacts")
finally:
    sys.argv = old_argv
    module.choose_runtime = old_choose_runtime
    module.apfs_output_info = old_apfs_output_info
kernel_path = module.normalize_optional_path(pathlib.Path("kernel.img"))
if kernel_path is None or not pathlib.Path(kernel_path).is_absolute():
    raise SystemExit("normalize_optional_path did not return an absolute path")
if module.normalize_optional_path(None) is not None:
    raise SystemExit("normalize_optional_path did not preserve None")
if module.positive_size_mb("64") != 64:
    raise SystemExit("positive_size_mb did not parse a positive size")
try:
    module.positive_size_mb("0")
except argparse.ArgumentTypeError:
    pass
else:
    raise SystemExit("positive_size_mb accepted zero")
if module.positive_float("1.5") != 1.5:
    raise SystemExit("positive_float did not parse a positive float")
try:
    module.positive_float("0")
except argparse.ArgumentTypeError:
    pass
else:
    raise SystemExit("positive_float accepted zero")
if module.non_empty_arg("alpine:3.23") != "alpine:3.23":
    raise SystemExit("non_empty_arg rejected a valid image reference")
try:
    module.non_empty_arg("")
except argparse.ArgumentTypeError:
    pass
else:
    raise SystemExit("non_empty_arg accepted an empty value")
if module.non_empty_path("kernel.img") != pathlib.Path("kernel.img"):
    raise SystemExit("non_empty_path rejected a valid path")
try:
    module.non_empty_path("")
except argparse.ArgumentTypeError:
    pass
else:
    raise SystemExit("non_empty_path accepted an empty path")
if module.root_device_arg("/dev/vda") != "/dev/vda":
    raise SystemExit("root_device_arg rejected a valid root device")
if module.root_device_arg("PARTUUID=abcd-01") != "PARTUUID=abcd-01":
    raise SystemExit("root_device_arg rejected a valid PARTUUID root")
if module.root_device_arg("UUID=abcd") != "UUID=abcd":
    raise SystemExit("root_device_arg rejected a valid UUID root")
try:
    module.root_device_arg("/dev/vda quiet")
except argparse.ArgumentTypeError:
    pass
else:
    raise SystemExit("root_device_arg accepted a value with whitespace")
try:
    module.root_device_arg("relative-root")
except argparse.ArgumentTypeError:
    pass
else:
    raise SystemExit("root_device_arg accepted an unsupported root token")
if module.single_kernel_cmdline_token("ext4") != "ext4":
    raise SystemExit("single_kernel_cmdline_token rejected a valid token")
try:
    module.single_kernel_cmdline_token("ext4 quiet")
except argparse.ArgumentTypeError:
    pass
else:
    raise SystemExit("single_kernel_cmdline_token accepted whitespace")
if module.validate_systemd_unit_names(["serial-getty@ttyS0.service", "apt-daily.timer"]):
    raise SystemExit("validate_systemd_unit_names rejected valid units")
if not module.validate_systemd_unit_names(["../escape.service", "bad unit.service", ""]):
    raise SystemExit("validate_systemd_unit_names accepted invalid units")

if "serial-getty@ttyAMA0.service" in module.BUILDER_SCRIPT:
    raise SystemExit("builder script still hardcodes ttyAMA0 serial-getty service")
if "TTYPath=/dev/ttyAMA0" in module.BUILDER_SCRIPT:
    raise SystemExit("builder script still hardcodes ttyAMA0 control-shell path")
if "${SERIAL_CONSOLE}" not in module.BUILDER_SCRIPT:
    raise SystemExit("builder script does not use SERIAL_CONSOLE")

captured = []
def fake_run(command, *, capture=False):
    captured.append(command)

module.run = fake_run
module.build_ext4(
    "docker",
    "alpine:3.23",
    "linux/amd64",
    output_dir,
    64,
    "systemd",
    False,
    "ttyS0",
    True,
    [],
    True,
)
if not captured:
    raise SystemExit("build_ext4 did not invoke the container runtime")
command = captured[0]
for index, item in enumerate(command):
    if item == "SERIAL_CONSOLE=ttyS0" and index > 0 and command[index - 1] == "-e":
        break
else:
    raise SystemExit("build_ext4 did not pass the platform serial console to the builder")

network_args = argparse.Namespace(
    kernel="/abs/kernel",
    kernel_format=2,
    initramfs=None,
    root_device="/dev/vda",
    root_fstype="ext4",
    root_options=None,
    disk_sync="relaxed",
    platform="linux/arm64",
    init_mode="inject-smoke",
    network_smoke=True,
)
network_command = module.manifest_command(network_args, pathlib.Path("/abs/vm-root.raw"))
if "--kernel-cmdline" not in network_command:
    raise SystemExit("manifest_command did not include --kernel-cmdline for network smoke")
kernel_cmdline = network_command[network_command.index("--kernel-cmdline") + 1]
if "KRUN_OSMODE_NET=1" not in kernel_cmdline.split():
    raise SystemExit("manifest_command did not include KRUN_OSMODE_NET=1 for network smoke")

systemd_network_args = argparse.Namespace(**vars(network_args))
systemd_network_args.init_mode = "systemd"
systemd_network_command = module.manifest_command(systemd_network_args, pathlib.Path("/abs/vm-root.raw"))
systemd_kernel_cmdline = systemd_network_command[systemd_network_command.index("--kernel-cmdline") + 1]
if "systemd.unit=multi-user.target" not in systemd_kernel_cmdline.split():
    raise SystemExit("manifest_command dropped systemd target with network smoke")
if "KRUN_OSMODE_NET=1" not in systemd_kernel_cmdline.split():
    raise SystemExit("manifest_command dropped network marker with systemd network smoke")

if not bundle_module.image_reference_is_digest_pinned("example.com/os/bundle@sha256:" + ("a" * 64)):
    raise SystemExit("bundle importer rejected a digest-pinned image reference")
if bundle_module.image_reference_is_digest_pinned("example.com/os/bundle:latest"):
    raise SystemExit("bundle importer accepted a mutable image tag as digest-pinned")

bundle_dir = pathlib.Path(sys.argv[1]) / "bundle"
bundle_dir.mkdir()
(bundle_dir / "kernel").write_text("kernel", encoding="utf-8")
(bundle_dir / "initramfs").write_text("initramfs", encoding="utf-8")
(bundle_dir / "root.raw").write_bytes(b"\0" * 1024)

def bundle_sha(name):
    return hashlib.sha256((bundle_dir / name).read_bytes()).hexdigest()

bundle_manifest = {
    "kind": "libkrun.os-bundle.v1",
    "manifest_schema_version": 1,
    "source_image": "example-os:latest",
    "source_digest": None,
    "platform": "linux/arm64",
    "kernel": "kernel",
    "kernel_sha256": bundle_sha("kernel"),
    "kernel_format": 2,
    "initramfs": "initramfs",
    "initramfs_sha256": bundle_sha("initramfs"),
    "root_disk": "root.raw",
    "root_disk_sha256": bundle_sha("root.raw"),
    "root_disk_size_bytes": (bundle_dir / "root.raw").stat().st_size,
    "root_disk_allocated_bytes": bundle_module.allocated_size_bytes(bundle_dir / "root.raw"),
    "root_device": "/dev/vda",
    "expected_root": "/dev/vda",
    "root_fstype": "ext4",
    "root_options": None,
    "init": "/sbin/init",
    "console": "ttyAMA0",
    "expected_pid1": "systemd",
    "expected_markers": [],
    "smoke_timeout_sec": 30,
    "smoke_poweroff_after_ready": True,
    "smoke_wait_exit_after_ready_sec": 60,
    "require_apfs_clone": False,
    "allow_full_copy_fallback": False,
}
(bundle_dir / "manifest.json").write_text(json.dumps(bundle_manifest, indent=2) + "\n", encoding="utf-8")
validated_bundle = bundle_module.validate_manifest(bundle_dir)
if validated_bundle["kind"] != "libkrun.os-bundle.v1":
    raise SystemExit("bundle importer did not validate a good bundle manifest")
clone_dest = (bundle_dir / "vm-root.raw").resolve()
smoke_output = (bundle_dir / "smoke.json").resolve()
clone_command, launch_command, smoke_command, perf_command = bundle_module.build_commands(
    bundle_dir,
    validated_bundle,
    clone_dest,
    smoke_output,
    bundle_dir / "perf.json",
)
if perf_command is None:
    raise SystemExit("bundle importer did not create perf command when perf output was requested")
if str(clone_dest) not in clone_command:
    raise SystemExit("bundle importer clone command did not use requested clone destination")
if "--root-disk" not in launch_command or launch_command[launch_command.index("--root-disk") + 1] != str(clone_dest):
    raise SystemExit("bundle importer launch command did not attach the APFS clone destination")
if "--expect-root" not in smoke_command or "/dev/vda" not in smoke_command:
    raise SystemExit("bundle importer smoke command did not include expected root")
if "--expect-pid1" not in smoke_command or "systemd" not in smoke_command:
    raise SystemExit("bundle importer smoke command did not include expected PID 1")
if "--require-pid1-marker" not in perf_command:
    raise SystemExit("bundle importer perf command did not require PID 1 marker")
if "--expect-root" not in perf_command or "/dev/vda" not in perf_command:
    raise SystemExit("bundle importer perf command did not include expected root")
if "--expect-console" not in perf_command or "ttyAMA0" not in perf_command:
    raise SystemExit("bundle importer perf command did not include expected console")
if "--poweroff-after-ready" in perf_command:
    raise SystemExit("bundle importer perf command included smoke-only poweroff flag")
if not str(launch_command[0]).endswith("/examples/os_mode"):
    raise SystemExit("bundle importer did not point at the host-side examples/os_mode launcher")
release_gate_bundle_dir = pathlib.Path(sys.argv[1]) / "bundle-release-gate"
release_gate_bundle_dir.mkdir()
for file_name in ("kernel", "initramfs", "root.raw"):
    (release_gate_bundle_dir / file_name).write_bytes((bundle_dir / file_name).read_bytes())
release_gate_manifest = copy.deepcopy(bundle_manifest)
release_gate_manifest["source_digest"] = "example-os@sha256:" + ("e" * 64)
(release_gate_bundle_dir / "manifest.json").write_text(
    json.dumps(release_gate_manifest, indent=2) + "\n",
    encoding="utf-8",
)
captured_release_gate_commands = []
old_release_gate_run_command = release_gate_module.run_command
old_bundle_apfs_info = bundle_module.apfs_info
old_bundle_repo_file = bundle_module.repo_file
try:
    release_gate_module.run_command = lambda command: captured_release_gate_commands.append(command)
    bundle_module.apfs_info = lambda path: {
        "checked": True,
        "is_apfs": True,
        "filesystem": "apfs",
        "device": "test",
    }
    fake_launcher = pathlib.Path(sys.argv[1]) / "fake-os-mode"
    bundle_module.repo_file = (
        lambda relative, require_exists=True:
        fake_launcher if relative == "examples/os_mode" else old_bundle_repo_file(relative, require_exists=require_exists)
    )
    release_perf_output, release_perf_clone, release_perf_command = release_gate_module.run_perf_gate(
        release_gate_bundle_dir,
        "gate-test",
    )
finally:
    release_gate_module.run_command = old_release_gate_run_command
    bundle_module.apfs_info = old_bundle_apfs_info
    bundle_module.repo_file = old_bundle_repo_file
if release_perf_output.name != "release-perf-gate-test.json":
    raise SystemExit("release gate perf run returned unexpected perf output path")
if len(captured_release_gate_commands) != 2:
    raise SystemExit(f"release gate perf run executed unexpected commands: {captured_release_gate_commands}")
if captured_release_gate_commands[0] != release_perf_clone:
    raise SystemExit("release gate perf run did not execute the APFS clone command first")
if captured_release_gate_commands[1] != release_perf_command:
    raise SystemExit("release gate perf run did not execute the perf command second")
if "--require-pid1-marker" not in release_perf_command:
    raise SystemExit("release gate perf command did not require a PID 1 marker")
if "--expect-root" not in release_perf_command or "/dev/vda" not in release_perf_command:
    raise SystemExit("release gate perf command did not preserve the expected root")
smoke_output.write_text(json.dumps({
    "ready": True,
    "output_lines": [],
    "observed_root": "/dev/vda",
    "observed_root_line": "/dev/vda ext4 rw",
    "observed_pid1": "systemd",
    "observed_pid1_line": "systemd /usr/lib/systemd/systemd",
    "observed_console": "ttyAMA0",
    "observed_consoles": ["ttyAMA0"],
    "observed_network": "skipped",
}) + "\n", encoding="utf-8")
bundle_module.enrich_smoke_evidence(
    smoke_output,
    bundle_dir=bundle_dir.resolve(),
    manifest=validated_bundle,
    clone_dest=clone_dest,
    launch=launch_command,
    clone=clone_command,
    smoke=smoke_command,
    timings_ms={
        "bundle_extraction": None,
        "apfs_clone": 1,
        "smoke": 2,
        "post_extraction_run": 3,
        "importer_total": 4,
    },
    image_reference="example-os@sha256:" + ("a" * 64),
)
enriched = json.loads(smoke_output.read_text(encoding="utf-8"))
bundle_evidence = enriched.get("bundle")
if not isinstance(bundle_evidence, dict):
    raise SystemExit("bundle importer did not enrich smoke JSON with bundle metadata")
if bundle_evidence.get("source_image") != "example-os:latest":
    raise SystemExit("bundle smoke evidence did not include source image")
if bundle_evidence.get("clone_dest") != str(clone_dest):
    raise SystemExit("bundle smoke evidence did not include clone destination")
if bundle_evidence.get("expected_pid1") != "systemd":
    raise SystemExit("bundle smoke evidence did not include expected PID 1")
if bundle_evidence.get("root_disk_allocated_bytes") != bundle_module.allocated_size_bytes(bundle_dir / "root.raw"):
    raise SystemExit("bundle smoke evidence did not include root disk allocated size")
if bundle_evidence.get("os_mode_command") != launch_command:
    raise SystemExit("bundle smoke evidence did not include host launch command")
if bundle_evidence.get("timings_ms", {}).get("apfs_clone") != 1:
    raise SystemExit("bundle smoke evidence did not include importer timing metadata")
if bundle_evidence.get("timings_ms", {}).get("post_extraction_run") != 3:
    raise SystemExit("bundle smoke evidence did not include post-extraction timing metadata")
if bundle_evidence.get("timings_ms", {}).get("importer_total") != 4:
    raise SystemExit("bundle smoke evidence did not include total importer timing metadata")
if bundle_evidence.get("imported_image") != "example-os@sha256:" + ("a" * 64):
    raise SystemExit("bundle smoke evidence did not include imported image reference")

def expect_bad_smoke_evidence(name, payload, expected_error):
    smoke_output.unlink(missing_ok=True)
    smoke_output.write_text(json.dumps(payload) + "\n", encoding="utf-8")
    try:
        bundle_module.enrich_smoke_evidence(
            smoke_output,
            bundle_dir=bundle_dir.resolve(),
            manifest=validated_bundle,
            clone_dest=clone_dest,
            launch=launch_command,
            clone=clone_command,
            smoke=smoke_command,
            image_reference="example-os@sha256:" + ("a" * 64),
        )
    except bundle_module.BundleError as exc:
        if expected_error not in str(exc):
            raise SystemExit(f"{name} reported unexpected error: {exc}")
    else:
        raise SystemExit(f"bundle importer enriched invalid smoke evidence: {name}")

base_smoke_payload = {
    "ready": True,
    "output_lines": [],
    "observed_root": "/dev/vda",
    "observed_pid1": "systemd",
    "observed_console": "ttyAMA0",
    "observed_consoles": ["ttyAMA0"],
}

def smoke_payload_with(**updates):
    payload = dict(base_smoke_payload)
    payload.update(updates)
    return payload

expect_bad_smoke_evidence(
    "smoke-ready-false",
    smoke_payload_with(ready=False),
    "ready=true",
)
expect_bad_smoke_evidence(
    "smoke-root-mismatch",
    smoke_payload_with(observed_root="/dev/wrong"),
    "observed root",
)
expect_bad_smoke_evidence(
    "smoke-console-mismatch",
    smoke_payload_with(observed_console="ttyS0", observed_consoles=["ttyS0"]),
    "observed consoles",
)
expect_bad_smoke_evidence(
    "smoke-pid1-mismatch",
    smoke_payload_with(observed_pid1="init"),
    "observed PID 1",
)
expect_bad_smoke_evidence(
    "smoke-pid1-init-krun",
    smoke_payload_with(observed_pid1="init.krun"),
    "init.krun",
)
smoke_output.unlink()
bundle_module.validate_output_candidate(
    "--clone-dest",
    clone_dest,
    {
        "manifest": (bundle_dir / "manifest.json").resolve(),
        "root_disk": (bundle_dir / "root.raw").resolve(),
    },
)
try:
    bundle_module.validate_output_candidate(
        "--clone-dest",
        (bundle_dir / "root.raw").resolve(),
        {
            "manifest": (bundle_dir / "manifest.json").resolve(),
            "root_disk": (bundle_dir / "root.raw").resolve(),
        },
    )
except bundle_module.BundleError as exc:
    if "must differ from root_disk" not in str(exc) and "destination already exists" not in str(exc):
        raise SystemExit(f"bundle importer reported unexpected root-disk conflict: {exc}")
else:
    raise SystemExit("bundle importer accepted immutable root.raw as clone destination")
try:
    bundle_module.validate_manifest(bundle_dir, strict_digest=True)
except bundle_module.BundleError as exc:
    if "--strict-digest" not in str(exc):
        raise SystemExit(f"bundle importer strict digest check failed with wrong error: {exc}")
else:
    raise SystemExit("bundle importer accepted missing source digest in strict mode")

def expect_bad_bundle(name, mutate, expected):
    bad_dir = pathlib.Path(sys.argv[1]) / name
    bad_dir.mkdir()
    for file_name in ("kernel", "initramfs", "root.raw"):
        (bad_dir / file_name).write_bytes((bundle_dir / file_name).read_bytes())
    bad_manifest = copy.deepcopy(bundle_manifest)
    mutate(bad_manifest)
    (bad_dir / "manifest.json").write_text(json.dumps(bad_manifest, indent=2) + "\n", encoding="utf-8")
    try:
        bundle_module.validate_manifest(bad_dir)
    except bundle_module.BundleError as exc:
        if expected not in str(exc):
            raise SystemExit(f"{name} reported unexpected error: {exc}")
    else:
        raise SystemExit(f"{name} unexpectedly validated")

expect_bad_bundle("bundle-bad-kind", lambda manifest: manifest.update({"kind": "other"}), "kind must be")
expect_bad_bundle("bundle-bad-platform", lambda manifest: manifest.update({"platform": "darwin/arm64"}), "platform must be")
expect_bad_bundle("bundle-bad-console", lambda manifest: manifest.update({"console": "ttyS0"}), "console must be ttyAMA0")
expect_bad_bundle("bundle-bad-root-token", lambda manifest: manifest.update({"root_device": "relative-root"}), "root_device must start")
expect_bad_bundle("bundle-bad-root-whitespace", lambda manifest: manifest.update({"root_device": "/dev/vda quiet"}), "single kernel command-line token")
expect_bad_bundle("bundle-bad-checksum", lambda manifest: manifest.update({"root_disk_sha256": "0" * 64}), "root_disk_sha256 does not match")
expect_bad_bundle("bundle-bad-size", lambda manifest: manifest.update({"root_disk_size_bytes": 1}), "root_disk_size_bytes does not match")
expect_bad_bundle("bundle-bad-allocated-size", lambda manifest: manifest.update({"root_disk_allocated_bytes": -1}), "root_disk_allocated_bytes must be a non-negative integer or null")
expect_bad_bundle("bundle-bad-pid1", lambda manifest: manifest.update({"expected_pid1": "init.krun"}), "expected_pid1 must not be init.krun")
expect_bad_bundle("bundle-bad-fallback", lambda manifest: manifest.update({"allow_full_copy_fallback": True}), "allow_full_copy_fallback=true")
expect_bad_bundle("bundle-bad-path", lambda manifest: manifest.update({"root_disk": "../root.raw"}), "must stay inside")
PY

echo "==> baseline table helper self-test"
python3 examples/os_mode_baseline_table.py \
    --release-evidence "$tmpdir/release-evidence-out" \
    >"$tmpdir/baseline-table.md"
if ! grep -q "| example-os@sha256:" "$tmpdir/baseline-table.md"; then
    echo "baseline table did not include the release image reference" >&2
    cat "$tmpdir/baseline-table.md" >&2
    exit 1
fi
if ! grep -q "| -/9/8 | 10 | 2 | 1 | 2 | 3 | 5 | yes | 50 |" "$tmpdir/baseline-table.md"; then
    echo "baseline table did not summarize load/pull/export, bundle, perf, poweroff, and total timings" >&2
    cat "$tmpdir/baseline-table.md" >&2
    exit 1
fi
if python3 examples/os_mode_baseline_table.py >"$tmpdir/baseline-missing.out" 2>"$tmpdir/baseline-missing.err"; then
    echo "baseline table missing-input test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "provide --release-evidence or --smoke-json" "$tmpdir/baseline-missing.err"; then
    echo "baseline table missing-input test did not report the missing evidence" >&2
    cat "$tmpdir/baseline-missing.err" >&2
    exit 1
fi

echo "==> container bundle importer self-test"
python3 examples/os_mode_import_container_bundle.py \
    --bundle-dir "$tmpdir/bundle" \
    --clone-dest vm-root.raw \
    --smoke-output smoke.json \
    --perf-output perf.json \
    >"$tmpdir/bundle-importer.out"
if ! grep -q "apfs_clone_command: .*/examples/os_mode_apfs_clone.sh .*/root.raw .*/vm-root.raw" "$tmpdir/bundle-importer.out"; then
    echo "bundle importer did not print the APFS clone command" >&2
    cat "$tmpdir/bundle-importer.out" >&2
    exit 1
fi
if ! grep -q "os_mode_command: .*/examples/os_mode --kernel .*/kernel" "$tmpdir/bundle-importer.out" ||
   ! grep -q -- "--root-disk .*/vm-root.raw" "$tmpdir/bundle-importer.out"; then
    echo "bundle importer did not print the clone-backed os_mode command" >&2
    cat "$tmpdir/bundle-importer.out" >&2
    exit 1
fi
if ! grep -q "smoke_command: .*/examples/os_mode_smoke.py --timeout 30 --wait-exit-after-ready 60 --output .*/smoke.json --expect-root /dev/vda --expect-console ttyAMA0 --expect-pid1 systemd -- .*/examples/os_mode" "$tmpdir/bundle-importer.out"; then
    echo "bundle importer did not print the smoke wrapper with OS invariants" >&2
    cat "$tmpdir/bundle-importer.out" >&2
    exit 1
fi
if ! grep -q "perf_command: .*/examples/os_mode_perf.py --timeout 30 --output .*/perf.json --require-pid1-marker --expect-root /dev/vda --expect-console ttyAMA0 -- .*/examples/os_mode" "$tmpdir/bundle-importer.out"; then
    echo "bundle importer did not print the perf command with OS invariants" >&2
    cat "$tmpdir/bundle-importer.out" >&2
    exit 1
fi
if grep -q -- "perf_command: .*--poweroff-after-ready" "$tmpdir/bundle-importer.out"; then
    echo "bundle importer perf command unexpectedly included smoke-only poweroff flag" >&2
    cat "$tmpdir/bundle-importer.out" >&2
    exit 1
fi
printf old-clone > "$tmpdir/bundle/existing.raw"
if python3 examples/os_mode_import_container_bundle.py --bundle-dir "$tmpdir/bundle" --clone-dest existing.raw >"$tmpdir/bundle-existing-clone.out" 2>"$tmpdir/bundle-existing-clone.err"; then
    echo "bundle importer existing clone destination test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--clone-dest destination already exists" "$tmpdir/bundle-existing-clone.err"; then
    echo "bundle importer existing clone destination test did not report existing destination" >&2
    cat "$tmpdir/bundle-existing-clone.err" >&2
    exit 1
fi
if ! grep -q -- "diagnostic_category=output-path" "$tmpdir/bundle-existing-clone.err"; then
    echo "bundle importer existing clone destination test did not report output-path diagnostic" >&2
    cat "$tmpdir/bundle-existing-clone.err" >&2
    exit 1
fi
if python3 examples/os_mode_import_container_bundle.py --bundle-dir "$tmpdir/bundle" --clone-dest root.raw >"$tmpdir/bundle-root-clone.out" 2>"$tmpdir/bundle-root-clone.err"; then
    echo "bundle importer root.raw clone destination test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--clone-dest destination already exists" "$tmpdir/bundle-root-clone.err" &&
   ! grep -q -- "--clone-dest must differ from root_disk" "$tmpdir/bundle-root-clone.err"; then
    echo "bundle importer root.raw clone destination test did not reject immutable root disk" >&2
    cat "$tmpdir/bundle-root-clone.err" >&2
    exit 1
fi
if python3 examples/os_mode_import_container_bundle.py --bundle-dir "$tmpdir/bundle" --strict-digest >"$tmpdir/bundle-strict.out" 2>"$tmpdir/bundle-strict.err"; then
    echo "bundle importer strict digest test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--strict-digest requires source_digest" "$tmpdir/bundle-strict.err"; then
    echo "bundle importer strict digest test did not report missing immutable digest" >&2
    cat "$tmpdir/bundle-strict.err" >&2
    exit 1
fi
if python3 examples/os_mode_import_container_bundle.py --image example-os:latest --output-dir "$tmpdir/bundle-image-strict" --strict-digest >"$tmpdir/bundle-image-strict.out" 2>"$tmpdir/bundle-image-strict.err"; then
    echo "bundle importer strict image reference test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--strict-digest with --image requires image@sha256" "$tmpdir/bundle-image-strict.err"; then
    echo "bundle importer strict image reference test did not require digest-pinned image" >&2
    cat "$tmpdir/bundle-image-strict.err" >&2
    exit 1
fi
if ! grep -q -- "diagnostic_category=image-resolution" "$tmpdir/bundle-image-strict.err"; then
    echo "bundle importer strict image reference test did not report image-resolution diagnostic" >&2
    cat "$tmpdir/bundle-image-strict.err" >&2
    exit 1
fi
expect_bad_bundle_import() {
    name=$1
    expected=$2
    if python3 examples/os_mode_import_container_bundle.py \
        --bundle-dir "$tmpdir/$name" \
        --clone-dest vm-root.raw \
        >"$tmpdir/$name-import.out" 2>"$tmpdir/$name-import.err"; then
        echo "bundle importer $name negative CLI test unexpectedly succeeded" >&2
        exit 1
    fi
    if ! grep -q -- "$expected" "$tmpdir/$name-import.err"; then
        echo "bundle importer $name negative CLI test did not report expected error" >&2
        cat "$tmpdir/$name-import.err" >&2
        exit 1
    fi
    if grep -q "apfs_clone_command:" "$tmpdir/$name-import.out" ||
       grep -q "os_mode_command:" "$tmpdir/$name-import.out" ||
       grep -q "smoke_command:" "$tmpdir/$name-import.out"; then
        echo "bundle importer $name printed launch commands for an invalid bundle" >&2
        cat "$tmpdir/$name-import.out" >&2
        exit 1
    fi
}
expect_bad_bundle_import "bundle-bad-platform" "platform must be"
expect_bad_bundle_import "bundle-bad-checksum" "root_disk_sha256 does not match"
expect_bad_bundle_import "bundle-bad-console" "console must be ttyAMA0"
expect_bad_bundle_import "bundle-bad-pid1" "expected_pid1 must not be init.krun"
for name in bundle-bad-platform bundle-bad-checksum bundle-bad-console bundle-bad-pid1; do
    if ! grep -q -- "diagnostic_category=manifest-validation" "$tmpdir/$name-import.err"; then
        echo "bundle importer $name negative CLI test did not report manifest-validation diagnostic" >&2
        cat "$tmpdir/$name-import.err" >&2
        exit 1
    fi
done
python3 - "$tmpdir/bundle-image-extract" <<'PY'
import sys
from pathlib import Path
from unittest.mock import patch

import examples.os_mode_import_container_bundle as importer

output_dir = Path(sys.argv[1])
commands = []

def fake_run_capture(command):
    commands.append(command)
    return "container-123\n"

def fake_run(command, **kwargs):
    commands.append(command)
    if command[:2] == ["docker", "cp"]:
        (output_dir / "libkrun-os-bundle").mkdir(parents=True)
    return None

with patch.object(importer, "choose_runtime", return_value="docker"), \
     patch.object(importer, "run_capture", side_effect=fake_run_capture), \
     patch.object(importer.subprocess, "run", side_effect=fake_run):
    bundle_dir = importer.extract_image_bundle("example-os:latest", output_dir, "docker")

if bundle_dir != output_dir / "libkrun-os-bundle":
    raise SystemExit(f"unexpected extracted bundle dir: {bundle_dir}")
if ["docker", "create", "example-os:latest", "true"] not in commands:
    raise SystemExit(f"docker create command did not include placeholder command: {commands}")
if ["docker", "cp", "container-123:/libkrun-os-bundle", str(output_dir)] not in commands:
    raise SystemExit(f"docker cp command was not issued: {commands}")
if ["docker", "rm", "-f", "container-123"] not in commands:
    raise SystemExit(f"docker rm cleanup command was not issued: {commands}")
PY
python3 - "$tmpdir/bundle-generic-image" <<'PY'
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import examples.os_mode_import_container_bundle as importer

output_dir = Path(sys.argv[1])
commands = []

def fake_run_capture(command):
    commands.append(command)
    return "container-456\n"

def fake_run(command, **kwargs):
    commands.append(command)
    if command[:2] == ["docker", "cp"]:
        raise subprocess.CalledProcessError(1, command)
    return None

with patch.object(importer, "choose_runtime", return_value="docker"), \
     patch.object(importer, "run_capture", side_effect=fake_run_capture), \
     patch.object(importer.subprocess, "run", side_effect=fake_run):
    try:
        importer.extract_image_bundle("generic-rootfs:latest", output_dir, "docker")
    except importer.BundleError as exc:
        message = str(exc)
    else:
        raise SystemExit("generic image extraction unexpectedly succeeded")

if "not a libkrun OS bundle" not in message:
    raise SystemExit(f"generic image failure did not explain bundle requirement: {message}")
if importer.diagnostic_category(message) != "image-extraction":
    raise SystemExit("generic image failure did not classify as image-extraction")
if ["docker", "rm", "-f", "container-456"] not in commands:
    raise SystemExit(f"docker rm cleanup command was not issued after failed copy: {commands}")
if (output_dir / "libkrun-os-bundle").exists():
    raise SystemExit("generic image failure left a bundle directory behind")
PY
python3 - "$tmpdir/bundle" "$tmpdir/bundle-reuse" "$tmpdir/bundle-reuse-mismatch" "$tmpdir/bundle-reuse-missing-meta" <<'PY'
import json
import shutil
import sys
from pathlib import Path

source_bundle = Path(sys.argv[1])
for output_arg in sys.argv[2:]:
    output_dir = Path(output_arg)
    output_dir.mkdir()
    shutil.copytree(source_bundle, output_dir / "libkrun-os-bundle")

for output_arg in sys.argv[2:4]:
    output_dir = Path(output_arg)
    metadata = {
        "schema_version": 1,
        "image_reference": "example-os:latest",
        "runtime": "docker",
        "bundle_dir": str(output_dir / "libkrun-os-bundle"),
        "bundle_dir_name": "libkrun-os-bundle",
    }
    (output_dir / ".libkrun-os-bundle-import.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
PY
python3 examples/os_mode_import_container_bundle.py \
    --image example-os:latest \
    --output-dir "$tmpdir/bundle-reuse" \
    --reuse-extracted-output-dir \
    --clone-dest reuse-vm-root.raw \
    >"$tmpdir/bundle-reuse.out"
if ! grep -q "os_mode_command: .*/examples/os_mode --kernel .*/bundle-reuse/libkrun-os-bundle/kernel" "$tmpdir/bundle-reuse.out"; then
    echo "bundle importer reuse test did not print launch command from cached bundle" >&2
    cat "$tmpdir/bundle-reuse.out" >&2
    exit 1
fi
if python3 examples/os_mode_import_container_bundle.py --image other-os:latest --output-dir "$tmpdir/bundle-reuse-mismatch" --reuse-extracted-output-dir >"$tmpdir/bundle-reuse-mismatch.out" 2>"$tmpdir/bundle-reuse-mismatch.err"; then
    echo "bundle importer reuse mismatch test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--reuse-extracted-output-dir image reference does not match metadata" "$tmpdir/bundle-reuse-mismatch.err"; then
    echo "bundle importer reuse mismatch test did not reject mismatched image" >&2
    cat "$tmpdir/bundle-reuse-mismatch.err" >&2
    exit 1
fi
if python3 examples/os_mode_import_container_bundle.py --image example-os:latest --output-dir "$tmpdir/bundle-reuse-missing-meta" --reuse-extracted-output-dir >"$tmpdir/bundle-reuse-missing-meta.out" 2>"$tmpdir/bundle-reuse-missing-meta.err"; then
    echo "bundle importer missing reuse metadata test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--reuse-extracted-output-dir requires import metadata" "$tmpdir/bundle-reuse-missing-meta.err"; then
    echo "bundle importer missing reuse metadata test did not report missing metadata" >&2
    cat "$tmpdir/bundle-reuse-missing-meta.err" >&2
    exit 1
fi
printf old-perf > "$tmpdir/bundle/existing-perf.json"
if python3 examples/os_mode_import_container_bundle.py --bundle-dir "$tmpdir/bundle" --perf-output existing-perf.json >"$tmpdir/bundle-existing-perf.out" 2>"$tmpdir/bundle-existing-perf.err"; then
    echo "bundle importer existing perf output test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--perf-output destination already exists" "$tmpdir/bundle-existing-perf.err"; then
    echo "bundle importer existing perf output test did not report existing destination" >&2
    cat "$tmpdir/bundle-existing-perf.err" >&2
    exit 1
fi
if python3 examples/os_mode_import_container_bundle.py --bundle-dir "$tmpdir/bundle" --perf-output root.raw >"$tmpdir/bundle-root-perf.out" 2>"$tmpdir/bundle-root-perf.err"; then
    echo "bundle importer root.raw perf output test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--perf-output destination already exists" "$tmpdir/bundle-root-perf.err" &&
   ! grep -q -- "--perf-output must differ from root_disk" "$tmpdir/bundle-root-perf.err"; then
    echo "bundle importer root.raw perf output test did not reject immutable root disk" >&2
    cat "$tmpdir/bundle-root-perf.err" >&2
    exit 1
fi
if python3 examples/os_mode_import_container_bundle.py --bundle-dir "$tmpdir/bundle" --smoke-output same.json --perf-output same.json >"$tmpdir/bundle-same-evidence.out" 2>"$tmpdir/bundle-same-evidence.err"; then
    echo "bundle importer smoke/perf collision test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--perf-output must differ from --smoke-output" "$tmpdir/bundle-same-evidence.err"; then
    echo "bundle importer smoke/perf collision test did not report output collision" >&2
    cat "$tmpdir/bundle-same-evidence.err" >&2
    exit 1
fi

echo "==> shell helper syntax"
sh -n \
    examples/os_mode_apfs_clone.sh \
    examples/os_mode_apfs_validate.sh \
    ci/os_mode_linux_validate.sh \
    ci/os_mode_host_checks.sh

echo "==> Linux validation helper argument guards"
KRUN_OSMODE_LINUX_VALIDATE_SELFTEST=1 ci/os_mode_linux_validate.sh
if ! grep -q "KRUN_OSMODE_EXPECT_CONSOLE" ci/os_mode_linux_validate.sh; then
    echo "Linux validation helper does not expose KRUN_OSMODE_EXPECT_CONSOLE" >&2
    exit 1
fi
if ! grep -q -- "--expect-console" ci/os_mode_linux_validate.sh; then
    echo "Linux validation helper does not pass --expect-console to os_mode_smoke.py" >&2
    exit 1
fi

echo "==> APFS clone helper argument guards"
if examples/os_mode_apfs_clone.sh "" "$tmpdir/empty-source.raw" >"$tmpdir/apfs-empty-source.out" 2>"$tmpdir/apfs-empty-source.err"; then
    echo "APFS clone helper empty-source test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "Base image path must be non-empty" "$tmpdir/apfs-empty-source.err"; then
    echo "APFS clone helper empty-source test did not report empty base path" >&2
    cat "$tmpdir/apfs-empty-source.err" >&2
    exit 1
fi
if examples/os_mode_apfs_clone.sh "$tmpdir/missing-base.raw" "" >"$tmpdir/apfs-empty-dest.out" 2>"$tmpdir/apfs-empty-dest.err"; then
    echo "APFS clone helper empty-destination test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "Clone image path must be non-empty" "$tmpdir/apfs-empty-dest.err"; then
    echo "APFS clone helper empty-destination test did not report empty clone path" >&2
    cat "$tmpdir/apfs-empty-dest.err" >&2
    exit 1
fi
if examples/os_mode_apfs_validate.sh "" >"$tmpdir/apfs-validate-empty-workdir.out" 2>"$tmpdir/apfs-validate-empty-workdir.err"; then
    echo "APFS validate helper empty-workdir test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "Work directory must be non-empty" "$tmpdir/apfs-validate-empty-workdir.err"; then
    echo "APFS validate helper empty-workdir test did not report empty work directory" >&2
    cat "$tmpdir/apfs-validate-empty-workdir.err" >&2
    exit 1
fi
if examples/os_mode_apfs_validate.sh "$tmpdir/apfs-validate" 0 >"$tmpdir/apfs-validate-zero-size.out" 2>"$tmpdir/apfs-validate-zero-size.err"; then
    echo "APFS validate helper zero-size test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "SIZE_MB must be a positive integer" "$tmpdir/apfs-validate-zero-size.err"; then
    echo "APFS validate helper zero-size test did not report invalid size" >&2
    cat "$tmpdir/apfs-validate-zero-size.err" >&2
    exit 1
fi
if examples/os_mode_apfs_validate.sh "$tmpdir/apfs-validate" bad >"$tmpdir/apfs-validate-bad-size.out" 2>"$tmpdir/apfs-validate-bad-size.err"; then
    echo "APFS validate helper bad-size test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "SIZE_MB must be a positive integer" "$tmpdir/apfs-validate-bad-size.err"; then
    echo "APFS validate helper bad-size test did not report invalid size" >&2
    cat "$tmpdir/apfs-validate-bad-size.err" >&2
    exit 1
fi

echo "==> Docker context guard"
for pattern in \
    target \
    examples/target \
    '*.raw' \
    '*.dSYM' \
    '*.dylib' \
    examples/os_mode; do
    if ! grep -Fx -- "$pattern" .dockerignore >/dev/null; then
        echo ".dockerignore is missing required pattern: $pattern" >&2
        exit 1
    fi
done

echo "==> C API syntax"
cc -fsyntax-only -Iinclude examples/os_mode.c
cc -DOS_MODE_PARSE_SELFTEST -Iinclude examples/os_mode.c -o "$tmpdir/os_mode_parse_selftest"
if ! "$tmpdir/os_mode_parse_selftest" >"$tmpdir/os_mode_parse_selftest.out" 2>&1; then
    cat "$tmpdir/os_mode_parse_selftest.out" >&2
    exit 1
fi

echo "==> smoke/perf helper argument guards"
if python3 examples/os_mode_smoke.py --timeout 0 -- python3 -c 'print("unused")' >"$tmpdir/smoke-bad-timeout.out" 2>"$tmpdir/smoke-bad-timeout.err"; then
    echo "smoke helper zero-timeout argument test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "value must be greater than zero" "$tmpdir/smoke-bad-timeout.err"; then
    echo "smoke helper zero-timeout argument test did not report invalid timeout" >&2
    cat "$tmpdir/smoke-bad-timeout.err" >&2
    exit 1
fi
printf old-smoke-json > "$tmpdir/smoke-existing-output.json"
if python3 examples/os_mode_smoke.py --output "$tmpdir/smoke-existing-output.json" -- python3 -c 'print("unused")' >"$tmpdir/smoke-existing-output.out" 2>"$tmpdir/smoke-existing-output.err"; then
    echo "smoke helper existing-output argument test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--output destination already exists" "$tmpdir/smoke-existing-output.err"; then
    echo "smoke helper existing-output argument test did not report existing destination" >&2
    cat "$tmpdir/smoke-existing-output.err" >&2
    exit 1
fi
if python3 examples/os_mode_smoke.py --output "$tmpdir/missing-smoke-parent/smoke.json" -- python3 -c 'print("unused")' >"$tmpdir/smoke-missing-output-parent.out" 2>"$tmpdir/smoke-missing-output-parent.err"; then
    echo "smoke helper missing-output-parent argument test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--output parent directory does not exist" "$tmpdir/smoke-missing-output-parent.err"; then
    echo "smoke helper missing-output-parent argument test did not report missing parent" >&2
    cat "$tmpdir/smoke-missing-output-parent.err" >&2
    exit 1
fi
if python3 examples/os_mode_smoke.py --wait-exit-after-ready -1 -- python3 -c 'print("unused")' >"$tmpdir/smoke-bad-wait-exit.out" 2>"$tmpdir/smoke-bad-wait-exit.err"; then
    echo "smoke helper negative wait-exit argument test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "value must be non-negative" "$tmpdir/smoke-bad-wait-exit.err"; then
    echo "smoke helper negative wait-exit argument test did not report invalid wait" >&2
    cat "$tmpdir/smoke-bad-wait-exit.err" >&2
    exit 1
fi
if python3 examples/os_mode_smoke.py -- >"$tmpdir/smoke-missing-command.out" 2>"$tmpdir/smoke-missing-command.err"; then
    echo "smoke helper missing-command argument test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "missing os_mode command after --" "$tmpdir/smoke-missing-command.err"; then
    echo "smoke helper missing-command argument test did not report missing command" >&2
    cat "$tmpdir/smoke-missing-command.err" >&2
    exit 1
fi
if python3 examples/os_mode_perf.py --timeout 0 -- python3 -c 'print("unused")' >"$tmpdir/perf-bad-timeout.out" 2>"$tmpdir/perf-bad-timeout.err"; then
    echo "perf helper zero-timeout argument test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "value must be greater than zero" "$tmpdir/perf-bad-timeout.err"; then
    echo "perf helper zero-timeout argument test did not report invalid timeout" >&2
    cat "$tmpdir/perf-bad-timeout.err" >&2
    exit 1
fi
printf old-perf-json > "$tmpdir/perf-existing-output.json"
if python3 examples/os_mode_perf.py --output "$tmpdir/perf-existing-output.json" -- python3 -c 'print("unused")' >"$tmpdir/perf-existing-output.out" 2>"$tmpdir/perf-existing-output.err"; then
    echo "perf helper existing-output argument test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--output destination already exists" "$tmpdir/perf-existing-output.err"; then
    echo "perf helper existing-output argument test did not report existing destination" >&2
    cat "$tmpdir/perf-existing-output.err" >&2
    exit 1
fi
if python3 examples/os_mode_perf.py --output "$tmpdir/missing-perf-parent/perf.json" -- python3 -c 'print("unused")' >"$tmpdir/perf-missing-output-parent.out" 2>"$tmpdir/perf-missing-output-parent.err"; then
    echo "perf helper missing-output-parent argument test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--output parent directory does not exist" "$tmpdir/perf-missing-output-parent.err"; then
    echo "perf helper missing-output-parent argument test did not report missing parent" >&2
    cat "$tmpdir/perf-missing-output-parent.err" >&2
    exit 1
fi
if python3 examples/os_mode_perf.py --control-delay -1 -- python3 -c 'print("unused")' >"$tmpdir/perf-bad-control-delay.out" 2>"$tmpdir/perf-bad-control-delay.err"; then
    echo "perf helper negative-control-delay argument test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "value must be non-negative" "$tmpdir/perf-bad-control-delay.err"; then
    echo "perf helper negative-control-delay argument test did not report invalid control delay" >&2
    cat "$tmpdir/perf-bad-control-delay.err" >&2
    exit 1
fi
if python3 examples/os_mode_perf.py -- >"$tmpdir/perf-missing-command.out" 2>"$tmpdir/perf-missing-command.err"; then
    echo "perf helper missing-command argument test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "missing command after --" "$tmpdir/perf-missing-command.err"; then
    echo "perf helper missing-command argument test did not report missing command" >&2
    cat "$tmpdir/perf-missing-command.err" >&2
    exit 1
fi

echo "==> smoke helper marker self-test"
python3 examples/os_mode_smoke.py --timeout 2 --expect-root /dev/vda --expect-console ttyAMA0 --output "$tmpdir/smoke-ok.json" -- python3 -c 'print("KRUN_OSMODE: init-started"); print("KRUN_OSMODE: root=/dev/vda ext4 rw"); print("KRUN_OSMODE: pid1=init /sbin/init"); print("KRUN_OSMODE: console=ttyAMA0"); print("KRUN_OSMODE: ready")'
python3 - "$tmpdir/smoke-ok.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("ready") is not True:
    raise SystemExit("smoke JSON did not record ready=true")
if payload.get("missing_markers") != []:
    raise SystemExit(f"smoke JSON recorded missing markers: {payload.get('missing_markers')}")
if not isinstance(payload.get("elapsed_ms"), int) or payload["elapsed_ms"] < 0:
    raise SystemExit("smoke JSON did not record non-negative elapsed_ms")
if not isinstance(payload.get("launcher_pid"), int) or payload["launcher_pid"] <= 0:
    raise SystemExit("smoke JSON did not record launcher_pid")
if not isinstance(payload.get("process_pid"), int) or payload["process_pid"] <= 0:
    raise SystemExit("smoke JSON did not record process_pid")
if payload.get("process_parent_pid") != payload.get("launcher_pid"):
    raise SystemExit("smoke JSON did not record launcher as process parent")
if "KRUN_OSMODE: ready" not in payload.get("output_lines", []):
    raise SystemExit("smoke JSON did not record merged stdout/stderr output")
PY

echo "==> smoke helper prefixed marker self-test"
python3 examples/os_mode_smoke.py --timeout 2 --expect-root /dev/vda --expect-console ttyAMA0 --expect-pid1 systemd --output "$tmpdir/smoke-prefixed-ok.json" -- python3 -c 'print("[    0.000000] Booting Linux on physical CPU 0x0000000000"); print("[    0.485088] krun-osmode-ready[1257]: KRUN_OSMODE: init-started"); print("[    0.486788] krun-osmode-ready[1257]: KRUN_OSMODE: root=/dev/vda ext4 rw,relatime"); print("[    0.491096] krun-osmode-ready[1257]: KRUN_OSMODE: pid1=systemd /usr/lib/systemd/systemd"); print("[    0.491718] krun-osmode-ready[1257]: KRUN_OSMODE: console=ttyAMA0"); print("[    0.495583] krun-osmode-ready[1257]: KRUN_OSMODE: ready")'
python3 - "$tmpdir/smoke-prefixed-ok.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("ready") is not True:
    raise SystemExit("smoke prefixed JSON did not record ready=true")
for key in ("first_kernel_log_ms", "root_ms", "pid1_ms", "console_ms", "ready_ms"):
    if not isinstance(payload.get("timings", {}).get(key), int):
        raise SystemExit(f"smoke prefixed JSON missed timing {key}")
for marker in (
    "KRUN_OSMODE: init-started",
    "KRUN_OSMODE: root=",
    "KRUN_OSMODE: pid1=",
    "KRUN_OSMODE: console=",
    "KRUN_OSMODE: ready",
):
    if marker not in payload.get("markers_seen", []):
        raise SystemExit(f"smoke prefixed JSON missed marker {marker!r}")
PY

echo "==> smoke helper exit-wait self-test"
python3 examples/os_mode_smoke.py --timeout 2 --wait-exit-after-ready 1 --output "$tmpdir/smoke-exit-ok.json" -- python3 -c 'print("KRUN_OSMODE: init-started"); print("KRUN_OSMODE: root=/dev/vda ext4 rw"); print("KRUN_OSMODE: pid1=init /sbin/init"); print("KRUN_OSMODE: console=ttyAMA0"); print("KRUN_OSMODE: ready")'
python3 - "$tmpdir/smoke-exit-ok.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("ready") is not True:
    raise SystemExit("smoke exit-wait JSON did not record ready=true")
if payload.get("exit_code") != 0:
    raise SystemExit(f"smoke exit-wait JSON recorded unexpected exit code: {payload.get('exit_code')}")
if payload.get("wait_exit_after_ready_sec") != 1.0:
    raise SystemExit("smoke exit-wait JSON did not record wait timeout")
PY

echo "==> smoke helper exit-wait drain self-test"
python3 examples/os_mode_smoke.py --timeout 2 --wait-exit-after-ready 2 --output "$tmpdir/smoke-exit-drain-ok.json" -- python3 -c 'import sys; print("KRUN_OSMODE: init-started"); print("KRUN_OSMODE: root=/dev/vda ext4 rw"); print("KRUN_OSMODE: pid1=init /sbin/init"); print("KRUN_OSMODE: console=ttyAMA0"); print("KRUN_OSMODE: ready"); [print("shutdown-drain-line-%04d %s" % (i, "x" * 200)) for i in range(600)]; sys.stdout.flush()' >"$tmpdir/smoke-exit-drain-ok.out" 2>"$tmpdir/smoke-exit-drain-ok.err"
python3 - "$tmpdir/smoke-exit-drain-ok.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("ready") is not True:
    raise SystemExit("smoke exit-drain JSON did not record ready=true")
if payload.get("exit_code") != 0:
    raise SystemExit(f"smoke exit-drain JSON recorded unexpected exit code: {payload.get('exit_code')}")
if len(payload.get("output_lines", [])) < 600:
    raise SystemExit("smoke exit-drain JSON did not retain post-ready output")
PY

if python3 examples/os_mode_smoke.py --timeout 2 --wait-exit-after-ready 0.2 --output "$tmpdir/smoke-exit-timeout.json" -- python3 -c 'import time; print("KRUN_OSMODE: init-started", flush=True); print("KRUN_OSMODE: root=/dev/vda ext4 rw", flush=True); print("KRUN_OSMODE: pid1=init /sbin/init", flush=True); print("KRUN_OSMODE: console=ttyAMA0", flush=True); print("KRUN_OSMODE: ready", flush=True); time.sleep(10)' >"$tmpdir/smoke-exit-timeout.out" 2>"$tmpdir/smoke-exit-timeout.err"; then
    echo "smoke helper exit-timeout test unexpectedly succeeded" >&2
    cat "$tmpdir/smoke-exit-timeout.out" >&2
    exit 1
fi
python3 - "$tmpdir/smoke-exit-timeout.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("ready") is not False:
    raise SystemExit("smoke exit-timeout JSON did not record ready=false")
if payload.get("failure_reason") != "exit-timeout":
    raise SystemExit(f"smoke exit-timeout JSON recorded unexpected failure: {payload.get('failure_reason')}")
if "KRUN_OSMODE: ready" not in payload.get("output_lines", []):
    raise SystemExit("smoke exit-timeout JSON did not record ready marker")
PY

echo "==> smoke helper expected marker self-test"
python3 examples/os_mode_smoke.py --timeout 2 --expect-marker 'KRUN_OSMODE: network=up' --output "$tmpdir/smoke-extra-marker-ok.json" -- python3 -c 'print("KRUN_OSMODE: init-started"); print("KRUN_OSMODE: root=/dev/vda ext4 rw"); print("KRUN_OSMODE: pid1=init /sbin/init"); print("KRUN_OSMODE: console=ttyAMA0"); print("KRUN_OSMODE: network=up"); print("KRUN_OSMODE: ready")'
python3 - "$tmpdir/smoke-extra-marker-ok.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("ready") is not True:
    raise SystemExit("expected-marker smoke JSON did not record ready=true")
if payload.get("missing_markers") != []:
    raise SystemExit(f"expected-marker smoke JSON recorded missing markers: {payload.get('missing_markers')}")
if "KRUN_OSMODE: network=up" not in payload.get("expected_markers_seen", []):
    raise SystemExit("expected-marker smoke JSON did not record the expected marker")
if payload.get("observed_root") != "/dev/vda":
    raise SystemExit(f"expected-marker smoke JSON recorded unexpected observed_root: {payload.get('observed_root')}")
if payload.get("observed_root_line") != "/dev/vda ext4 rw":
    raise SystemExit(f"expected-marker smoke JSON recorded unexpected observed_root_line: {payload.get('observed_root_line')}")
if payload.get("observed_pid1") != "init":
    raise SystemExit(f"expected-marker smoke JSON recorded unexpected observed_pid1: {payload.get('observed_pid1')}")
if payload.get("observed_pid1_line") != "init /sbin/init":
    raise SystemExit(f"expected-marker smoke JSON recorded unexpected observed_pid1_line: {payload.get('observed_pid1_line')}")
if payload.get("observed_console") != "ttyAMA0":
    raise SystemExit(f"expected-marker smoke JSON recorded unexpected observed_console: {payload.get('observed_console')}")
if payload.get("observed_consoles") != ["ttyAMA0"]:
    raise SystemExit(f"expected-marker smoke JSON recorded unexpected observed_consoles: {payload.get('observed_consoles')}")
if payload.get("observed_network") != "up":
    raise SystemExit(f"expected-marker smoke JSON recorded unexpected observed_network: {payload.get('observed_network')}")
observed = payload.get("observed", {})
if observed.get("root") != "/dev/vda" or observed.get("pid1") != "init" or observed.get("console") != "ttyAMA0":
    raise SystemExit(f"expected-marker smoke JSON recorded unexpected observed map: {observed}")
PY

if python3 examples/os_mode_smoke.py --timeout 0.5 --expect-marker 'KRUN_OSMODE: network=up' --output "$tmpdir/smoke-extra-marker-bad.json" -- python3 -c 'print("KRUN_OSMODE: init-started"); print("KRUN_OSMODE: root=/dev/vda ext4 rw"); print("KRUN_OSMODE: pid1=init /sbin/init"); print("KRUN_OSMODE: console=ttyAMA0"); print("KRUN_OSMODE: ready")' >"$tmpdir/smoke-extra-marker-bad.out" 2>"$tmpdir/smoke-extra-marker-bad.err"; then
    echo "smoke helper expected-marker negative test unexpectedly succeeded" >&2
    cat "$tmpdir/smoke-extra-marker-bad.out" >&2
    exit 1
fi
python3 - "$tmpdir/smoke-extra-marker-bad.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("ready") is not False:
    raise SystemExit("missing expected-marker smoke JSON did not record ready=false")
if payload.get("failure_reason") != "missing-expected-markers":
    raise SystemExit(f"missing expected-marker smoke JSON recorded unexpected failure: {payload.get('failure_reason')}")
if "KRUN_OSMODE: network=up" not in payload.get("missing_markers", []):
    raise SystemExit("missing expected-marker smoke JSON did not record the missing marker")
PY

echo "==> smoke helper timeout self-test"
if python3 examples/os_mode_smoke.py --timeout 0.5 --output "$tmpdir/smoke-timeout.json" -- python3 -c 'import sys,time; sys.stdout.write("partial-without-newline"); sys.stdout.flush(); time.sleep(10)' >"$tmpdir/smoke-timeout.out" 2>"$tmpdir/smoke-timeout.err"; then
    echo "smoke helper timeout test unexpectedly succeeded" >&2
    cat "$tmpdir/smoke-timeout.out" >&2
    exit 1
fi
python3 - "$tmpdir/smoke-timeout.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("ready") is not False:
    raise SystemExit("timeout smoke JSON did not record ready=false")
if payload.get("failure_reason") != "missing-markers":
    raise SystemExit(f"timeout smoke JSON recorded unexpected failure: {payload.get('failure_reason')}")
if "KRUN_OSMODE: ready" not in payload.get("missing_markers", []):
    raise SystemExit("timeout smoke JSON did not record missing ready marker")
if payload.get("output_lines") != ["partial-without-newline"]:
    raise SystemExit(f"timeout smoke JSON did not record partial output: {payload.get('output_lines')}")
PY

echo "==> smoke helper root guard self-test"
if python3 examples/os_mode_smoke.py --timeout 2 --expect-root /dev/vda1 --output "$tmpdir/smoke-root-bad.json" -- python3 -c 'print("KRUN_OSMODE: init-started"); print("KRUN_OSMODE: root=/dev/vda10 ext4 rw"); print("KRUN_OSMODE: pid1=init /sbin/init"); print("KRUN_OSMODE: console=ttyAMA0"); print("KRUN_OSMODE: ready")' >"$tmpdir/smoke-root-bad.out" 2>"$tmpdir/smoke-root-bad.err"; then
    echo "smoke helper root guard test unexpectedly succeeded" >&2
    cat "$tmpdir/smoke-root-bad.out" >&2
    exit 1
fi
python3 - "$tmpdir/smoke-root-bad.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("ready") is not False:
    raise SystemExit("root guard JSON did not record ready=false")
if payload.get("failure_reason") != "root-mismatch":
    raise SystemExit(f"root guard JSON recorded unexpected failure: {payload.get('failure_reason')}")
if "KRUN_OSMODE: root=" not in payload.get("markers_seen", []):
    raise SystemExit("root guard JSON did not record the root marker")
PY

echo "==> smoke helper console guard self-test"
if python3 examples/os_mode_smoke.py --timeout 2 --expect-console ttyS0 --output "$tmpdir/smoke-console-bad.json" -- python3 -c 'print("KRUN_OSMODE: init-started"); print("KRUN_OSMODE: root=/dev/vda ext4 rw"); print("KRUN_OSMODE: pid1=init /sbin/init"); print("KRUN_OSMODE: console=ttyAMA0"); print("KRUN_OSMODE: ready")' >"$tmpdir/smoke-console-bad.out" 2>"$tmpdir/smoke-console-bad.err"; then
    echo "smoke helper console guard test unexpectedly succeeded" >&2
    cat "$tmpdir/smoke-console-bad.out" >&2
    exit 1
fi
python3 - "$tmpdir/smoke-console-bad.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("ready") is not False:
    raise SystemExit("console guard JSON did not record ready=false")
if payload.get("failure_reason") != "console-mismatch":
    raise SystemExit(f"console guard JSON recorded unexpected failure: {payload.get('failure_reason')}")
if "KRUN_OSMODE: console=" not in payload.get("markers_seen", []):
    raise SystemExit("console guard JSON did not record the console marker")
PY

echo "==> smoke helper pid1 guard self-test"
if python3 examples/os_mode_smoke.py --timeout 2 --output "$tmpdir/smoke-pid1-bad.json" -- python3 -c 'print("KRUN_OSMODE: init-started"); print("KRUN_OSMODE: root=/dev/vda ext4 rw"); print("KRUN_OSMODE: pid1=init.krun /init.krun"); print("KRUN_OSMODE: console=ttyAMA0"); print("KRUN_OSMODE: ready")' >"$tmpdir/smoke-pid1-bad.out" 2>"$tmpdir/smoke-pid1-bad.err"; then
    echo "smoke helper pid1 guard test unexpectedly succeeded" >&2
    cat "$tmpdir/smoke-pid1-bad.out" >&2
    exit 1
fi
python3 - "$tmpdir/smoke-pid1-bad.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("ready") is not False:
    raise SystemExit("pid1 guard JSON did not record ready=false")
if payload.get("failure_reason") != "pid1-init.krun":
    raise SystemExit(f"pid1 guard JSON recorded unexpected failure: {payload.get('failure_reason')}")
if "KRUN_OSMODE: pid1=" not in payload.get("markers_seen", []):
    raise SystemExit("pid1 guard JSON did not record the pid1 marker")
PY
if python3 examples/os_mode_smoke.py --timeout 2 --expect-pid1 systemd --output "$tmpdir/smoke-pid1-mismatch.json" -- python3 -c 'print("KRUN_OSMODE: init-started"); print("KRUN_OSMODE: root=/dev/vda ext4 rw"); print("KRUN_OSMODE: pid1=init /sbin/init"); print("KRUN_OSMODE: console=ttyAMA0"); print("KRUN_OSMODE: ready")' >"$tmpdir/smoke-pid1-mismatch.out" 2>"$tmpdir/smoke-pid1-mismatch.err"; then
    echo "smoke helper pid1 mismatch test unexpectedly succeeded" >&2
    cat "$tmpdir/smoke-pid1-mismatch.out" >&2
    exit 1
fi
python3 - "$tmpdir/smoke-pid1-mismatch.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("ready") is not False:
    raise SystemExit("pid1 mismatch JSON did not record ready=false")
if payload.get("failure_reason") != "pid1-mismatch":
    raise SystemExit(f"pid1 mismatch JSON recorded unexpected failure: {payload.get('failure_reason')}")
if payload.get("expected_pid1") != "systemd":
    raise SystemExit("pid1 mismatch JSON did not record expected_pid1")
PY

echo "==> perf helper control self-test"
python3 examples/os_mode_perf.py \
    --timeout 3 \
    --label perf-control-self-test \
    --output "$tmpdir/perf-control.json" \
    --control-delay 0 \
    --control-command 'echo control' \
    --expect-control-marker 'KRUN_OSMODE: control=ok' \
    -- python3 -c 'import sys; print("KRUN_OSMODE: ready", flush=True); sys.stdin.readline(); print("KRUN_OSMODE: control=ok", flush=True)'
python3 - "$tmpdir/perf-control.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
timings = payload.get("timings", {})
if "ready_ms" not in timings:
    raise SystemExit("perf JSON did not record ready_ms")
if "control_ms" not in timings:
    raise SystemExit("perf JSON did not record control_ms")
if "KRUN_OSMODE: control=ok" not in payload.get("markers_seen", []):
    raise SystemExit("perf JSON did not record control marker")
if "KRUN_OSMODE: ready" not in payload.get("output_lines", []):
    raise SystemExit("perf JSON did not record output lines")
PY

echo "==> perf helper partial-line self-test"
python3 examples/os_mode_perf.py \
    --timeout 2 \
    --label perf-partial-line-self-test \
    --output "$tmpdir/perf-partial-line.json" \
    -- python3 -c 'import sys; sys.stdout.write("KRUN_OSMODE: ready"); sys.stdout.flush()' >"$tmpdir/perf-partial-line.out" 2>"$tmpdir/perf-partial-line.err"
python3 - "$tmpdir/perf-partial-line.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
timings = payload.get("timings", {})
if "ready_ms" not in timings:
    raise SystemExit("partial-line perf JSON did not record ready_ms")
if payload.get("failure_reason") is not None:
    raise SystemExit(f"partial-line perf JSON recorded unexpected failure: {payload.get('failure_reason')}")
if payload.get("output_lines") != ["KRUN_OSMODE: ready"]:
    raise SystemExit(f"partial-line perf JSON did not record partial output: {payload.get('output_lines')}")
PY

echo "==> perf helper prefixed marker self-test"
python3 examples/os_mode_perf.py \
    --timeout 2 \
    --label perf-prefixed-self-test \
    --output "$tmpdir/perf-prefixed-ok.json" \
    --expect-root /dev/vda \
    --expect-console ttyAMA0 \
    --require-pid1-marker \
    -- python3 -c 'print("[    0.000000] Booting Linux on physical CPU 0x0000000000"); print("[    0.486788] krun-osmode-ready[1257]: KRUN_OSMODE: root=/dev/vda ext4 rw,relatime"); print("[    0.491096] krun-osmode-ready[1257]: KRUN_OSMODE: pid1=systemd /usr/lib/systemd/systemd"); print("[    0.491718] krun-osmode-ready[1257]: KRUN_OSMODE: console=ttyAMA0"); print("[    0.495583] krun-osmode-ready[1257]: KRUN_OSMODE: ready")'
python3 - "$tmpdir/perf-prefixed-ok.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("failure_reason") is not None:
    raise SystemExit(f"perf prefixed helper failed: {payload.get('failure_reason')}")
for key in ("first_kernel_log_ms", "root_ms", "pid1_ms", "console_ms", "ready_ms"):
    if not isinstance(payload.get("timings", {}).get(key), int):
        raise SystemExit(f"perf prefixed helper missed timing {key}")
if payload.get("observed_root") != "/dev/vda":
    raise SystemExit(f"perf prefixed helper recorded unexpected observed_root: {payload.get('observed_root')}")
if payload.get("observed_root_line") != "/dev/vda ext4 rw,relatime":
    raise SystemExit(f"perf prefixed helper recorded unexpected observed_root_line: {payload.get('observed_root_line')}")
if payload.get("observed_pid1") != "systemd":
    raise SystemExit(f"perf prefixed helper recorded unexpected observed_pid1: {payload.get('observed_pid1')}")
if payload.get("observed_pid1_line") != "systemd /usr/lib/systemd/systemd":
    raise SystemExit(f"perf prefixed helper recorded unexpected observed_pid1_line: {payload.get('observed_pid1_line')}")
if payload.get("observed_console") != "ttyAMA0":
    raise SystemExit(f"perf prefixed helper recorded unexpected observed_console: {payload.get('observed_console')}")
if payload.get("observed_consoles") != ["ttyAMA0"]:
    raise SystemExit(f"perf prefixed helper recorded unexpected observed_consoles: {payload.get('observed_consoles')}")
observed = payload.get("observed", {})
if observed.get("root") != "/dev/vda" or observed.get("pid1") != "systemd" or observed.get("console") != "ttyAMA0":
    raise SystemExit(f"perf prefixed helper recorded unexpected observed map: {observed}")
PY

python3 examples/os_mode_perf.py \
    --timeout 2 \
    --label perf-host-log-self-test \
    --output "$tmpdir/perf-host-log.json" \
    -- python3 -c 'print("[2026-05-18T17:10:53Z WARN krun_vmm::builder] host-side warning"); print("KRUN_OSMODE: ready")'
python3 - "$tmpdir/perf-host-log.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
timings = payload.get("timings", {})
if "first_kernel_log_ms" in timings:
    raise SystemExit("perf helper treated a host timestamped warning as a kernel log")
if "ready_ms" not in timings:
    raise SystemExit("perf host-log self-test did not record ready_ms")
PY

echo "==> perf helper OS invariant guard self-test"
if python3 examples/os_mode_perf.py \
    --timeout 2 \
    --label perf-root-guard-self-test \
    --output "$tmpdir/perf-root-bad.json" \
    --expect-root /dev/vda1 \
    -- python3 -c 'print("KRUN_OSMODE: root=/dev/vda10 ext4 rw"); print("KRUN_OSMODE: ready")' >"$tmpdir/perf-root-bad.out" 2>"$tmpdir/perf-root-bad.err"; then
    echo "perf helper root guard test unexpectedly succeeded" >&2
    cat "$tmpdir/perf-root-bad.out" >&2
    exit 1
fi
python3 - "$tmpdir/perf-root-bad.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("failure_reason") != "root-mismatch":
    raise SystemExit(f"perf root guard JSON recorded unexpected failure: {payload.get('failure_reason')}")
if payload.get("expected_root") != "/dev/vda1":
    raise SystemExit("perf root guard JSON did not record expected_root")
PY
if python3 examples/os_mode_perf.py \
    --timeout 2 \
    --label perf-missing-root-guard-self-test \
    --output "$tmpdir/perf-root-missing.json" \
    --expect-root /dev/vda \
    -- python3 -c 'print("KRUN_OSMODE: ready")' >"$tmpdir/perf-root-missing.out" 2>"$tmpdir/perf-root-missing.err"; then
    echo "perf helper missing-root guard test unexpectedly succeeded" >&2
    cat "$tmpdir/perf-root-missing.out" >&2
    exit 1
fi
python3 - "$tmpdir/perf-root-missing.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("failure_reason") != "missing-root-marker":
    raise SystemExit(f"perf missing-root JSON recorded unexpected failure: {payload.get('failure_reason')}")
PY
if python3 examples/os_mode_perf.py \
    --timeout 2 \
    --label perf-console-guard-self-test \
    --output "$tmpdir/perf-console-bad.json" \
    --expect-console ttyS0 \
    -- python3 -c 'print("KRUN_OSMODE: console=ttyAMA0"); print("KRUN_OSMODE: ready")' >"$tmpdir/perf-console-bad.out" 2>"$tmpdir/perf-console-bad.err"; then
    echo "perf helper console guard test unexpectedly succeeded" >&2
    cat "$tmpdir/perf-console-bad.out" >&2
    exit 1
fi
python3 - "$tmpdir/perf-console-bad.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("failure_reason") != "console-mismatch":
    raise SystemExit(f"perf console guard JSON recorded unexpected failure: {payload.get('failure_reason')}")
if payload.get("expected_console") != "ttyS0":
    raise SystemExit("perf console guard JSON did not record expected_console")
PY
if python3 examples/os_mode_perf.py \
    --timeout 2 \
    --label perf-missing-console-guard-self-test \
    --output "$tmpdir/perf-console-missing.json" \
    --expect-console ttyAMA0 \
    -- python3 -c 'print("KRUN_OSMODE: ready")' >"$tmpdir/perf-console-missing.out" 2>"$tmpdir/perf-console-missing.err"; then
    echo "perf helper missing-console guard test unexpectedly succeeded" >&2
    cat "$tmpdir/perf-console-missing.out" >&2
    exit 1
fi
python3 - "$tmpdir/perf-console-missing.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("failure_reason") != "missing-console-marker":
    raise SystemExit(f"perf missing-console JSON recorded unexpected failure: {payload.get('failure_reason')}")
PY
if python3 examples/os_mode_perf.py \
    --timeout 2 \
    --label perf-pid1-guard-self-test \
    --output "$tmpdir/perf-pid1-bad.json" \
    -- python3 -c 'print("KRUN_OSMODE: pid1=init.krun /init.krun"); print("KRUN_OSMODE: ready")' >"$tmpdir/perf-pid1-bad.out" 2>"$tmpdir/perf-pid1-bad.err"; then
    echo "perf helper pid1 guard test unexpectedly succeeded" >&2
    cat "$tmpdir/perf-pid1-bad.out" >&2
    exit 1
fi
python3 - "$tmpdir/perf-pid1-bad.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("failure_reason") != "pid1-init.krun":
    raise SystemExit(f"perf pid1 guard JSON recorded unexpected failure: {payload.get('failure_reason')}")
PY
if python3 examples/os_mode_perf.py \
    --timeout 2 \
    --label perf-missing-pid1-guard-self-test \
    --output "$tmpdir/perf-pid1-missing.json" \
    --require-pid1-marker \
    -- python3 -c 'print("KRUN_OSMODE: ready")' >"$tmpdir/perf-pid1-missing.out" 2>"$tmpdir/perf-pid1-missing.err"; then
    echo "perf helper missing-pid1 guard test unexpectedly succeeded" >&2
    cat "$tmpdir/perf-pid1-missing.out" >&2
    exit 1
fi
python3 - "$tmpdir/perf-pid1-missing.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("failure_reason") != "missing-pid1-marker":
    raise SystemExit(f"perf missing-pid1 JSON recorded unexpected failure: {payload.get('failure_reason')}")
if payload.get("require_pid1_marker") is not True:
    raise SystemExit("perf missing-pid1 JSON did not record require_pid1_marker=true")
PY

echo "==> perf helper timeout self-test"
if python3 examples/os_mode_perf.py \
    --timeout 0.5 \
    --label perf-timeout-self-test \
    --output "$tmpdir/perf-timeout.json" \
    --expect-control-marker 'KRUN_OSMODE: control=missing' \
    -- python3 -c 'import time; print("KRUN_OSMODE: ready", flush=True); time.sleep(10)' >"$tmpdir/perf-timeout.out" 2>"$tmpdir/perf-timeout.err"; then
    echo "perf helper timeout test unexpectedly succeeded" >&2
    cat "$tmpdir/perf-timeout.out" >&2
    exit 1
fi
python3 - "$tmpdir/perf-timeout.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
timings = payload.get("timings", {})
if "ready_ms" not in timings:
    raise SystemExit("timeout perf JSON did not record ready_ms")
if "control_ms" in timings:
    raise SystemExit("timeout perf JSON unexpectedly recorded control_ms")
if "KRUN_OSMODE: ready" not in payload.get("markers_seen", []):
    raise SystemExit("timeout perf JSON did not record ready marker")
if payload.get("failure_reason") != "missing-control-marker":
    raise SystemExit(f"timeout perf JSON recorded unexpected failure: {payload.get('failure_reason')}")
PY

echo "==> perf helper exit-wait self-test"
if python3 examples/os_mode_perf.py \
    --timeout 2 \
    --label perf-exit-wait-self-test \
    --output "$tmpdir/perf-exit-wait.json" \
    --wait-exit-after-ready 0.2 \
    -- python3 -c 'import time; print("KRUN_OSMODE: ready", flush=True); time.sleep(10)' >"$tmpdir/perf-exit-wait.out" 2>"$tmpdir/perf-exit-wait.err"; then
    echo "perf helper exit-wait test unexpectedly succeeded" >&2
    cat "$tmpdir/perf-exit-wait.out" >&2
    exit 1
fi
python3 - "$tmpdir/perf-exit-wait.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("failure_reason") != "exit-timeout":
    raise SystemExit(f"exit-wait perf JSON recorded unexpected failure: {payload.get('failure_reason')}")
if "ready_ms" not in payload.get("timings", {}):
    raise SystemExit("exit-wait perf JSON did not record ready_ms")
PY

echo "==> perf helper nonzero-exit self-test"
if python3 examples/os_mode_perf.py \
    --timeout 2 \
    --label perf-nonzero-exit-self-test \
    --output "$tmpdir/perf-nonzero-exit.json" \
    --wait-exit-after-ready 1 \
    -- python3 -c 'import sys; print("KRUN_OSMODE: ready", flush=True); sys.exit(7)' >"$tmpdir/perf-nonzero-exit.out" 2>"$tmpdir/perf-nonzero-exit.err"; then
    echo "perf helper nonzero-exit test unexpectedly succeeded" >&2
    cat "$tmpdir/perf-nonzero-exit.out" >&2
    exit 1
fi
python3 - "$tmpdir/perf-nonzero-exit.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
if payload.get("failure_reason") != "exit-nonzero":
    raise SystemExit(f"nonzero-exit perf JSON recorded unexpected failure: {payload.get('failure_reason')}")
if payload.get("exit_code") != 7:
    raise SystemExit(f"nonzero-exit perf JSON recorded unexpected exit code: {payload.get('exit_code')}")
if "ready_ms" not in payload.get("timings", {}):
    raise SystemExit("nonzero-exit perf JSON did not record ready_ms")
PY

echo "==> manifest checker self-test"
mkdir -p "$tmpdir/manifest"
printf rootfs > "$tmpdir/manifest/rootfs.tar"
dd if=/dev/zero of="$tmpdir/manifest/root.raw" bs=1048576 count=1 >/dev/null 2>&1
printf kernel > "$tmpdir/manifest/kernel.img"
printf initramfs > "$tmpdir/manifest/initramfs.img"
python3 - "$tmpdir/manifest" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

def sha(name):
    return hashlib.sha256((root / name).read_bytes()).hexdigest()

def size(name):
    return (root / name).stat().st_size

manifest = {
    "manifest_schema_version": 1,
    "created_at_utc": "2026-05-17T12:00:00Z",
    "builder": "examples/os_mode_build_container_rootfs.py",
    "builder_script_sha256": "d" * 64,
    "builder_image": "alpine:3.23",
    "builder_digest": "alpine:3.23@sha256:" + ("c" * 64),
    "build_host": {
        "system": "Darwin",
        "release": "25.4.0",
        "machine": "arm64",
        "python_version": "3.13.0",
    },
    "runtime": "docker",
    "runtime_version": "Docker version 27.0.0",
    "source_image": "example:latest",
    "source_digest": "example:latest@sha256:" + ("a" * 64),
    "platform": "linux/arm64",
    "init_mode": "inject-smoke",
    "require_dhcp_client": False,
    "network_smoke": False,
    "smoke_timeout_sec": 30,
    "smoke_poweroff_after_ready": True,
    "smoke_wait_exit_after_ready_sec": 60,
    "expected_markers": [],
    "systemd_default_masks": True,
    "systemd_masks": ["custom-ready.service"],
    "systemd_serial_control_shell": False,
    "systemd_effective_masks": [
        "systemd-logind.service",
        "apt-daily.timer",
        "apt-daily-upgrade.timer",
        "dpkg-db-backup.timer",
        "e2scrub_all.timer",
        "custom-ready.service",
    ],
    "rootfs_tar": "rootfs.tar",
    "rootfs_tar_sha256": sha("rootfs.tar"),
    "rootfs_tar_size_bytes": size("rootfs.tar"),
    "overlay_tar": None,
    "overlay_tar_sha256": None,
    "overlay_tar_size_bytes": None,
    "root_disk": "root.raw",
    "root_disk_sha256": sha("root.raw"),
    "root_disk_size_bytes": size("root.raw"),
    "root_disk_size_mb": 1,
    "root_device": "/dev/vda",
    "expected_root": "/dev/vda",
    "root_fstype": "ext4",
    "root_options": None,
    "disk_sync": "relaxed",
    "kernel": "kernel.img",
    "kernel_format": 2,
    "initramfs": "initramfs.img",
    "init": "/sbin/init",
    "timings_ms": {"export_rootfs": 1, "build_ext4": 2, "total": 3},
    "output_dir_apfs": {
        "checked": True,
        "device": "/dev/disk3s5",
        "filesystem": "apfs",
        "is_apfs": True,
        "mount_point": "/System/Volumes/Data",
    },
    "os_mode_command": [
        "examples/os_mode",
        "--kernel",
        "kernel.img",
        "--kernel-format",
        "2",
        "--initramfs",
        "initramfs.img",
        "--root-disk",
        "vm-root.raw",
        "--disk-sync",
        "relaxed",
        "--root-device",
        "/dev/vda",
        "--root-fstype",
        "ext4",
        "--guest-init",
        "/sbin/init",
        "--console",
        "ttyAMA0",
    ],
    "apfs_clone_command": [
        "examples/os_mode_apfs_clone.sh",
        "root.raw",
        "vm-root.raw",
    ],
}
(root / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
bad = dict(manifest)
del bad["source_digest"]
(root / "bad-manifest.json").write_text(json.dumps(bad, indent=2) + "\n")
bad_schema_version = dict(manifest)
bad_schema_version["manifest_schema_version"] = 2
(root / "bad-schema-version-manifest.json").write_text(json.dumps(bad_schema_version, indent=2) + "\n")
bad_schema_bool = dict(manifest)
bad_schema_bool["manifest_schema_version"] = True
(root / "bad-schema-bool-manifest.json").write_text(json.dumps(bad_schema_bool, indent=2) + "\n")
bad_created_at = dict(manifest)
bad_created_at["created_at_utc"] = "2026-05-17 12:00:00"
(root / "bad-created-at-manifest.json").write_text(json.dumps(bad_created_at, indent=2) + "\n")
bare_source_digest = dict(manifest)
bare_source_digest["source_digest"] = "b" * 64
(root / "bare-source-digest-manifest.json").write_text(json.dumps(bare_source_digest, indent=2) + "\n")
bad_source_digest_shape = dict(manifest)
bad_source_digest_shape["source_digest"] = "sha256:example"
(root / "bad-source-digest-shape-manifest.json").write_text(json.dumps(bad_source_digest_shape, indent=2) + "\n")
bad_builder_digest_shape = dict(manifest)
bad_builder_digest_shape["builder_digest"] = "sha256:example"
(root / "bad-builder-digest-shape-manifest.json").write_text(json.dumps(bad_builder_digest_shape, indent=2) + "\n")
bad_missing_builder_digest = dict(manifest)
del bad_missing_builder_digest["builder_digest"]
(root / "bad-missing-builder-digest-manifest.json").write_text(json.dumps(bad_missing_builder_digest, indent=2) + "\n")
bad_build_host = dict(manifest)
bad_build_host["build_host"] = {"system": "", "release": "25.4.0", "machine": "arm64", "python_version": "3.13.0"}
(root / "bad-build-host-manifest.json").write_text(json.dumps(bad_build_host, indent=2) + "\n")
bad_builder_script = dict(manifest)
bad_builder_script["builder_script_sha256"] = "sha256:example"
(root / "bad-builder-script-manifest.json").write_text(json.dumps(bad_builder_script, indent=2) + "\n")
bad_builder = dict(manifest)
bad_builder["builder"] = "other-builder.py"
(root / "bad-builder-manifest.json").write_text(json.dumps(bad_builder, indent=2) + "\n")
bad_runtime = dict(manifest)
bad_runtime["runtime"] = "containerd"
(root / "bad-runtime-manifest.json").write_text(json.dumps(bad_runtime, indent=2) + "\n")
bad_runtime_version = dict(manifest)
bad_runtime_version["runtime_version"] = ""
(root / "bad-runtime-version-manifest.json").write_text(json.dumps(bad_runtime_version, indent=2) + "\n")
bad_systemd_mask = dict(manifest)
bad_systemd_mask["systemd_masks"] = ["../escape.service"]
(root / "bad-systemd-mask-manifest.json").write_text(json.dumps(bad_systemd_mask, indent=2) + "\n")
bad_systemd_mask_type = dict(manifest)
bad_systemd_mask_type["systemd_default_masks"] = "yes"
(root / "bad-systemd-mask-type-manifest.json").write_text(json.dumps(bad_systemd_mask_type, indent=2) + "\n")
bad_missing_apfs = dict(manifest)
del bad_missing_apfs["output_dir_apfs"]
(root / "bad-missing-apfs-manifest.json").write_text(json.dumps(bad_missing_apfs, indent=2) + "\n")
bad_apfs_shape = dict(manifest)
bad_apfs_shape["output_dir_apfs"] = {"checked": "yes", "filesystem": "apfs", "is_apfs": True}
(root / "bad-apfs-shape-manifest.json").write_text(json.dumps(bad_apfs_shape, indent=2) + "\n")
bad_apfs_checked = dict(manifest)
bad_apfs_checked["output_dir_apfs"] = {"checked": True, "filesystem": "", "is_apfs": True, "device": "disk3s5", "mount_point": "/System/Volumes/Data"}
(root / "bad-apfs-checked-manifest.json").write_text(json.dumps(bad_apfs_checked, indent=2) + "\n")
bad_kernel = dict(manifest)
bad_kernel["kernel"] = "missing-kernel.img"
(root / "bad-kernel-manifest.json").write_text(json.dumps(bad_kernel, indent=2) + "\n")
bad_missing_kernel_field = dict(manifest)
del bad_missing_kernel_field["kernel"]
(root / "bad-missing-kernel-field-manifest.json").write_text(json.dumps(bad_missing_kernel_field, indent=2) + "\n")
bad_kernel_format = dict(manifest)
bad_kernel_format["kernel_format"] = 9
(root / "bad-kernel-format-manifest.json").write_text(json.dumps(bad_kernel_format, indent=2) + "\n")
bad_kernel_format_bool = dict(manifest)
bad_kernel_format_bool["kernel_format"] = True
(root / "bad-kernel-format-bool-manifest.json").write_text(json.dumps(bad_kernel_format_bool, indent=2) + "\n")
bad_command_kernel_format = dict(manifest)
bad_command_kernel_format["os_mode_command"] = list(manifest["os_mode_command"])
bad_command_kernel_format["os_mode_command"][4] = "0"
(root / "bad-command-kernel-format-manifest.json").write_text(json.dumps(bad_command_kernel_format, indent=2) + "\n")
bad_init_mode = dict(manifest)
bad_init_mode["init_mode"] = "unknown"
(root / "bad-init-mode-manifest.json").write_text(json.dumps(bad_init_mode, indent=2) + "\n")
bad_command = dict(manifest)
bad_command["os_mode_command"] = list(manifest["os_mode_command"])
bad_command["os_mode_command"][2] = "other-kernel.img"
(root / "bad-command-manifest.json").write_text(json.dumps(bad_command, indent=2) + "\n")
bad_launches_base = dict(manifest)
bad_launches_base["os_mode_command"] = list(manifest["os_mode_command"])
bad_launches_base["os_mode_command"][bad_launches_base["os_mode_command"].index("--root-disk") + 1] = "root.raw"
(root / "bad-launches-base-manifest.json").write_text(json.dumps(bad_launches_base, indent=2) + "\n")
bad_duplicate_option = dict(manifest)
bad_duplicate_option["os_mode_command"] = list(manifest["os_mode_command"]) + [
    "--root-disk",
    "other-root.raw",
]
(root / "bad-duplicate-option-manifest.json").write_text(json.dumps(bad_duplicate_option, indent=2) + "\n")
bad_missing_option_value = dict(manifest)
bad_missing_option_value["os_mode_command"] = list(manifest["os_mode_command"])
root_disk_index = bad_missing_option_value["os_mode_command"].index("--root-disk")
del bad_missing_option_value["os_mode_command"][root_disk_index + 1]
(root / "bad-missing-option-value-manifest.json").write_text(json.dumps(bad_missing_option_value, indent=2) + "\n")
bad_nonstring_command = dict(manifest)
bad_nonstring_command["os_mode_command"] = list(manifest["os_mode_command"]) + [7]
(root / "bad-nonstring-command-manifest.json").write_text(json.dumps(bad_nonstring_command, indent=2) + "\n")
bad_unknown_argument = dict(manifest)
bad_unknown_argument["os_mode_command"] = list(manifest["os_mode_command"]) + [
    "--unknown",
    "value",
]
(root / "bad-unknown-argument-manifest.json").write_text(json.dumps(bad_unknown_argument, indent=2) + "\n")
bad_os_mode_helper = dict(manifest)
bad_os_mode_helper["os_mode_command"] = list(manifest["os_mode_command"])
bad_os_mode_helper["os_mode_command"][0] = "other/os_mode"
(root / "bad-os-mode-helper-manifest.json").write_text(json.dumps(bad_os_mode_helper, indent=2) + "\n")
bad_console = dict(manifest)
bad_console["os_mode_command"] = list(manifest["os_mode_command"])
bad_console["os_mode_command"][-1] = "ttyS0"
(root / "bad-console-manifest.json").write_text(json.dumps(bad_console, indent=2) + "\n")
bad_systemd = dict(manifest)
bad_systemd["init_mode"] = "systemd"
bad_systemd["os_mode_command"] = list(manifest["os_mode_command"])
(root / "bad-systemd-manifest.json").write_text(json.dumps(bad_systemd, indent=2) + "\n")
systemd = dict(manifest)
systemd["init_mode"] = "systemd"
systemd["os_mode_command"] = list(manifest["os_mode_command"]) + [
    "--kernel-cmdline",
    "rw systemd.unit=multi-user.target",
]
(root / "systemd-manifest.json").write_text(json.dumps(systemd, indent=2) + "\n")
network_smoke = dict(manifest)
network_smoke["require_dhcp_client"] = True
network_smoke["network_smoke"] = True
network_smoke["smoke_timeout_sec"] = 45
network_smoke["smoke_wait_exit_after_ready_sec"] = 60
network_smoke["expected_markers"] = ["KRUN_OSMODE: network=up"]
network_smoke["os_mode_command"] = list(manifest["os_mode_command"]) + [
    "--kernel-cmdline",
    "KRUN_OSMODE_NET=1",
]
(root / "network-smoke-manifest.json").write_text(json.dumps(network_smoke, indent=2) + "\n")
bad_network_smoke_marker = dict(network_smoke)
bad_network_smoke_marker["expected_markers"] = []
(root / "bad-network-smoke-marker-manifest.json").write_text(json.dumps(bad_network_smoke_marker, indent=2) + "\n")
bad_network_smoke_cmdline = dict(network_smoke)
bad_network_smoke_cmdline["os_mode_command"] = list(manifest["os_mode_command"])
(root / "bad-network-smoke-cmdline-manifest.json").write_text(json.dumps(bad_network_smoke_cmdline, indent=2) + "\n")
bad_expected_markers_type = dict(manifest)
bad_expected_markers_type["expected_markers"] = ["KRUN_OSMODE: network=up", ""]
(root / "bad-expected-markers-type-manifest.json").write_text(json.dumps(bad_expected_markers_type, indent=2) + "\n")
bad_smoke_timeout = dict(manifest)
bad_smoke_timeout["smoke_timeout_sec"] = 0
(root / "bad-smoke-timeout-manifest.json").write_text(json.dumps(bad_smoke_timeout, indent=2) + "\n")
bad_smoke_poweroff_type = dict(manifest)
bad_smoke_poweroff_type["smoke_poweroff_after_ready"] = "yes"
(root / "bad-smoke-poweroff-type-manifest.json").write_text(json.dumps(bad_smoke_poweroff_type, indent=2) + "\n")
bad_smoke_wait_exit = dict(manifest)
bad_smoke_wait_exit["smoke_wait_exit_after_ready_sec"] = 0
(root / "bad-smoke-wait-exit-manifest.json").write_text(json.dumps(bad_smoke_wait_exit, indent=2) + "\n")
bad_timing_total = dict(manifest)
bad_timing_total["timings_ms"] = {"export_rootfs": 2, "build_ext4": 2, "total": 3}
(root / "bad-timing-total-manifest.json").write_text(json.dumps(bad_timing_total, indent=2) + "\n")
bad_timing_bool = dict(manifest)
bad_timing_bool["timings_ms"] = {"export_rootfs": True, "build_ext4": 2, "total": 3}
(root / "bad-timing-bool-manifest.json").write_text(json.dumps(bad_timing_bool, indent=2) + "\n")
no_smoke_poweroff = dict(manifest)
no_smoke_poweroff["smoke_poweroff_after_ready"] = False
no_smoke_poweroff["smoke_wait_exit_after_ready_sec"] = None
(root / "no-smoke-poweroff-manifest.json").write_text(json.dumps(no_smoke_poweroff, indent=2) + "\n")
amd64 = dict(manifest)
amd64["platform"] = "linux/amd64"
amd64["os_mode_command"] = list(manifest["os_mode_command"])
amd64["os_mode_command"][-1] = "ttyS0"
(root / "amd64-manifest.json").write_text(json.dumps(amd64, indent=2) + "\n")
bad_platform = dict(manifest)
bad_platform["platform"] = "darwin/arm64"
(root / "bad-platform-manifest.json").write_text(json.dumps(bad_platform, indent=2) + "\n")
bad_root_device_token = dict(manifest)
bad_root_device_token["root_device"] = "/dev/vda quiet"
(root / "bad-root-device-token-manifest.json").write_text(json.dumps(bad_root_device_token, indent=2) + "\n")
bad_expected_root_token = dict(manifest)
bad_expected_root_token["expected_root"] = "/dev/vda quiet"
(root / "bad-expected-root-token-manifest.json").write_text(json.dumps(bad_expected_root_token, indent=2) + "\n")
partuuid_root = dict(manifest)
partuuid_root["root_device"] = "PARTUUID=abcd-01"
partuuid_root["os_mode_command"] = list(manifest["os_mode_command"])
partuuid_root["os_mode_command"][partuuid_root["os_mode_command"].index("--root-device") + 1] = "PARTUUID=abcd-01"
(root / "partuuid-root-manifest.json").write_text(json.dumps(partuuid_root, indent=2) + "\n")
bad_root_device_kind = dict(manifest)
bad_root_device_kind["root_device"] = "relative-root"
(root / "bad-root-device-kind-manifest.json").write_text(json.dumps(bad_root_device_kind, indent=2) + "\n")
bad_root_fstype_token = dict(manifest)
bad_root_fstype_token["root_fstype"] = "ext4 quiet"
(root / "bad-root-fstype-token-manifest.json").write_text(json.dumps(bad_root_fstype_token, indent=2) + "\n")
root_options = dict(manifest)
root_options["root_options"] = "rw,noatime"
root_options["os_mode_command"] = list(manifest["os_mode_command"])
guest_init_index = root_options["os_mode_command"].index("--guest-init")
root_options["os_mode_command"][guest_init_index:guest_init_index] = [
    "--root-options",
    "rw,noatime",
]
(root / "root-options-manifest.json").write_text(json.dumps(root_options, indent=2) + "\n")
bad_root_options_token = dict(root_options)
bad_root_options_token["root_options"] = "rw quiet"
(root / "bad-root-options-token-manifest.json").write_text(json.dumps(bad_root_options_token, indent=2) + "\n")
bad_root_options_command = dict(root_options)
bad_root_options_command["os_mode_command"] = list(root_options["os_mode_command"])
bad_root_options_command["os_mode_command"][
    bad_root_options_command["os_mode_command"].index("--root-options") + 1
] = "ro"
(root / "bad-root-options-command-manifest.json").write_text(json.dumps(bad_root_options_command, indent=2) + "\n")
bad_amd64_console = dict(amd64)
bad_amd64_console["os_mode_command"] = list(amd64["os_mode_command"])
bad_amd64_console["os_mode_command"][-1] = "ttyAMA0"
(root / "bad-amd64-console-manifest.json").write_text(json.dumps(bad_amd64_console, indent=2) + "\n")
bad_checksum = dict(manifest)
bad_checksum["root_disk_sha256"] = None
(root / "bad-checksum-manifest.json").write_text(json.dumps(bad_checksum, indent=2) + "\n")
bad_root_size = dict(manifest)
bad_root_size["root_disk_size_bytes"] = 1
(root / "bad-root-size-manifest.json").write_text(json.dumps(bad_root_size, indent=2) + "\n")
bad_root_size_mb = dict(manifest)
bad_root_size_mb["root_disk_size_mb"] = 2
(root / "bad-root-size-mb-manifest.json").write_text(json.dumps(bad_root_size_mb, indent=2) + "\n")
bad_rootfs_size = dict(manifest)
bad_rootfs_size["rootfs_tar_size_bytes"] = 1
(root / "bad-rootfs-size-manifest.json").write_text(json.dumps(bad_rootfs_size, indent=2) + "\n")
bad_overlay_checksum = dict(manifest)
bad_overlay_checksum["overlay_tar_sha256"] = sha("rootfs.tar")
(root / "bad-overlay-checksum-manifest.json").write_text(json.dumps(bad_overlay_checksum, indent=2) + "\n")
bad_overlay_size_when_null = dict(manifest)
bad_overlay_size_when_null["overlay_tar_size_bytes"] = 1
(root / "bad-overlay-size-null-manifest.json").write_text(json.dumps(bad_overlay_size_when_null, indent=2) + "\n")
bad_clone_dest = dict(manifest)
bad_clone_dest["apfs_clone_command"] = list(manifest["apfs_clone_command"])
bad_clone_dest["apfs_clone_command"][2] = None
(root / "bad-clone-dest-manifest.json").write_text(json.dumps(bad_clone_dest, indent=2) + "\n")
bad_clone_nonstring = dict(manifest)
bad_clone_nonstring["apfs_clone_command"] = list(manifest["apfs_clone_command"])
bad_clone_nonstring["apfs_clone_command"][1] = 7
(root / "bad-clone-nonstring-manifest.json").write_text(json.dumps(bad_clone_nonstring, indent=2) + "\n")
bad_clone_helper = dict(manifest)
bad_clone_helper["apfs_clone_command"] = list(manifest["apfs_clone_command"])
bad_clone_helper["apfs_clone_command"][0] = "other/clone.sh"
(root / "bad-clone-helper-manifest.json").write_text(json.dumps(bad_clone_helper, indent=2) + "\n")
bad_clone_dest_resolved = dict(manifest)
bad_clone_dest_resolved["apfs_clone_command"] = list(manifest["apfs_clone_command"])
bad_clone_dest_resolved["apfs_clone_command"][2] = "./root.raw"
bad_clone_dest_resolved["os_mode_command"] = list(manifest["os_mode_command"])
bad_clone_dest_resolved["os_mode_command"][
    bad_clone_dest_resolved["os_mode_command"].index("--root-disk") + 1
] = "./root.raw"
(root / "bad-clone-dest-resolved-manifest.json").write_text(json.dumps(bad_clone_dest_resolved, indent=2) + "\n")
bad_clone_dest_rootfs = dict(manifest)
bad_clone_dest_rootfs["apfs_clone_command"] = list(manifest["apfs_clone_command"])
bad_clone_dest_rootfs["apfs_clone_command"][2] = "rootfs.tar"
bad_clone_dest_rootfs["os_mode_command"] = list(manifest["os_mode_command"])
bad_clone_dest_rootfs["os_mode_command"][
    bad_clone_dest_rootfs["os_mode_command"].index("--root-disk") + 1
] = "rootfs.tar"
(root / "bad-clone-dest-rootfs-manifest.json").write_text(json.dumps(bad_clone_dest_rootfs, indent=2) + "\n")
overlay_path = root / "overlay.tar"
overlay_path.write_text("overlay", encoding="utf-8")
overlay_manifest = dict(manifest)
overlay_manifest["overlay_tar"] = "overlay.tar"
overlay_manifest["overlay_tar_sha256"] = sha("overlay.tar")
overlay_manifest["overlay_tar_size_bytes"] = size("overlay.tar")
(root / "overlay-manifest.json").write_text(json.dumps(overlay_manifest, indent=2) + "\n")
bad_clone_dest_overlay = dict(overlay_manifest)
bad_clone_dest_overlay["apfs_clone_command"] = list(overlay_manifest["apfs_clone_command"])
bad_clone_dest_overlay["apfs_clone_command"][2] = "overlay.tar"
bad_clone_dest_overlay["os_mode_command"] = list(overlay_manifest["os_mode_command"])
bad_clone_dest_overlay["os_mode_command"][
    bad_clone_dest_overlay["os_mode_command"].index("--root-disk") + 1
] = "overlay.tar"
(root / "bad-clone-dest-overlay-manifest.json").write_text(json.dumps(bad_clone_dest_overlay, indent=2) + "\n")
bad_clone_dest_manifest = dict(manifest)
bad_clone_dest_manifest["apfs_clone_command"] = list(manifest["apfs_clone_command"])
bad_clone_dest_manifest["apfs_clone_command"][2] = "bad-clone-dest-manifestfile-manifest.json"
bad_clone_dest_manifest["os_mode_command"] = list(manifest["os_mode_command"])
bad_clone_dest_manifest["os_mode_command"][
    bad_clone_dest_manifest["os_mode_command"].index("--root-disk") + 1
] = "bad-clone-dest-manifestfile-manifest.json"
(root / "bad-clone-dest-manifestfile-manifest.json").write_text(json.dumps(bad_clone_dest_manifest, indent=2) + "\n")
PY

examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/manifest.json"
examples/os_mode_manifest_check.py --require-apfs --check-kernel-paths "$tmpdir/manifest/manifest.json"
examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/systemd-manifest.json"
examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/amd64-manifest.json"
examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bare-source-digest-manifest.json"
examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/root-options-manifest.json"
examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/partuuid-root-manifest.json"
examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/network-smoke-manifest.json"
examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/no-smoke-poweroff-manifest.json"
examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/overlay-manifest.json"
echo "==> container bundle publisher self-test"
python3 examples/os_mode_publish_container_bundle.py \
    "$tmpdir/manifest/manifest.json" \
    --output-dir "$tmpdir/published-bundle" \
    --artifact-manifest-output "$tmpdir/published-bundle-artifact.json" \
    >"$tmpdir/publish-bundle.out"
if ! grep -q "bundle_dir: .*/published-bundle/libkrun-os-bundle" "$tmpdir/publish-bundle.out"; then
    echo "bundle publisher did not print the bundle directory" >&2
    cat "$tmpdir/publish-bundle.out" >&2
    exit 1
fi
if [ ! -f "$tmpdir/published-bundle/Containerfile" ]; then
    echo "bundle publisher did not write Containerfile" >&2
    exit 1
fi
if [ ! -f "$tmpdir/published-bundle-artifact.json" ]; then
    echo "bundle publisher did not write artifact manifest" >&2
    exit 1
fi
if [ ! -f "$tmpdir/published-bundle/libkrun-os-bundle/root.raw" ] ||
   [ ! -f "$tmpdir/published-bundle/libkrun-os-bundle/kernel" ] ||
   [ ! -f "$tmpdir/published-bundle/libkrun-os-bundle/initramfs" ] ||
   [ ! -f "$tmpdir/published-bundle/libkrun-os-bundle/manifest.json" ]; then
    echo "bundle publisher did not write expected bundle files" >&2
    find "$tmpdir/published-bundle" -maxdepth 3 -type f >&2
    exit 1
fi
python3 examples/os_mode_import_container_bundle.py \
    --bundle-dir "$tmpdir/published-bundle/libkrun-os-bundle" \
    --clone-dest vm-root.raw \
    --smoke-output smoke.json \
    >"$tmpdir/published-bundle-import.out"
if ! grep -q "smoke_command: .*/examples/os_mode_smoke.py --timeout 30 --wait-exit-after-ready 60 --output .*/smoke.json --expect-root /dev/vda --expect-console ttyAMA0 --expect-pid1 init -- .*/examples/os_mode" "$tmpdir/published-bundle-import.out"; then
    echo "published bundle importer output did not include guarded smoke command" >&2
    cat "$tmpdir/published-bundle-import.out" >&2
    exit 1
fi
python3 - "$tmpdir/published-bundle/libkrun-os-bundle/manifest.json" <<'PY'
import json
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
if manifest.get("kind") != "libkrun.os-bundle.v1":
    raise SystemExit("published bundle manifest has wrong kind")
if manifest.get("root_disk") != "root.raw":
    raise SystemExit("published bundle manifest does not point at immutable root.raw")
if manifest.get("root_disk_allocated_bytes") is None:
    raise SystemExit("published bundle manifest did not record root disk allocated size")
if manifest.get("require_apfs_clone") is not True:
    raise SystemExit("published bundle manifest does not require APFS clone launch")
if manifest.get("allow_full_copy_fallback") is not False:
    raise SystemExit("published bundle manifest allows full-copy fallback")
if manifest.get("expected_pid1") != "init":
    raise SystemExit(f"published bundle manifest recorded unexpected pid1: {manifest.get('expected_pid1')}")
PY
python3 - "$tmpdir/published-bundle-artifact.json" "$tmpdir/published-bundle/libkrun-os-bundle/manifest.json" <<'PY'
import json
import sys
from pathlib import Path

artifact = json.load(open(sys.argv[1], encoding="utf-8"))
bundle_manifest = json.load(open(sys.argv[2], encoding="utf-8"))
if artifact.get("kind") != "libkrun.os-bundle.artifact.v1":
    raise SystemExit("published artifact manifest has wrong kind")
if artifact.get("bundle_manifest", {}).get("root_disk_sha256") != bundle_manifest.get("root_disk_sha256"):
    raise SystemExit("published artifact manifest did not copy bundle root digest")
if artifact.get("bundle_manifest", {}).get("platform") != "linux/arm64":
    raise SystemExit("published artifact manifest did not record platform")
if artifact.get("archive") is not None:
    raise SystemExit("published artifact manifest recorded archive metadata when no archive was saved")
if artifact.get("commands", {}).get("run") is not None:
    raise SystemExit("published artifact manifest recorded a run command without an image tag or digest")
if not Path(artifact.get("bundle_manifest", {}).get("path", "")).is_absolute():
    raise SystemExit("published artifact manifest did not record an absolute manifest path")
PY
mkdir -p "$tmpdir/published-existing"
printf old > "$tmpdir/published-existing/old"
if python3 examples/os_mode_publish_container_bundle.py "$tmpdir/manifest/manifest.json" --output-dir "$tmpdir/published-existing" >"$tmpdir/publish-existing.out" 2>"$tmpdir/publish-existing.err"; then
    echo "bundle publisher existing-output negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--output-dir already contains files" "$tmpdir/publish-existing.err"; then
    echo "bundle publisher existing-output negative test did not report stale output" >&2
    cat "$tmpdir/publish-existing.err" >&2
    exit 1
fi
if python3 examples/os_mode_publish_container_bundle.py "$tmpdir/manifest/manifest.json" --output-dir "$tmpdir/published-bad-pid1" --expected-pid1 init.krun >"$tmpdir/publish-bad-pid1.out" 2>"$tmpdir/publish-bad-pid1.err"; then
    echo "bundle publisher bad pid1 negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--expected-pid1 must not be init.krun" "$tmpdir/publish-bad-pid1.err"; then
    echo "bundle publisher bad pid1 negative test did not reject init.krun" >&2
    cat "$tmpdir/publish-bad-pid1.err" >&2
    exit 1
fi
if python3 examples/os_mode_publish_container_bundle.py "$tmpdir/manifest/bad-launches-base-manifest.json" --output-dir "$tmpdir/published-launches-base" >"$tmpdir/publish-launches-base.out" 2>"$tmpdir/publish-launches-base.err"; then
    echo "bundle publisher launch-base negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "immutable base root.raw" "$tmpdir/publish-launches-base.err" &&
   ! grep -q "attaches immutable root_disk directly" "$tmpdir/publish-launches-base.err" &&
   ! grep -q "root disk must match apfs_clone_command destination" "$tmpdir/publish-launches-base.err"; then
    echo "bundle publisher launch-base negative test did not reject immutable root launch" >&2
    cat "$tmpdir/publish-launches-base.err" >&2
    exit 1
fi
if python3 examples/os_mode_publish_container_bundle.py "$tmpdir/manifest/manifest.json" --output-dir "$tmpdir/published-push-no-tag" --push >"$tmpdir/publish-push-no-tag.out" 2>"$tmpdir/publish-push-no-tag.err"; then
    echo "bundle publisher push without image tag test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--push requires --image-tag" "$tmpdir/publish-push-no-tag.err"; then
    echo "bundle publisher push without image tag test did not report invalid option combination" >&2
    cat "$tmpdir/publish-push-no-tag.err" >&2
    exit 1
fi
if python3 examples/os_mode_publish_container_bundle.py "$tmpdir/manifest/manifest.json" --output-dir "$tmpdir/published-digest-no-push" --digest-output "$tmpdir/digest.txt" >"$tmpdir/publish-digest-no-push.out" 2>"$tmpdir/publish-digest-no-push.err"; then
    echo "bundle publisher digest-output without push test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--digest-output requires --push" "$tmpdir/publish-digest-no-push.err"; then
    echo "bundle publisher digest-output without push test did not report invalid option combination" >&2
    cat "$tmpdir/publish-digest-no-push.err" >&2
    exit 1
fi
if python3 examples/os_mode_publish_container_bundle.py "$tmpdir/manifest/manifest.json" --output-dir "$tmpdir/published-archive-no-tag" --archive-output "$tmpdir/bundle-image.tar" >"$tmpdir/publish-archive-no-tag.out" 2>"$tmpdir/publish-archive-no-tag.err"; then
    echo "bundle publisher archive-output without image-tag test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--archive-output requires --image-tag" "$tmpdir/publish-archive-no-tag.err"; then
    echo "bundle publisher archive-output without image-tag test did not report invalid option combination" >&2
    cat "$tmpdir/publish-archive-no-tag.err" >&2
    exit 1
fi
if python3 examples/os_mode_publish_container_bundle.py "$tmpdir/manifest/manifest.json" --output-dir "$tmpdir/published-archive-sha-no-archive" --archive-sha256-output "$tmpdir/bundle-image.sha256" >"$tmpdir/publish-archive-sha-no-archive.out" 2>"$tmpdir/publish-archive-sha-no-archive.err"; then
    echo "bundle publisher archive-sha without archive-output test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--archive-sha256-output requires --archive-output" "$tmpdir/publish-archive-sha-no-archive.err"; then
    echo "bundle publisher archive-sha without archive-output test did not report invalid option combination" >&2
    cat "$tmpdir/publish-archive-sha-no-archive.err" >&2
    exit 1
fi
python3 - "$tmpdir" <<'PY'
import importlib.util
import json
import pathlib
import sys

repo = pathlib.Path.cwd()
sys.path.insert(0, str(repo / "examples"))
spec = importlib.util.spec_from_file_location(
    "os_mode_publish_container_bundle",
    repo / "examples" / "os_mode_publish_container_bundle.py",
)
publisher = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(publisher)

digest_path = pathlib.Path(sys.argv[1]) / "publisher-digest.txt"
publisher.write_digest_output(digest_path, "example.com/os/bundle@sha256:" + ("a" * 64))
if digest_path.read_text(encoding="utf-8").strip() != "example.com/os/bundle@sha256:" + ("a" * 64):
    raise SystemExit("publisher did not write digest output")
try:
    publisher.write_digest_output(digest_path, "example.com/os/bundle@sha256:" + ("b" * 64))
except publisher.PublishError as exc:
    if "destination already exists" not in str(exc):
        raise SystemExit(f"publisher digest output reported unexpected error: {exc}")
else:
    raise SystemExit("publisher overwrote an existing digest output file")

archive_path = pathlib.Path(sys.argv[1]) / "publisher-archive.tar"
commands = []
old_run = publisher.run
try:
    def fake_run(command):
        commands.append(command)
        if command[:2] == ["docker", "save"]:
            pathlib.Path(command[command.index("-o") + 1]).write_bytes(b"archive")
    publisher.run = fake_run
    saved_archive = publisher.save_image_archive("docker", "example.com/os/bundle:test", archive_path)
finally:
    publisher.run = old_run
if saved_archive != archive_path.resolve():
    raise SystemExit("publisher save_image_archive returned an unexpected archive path")
if commands != [["docker", "save", "-o", str(archive_path.resolve()), "example.com/os/bundle:test"]]:
    raise SystemExit(f"publisher save_image_archive used unexpected command: {commands}")
if publisher.sha256_file(saved_archive) != "0eb3e36bfb24dcd9bb1d1bece1531216b59539a8fde17ee80224af0653c92aa3":
    raise SystemExit("publisher save_image_archive wrote unexpected archive content")
sha_path = pathlib.Path(sys.argv[1]) / "publisher-archive.sha256"
publisher.write_text_output(sha_path, publisher.sha256_file(saved_archive) + "\n", "--archive-sha256-output")
if sha_path.read_text(encoding="utf-8").strip() != publisher.sha256_file(saved_archive):
    raise SystemExit("publisher did not write archive SHA-256 output")
try:
    publisher.save_image_archive("docker", "example.com/os/bundle:test", archive_path)
except publisher.PublishError as exc:
    if "--archive-output destination already exists" not in str(exc):
        raise SystemExit(f"publisher archive existing-output reported unexpected error: {exc}")
else:
    raise SystemExit("publisher overwrote an existing archive output")

bundle_dir = pathlib.Path(sys.argv[1]) / "publisher-artifact-bundle"
bundle_dir.mkdir()
(bundle_dir / "manifest.json").write_text(
    json.dumps({
        "kind": "libkrun.os-bundle.v1",
        "platform": "linux/arm64",
        "expected_root": "/dev/vda",
        "console": "ttyAMA0",
        "expected_pid1": "systemd",
        "root_disk_sha256": "1" * 64,
        "kernel_sha256": "2" * 64,
        "initramfs_sha256": "3" * 64,
    }) + "\n",
    encoding="utf-8",
)
artifact = publisher.build_artifact_manifest(
    image_tag="example.com/os/bundle:test",
    digest_ref="example.com/os/bundle@sha256:" + ("c" * 64),
    runtime="docker",
    output_dir=pathlib.Path(sys.argv[1]) / "publisher-context",
    bundle_dir=bundle_dir,
    bundle_manifest=json.loads((bundle_dir / "manifest.json").read_text(encoding="utf-8")),
    archive_path=archive_path,
    archive_sha256=publisher.sha256_file(archive_path),
)
if artifact.get("archive", {}).get("sha256") != publisher.sha256_file(archive_path):
    raise SystemExit("publisher artifact manifest did not record archive sha256")
if artifact.get("archive", {}).get("load_command") != ["docker", "load", "-i", str(archive_path)]:
    raise SystemExit("publisher artifact manifest did not record archive load command")
if artifact.get("commands", {}).get("run") != ["examples/krun_os_run.py", "example.com/os/bundle@sha256:" + ("c" * 64)]:
    raise SystemExit("publisher artifact manifest did not prefer digest ref for run command")
if artifact.get("commands", {}).get("clean_host_preflight") != [
    "examples/os_mode_clean_host_preflight.py",
    "example.com/os/bundle@sha256:" + ("c" * 64),
    "--output-dir",
    "RELEASE_EVIDENCE_DIR",
    "--json-output",
    "CLEAN_HOST_PREFLIGHT_JSON",
]:
    raise SystemExit("publisher artifact manifest did not record clean-host preflight command")
if artifact.get("commands", {}).get("clean_host_preflight_from_artifact") != [
    "examples/os_mode_clean_host_preflight.py",
    "--artifact-manifest",
    "ARTIFACT_MANIFEST",
    "--output-dir",
    "RELEASE_EVIDENCE_DIR",
    "--json-output",
    "CLEAN_HOST_PREFLIGHT_JSON",
]:
    raise SystemExit("publisher artifact manifest did not record archive clean-host preflight command")
if artifact.get("commands", {}).get("clean_host_baseline") != [
    "examples/os_mode_clean_host_baseline.py",
    "example.com/os/bundle@sha256:" + ("c" * 64),
    "--output-dir",
    "RELEASE_EVIDENCE_DIR",
    "--preflight-json",
    "CLEAN_HOST_PREFLIGHT_JSON",
    "--accept-json-output",
    "ACCEPTANCE_JSON",
    "--accept-table-output",
    "ACCEPTED_BASELINE_MD",
    "--design-doc-output",
    "DESIGN_DOC_SNIPPET_MD",
    "--evidence-label",
    "RELEASE_EVIDENCE_LABEL",
    "--final-release-baseline",
]:
    raise SystemExit("publisher artifact manifest did not record clean-host baseline command")
if artifact.get("commands", {}).get("clean_host_baseline_from_artifact") != [
    "examples/os_mode_clean_host_baseline.py",
    "--artifact-manifest",
    "ARTIFACT_MANIFEST",
    "--output-dir",
    "RELEASE_EVIDENCE_DIR",
    "--preflight-json",
    "CLEAN_HOST_PREFLIGHT_JSON",
    "--accept-json-output",
    "ACCEPTANCE_JSON",
    "--accept-table-output",
    "ACCEPTED_BASELINE_MD",
    "--design-doc-output",
    "DESIGN_DOC_SNIPPET_MD",
    "--evidence-label",
    "RELEASE_EVIDENCE_LABEL",
    "--final-release-baseline",
]:
    raise SystemExit("publisher artifact manifest did not record archive clean-host baseline command")
if artifact.get("commands", {}).get("release_gate") != [
    "examples/os_mode_release_gate.py",
    "example.com/os/bundle@sha256:" + ("c" * 64),
    "--output-dir",
    "RELEASE_EVIDENCE_DIR",
    "--preflight-json",
    "CLEAN_HOST_PREFLIGHT_JSON",
    "--clean-host-baseline",
]:
    raise SystemExit("publisher artifact manifest did not record release gate command")
if artifact.get("commands", {}).get("release_gate_from_artifact") != [
    "examples/os_mode_release_gate.py",
    "--artifact-manifest",
    "ARTIFACT_MANIFEST",
    "--output-dir",
    "RELEASE_EVIDENCE_DIR",
    "--preflight-json",
    "CLEAN_HOST_PREFLIGHT_JSON",
    "--clean-host-baseline",
]:
    raise SystemExit("publisher artifact manifest did not record archive release gate command")
artifact_path = pathlib.Path(sys.argv[1]) / "publisher-artifact.json"
publisher.write_artifact_manifest(artifact_path, artifact)
if json.loads(artifact_path.read_text(encoding="utf-8")).get("kind") != "libkrun.os-bundle.artifact.v1":
    raise SystemExit("publisher did not write artifact manifest JSON")
PY
examples/os_mode_manifest_check.py --require-apfs --print-commands "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands.out"
if ! grep -q "apfs_clone_command: .*/examples/os_mode_apfs_clone.sh .*/root.raw .*/vm-root.raw" "$tmpdir/manifest-print-commands.out"; then
    echo "manifest checker print-commands output did not include APFS clone command" >&2
    cat "$tmpdir/manifest-print-commands.out" >&2
    exit 1
fi
if ! grep -q "os_mode_command: .*/examples/os_mode --kernel .*/kernel.img" "$tmpdir/manifest-print-commands.out" ||
   ! grep -q -- "--initramfs .*/initramfs.img" "$tmpdir/manifest-print-commands.out" ||
   ! grep -q -- "--root-disk .*/vm-root.raw" "$tmpdir/manifest-print-commands.out"; then
    echo "manifest checker print-commands output did not include resolved clone-backed os_mode command" >&2
    cat "$tmpdir/manifest-print-commands.out" >&2
    exit 1
fi
if ! grep -q "smoke_command: .*/examples/os_mode_smoke.py --timeout 30 --wait-exit-after-ready 60 --expect-root /dev/vda --expect-console ttyAMA0 -- .*/examples/os_mode --kernel .*/kernel.img" "$tmpdir/manifest-print-commands.out" ||
   ! grep -q -- "--poweroff-after-ready" "$tmpdir/manifest-print-commands.out"; then
    echo "manifest checker print-commands output did not include resolved smoke command" >&2
    cat "$tmpdir/manifest-print-commands.out" >&2
    exit 1
fi
examples/os_mode_manifest_check.py --require-apfs --print-commands "$tmpdir/manifest/no-smoke-poweroff-manifest.json" >"$tmpdir/manifest-print-commands-no-poweroff.out"
if grep -q -- "--poweroff-after-ready" "$tmpdir/manifest-print-commands-no-poweroff.out"; then
    echo "manifest checker printed poweroff flag despite smoke_poweroff_after_ready=false" >&2
    cat "$tmpdir/manifest-print-commands-no-poweroff.out" >&2
    exit 1
fi
examples/os_mode_manifest_check.py --require-apfs --print-commands "$tmpdir/manifest/network-smoke-manifest.json" >"$tmpdir/manifest-print-commands-network.out"
if ! grep -q "smoke_command: .*/examples/os_mode_smoke.py --timeout 45 --wait-exit-after-ready 60 --expect-root /dev/vda --expect-console ttyAMA0 --expect-marker 'KRUN_OSMODE: network=up' -- .*/examples/os_mode" "$tmpdir/manifest-print-commands-network.out"; then
    echo "manifest checker print-commands output did not include network expected-marker smoke command" >&2
    cat "$tmpdir/manifest-print-commands-network.out" >&2
    exit 1
fi
if ! grep -q -- "--kernel-cmdline KRUN_OSMODE_NET=1" "$tmpdir/manifest-print-commands-network.out"; then
    echo "manifest checker print-commands output did not include network kernel command line" >&2
    cat "$tmpdir/manifest-print-commands-network.out" >&2
    exit 1
fi
examples/os_mode_manifest_check.py --require-apfs --print-commands --smoke-output smoke.json "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-smoke-output.out"
if ! grep -q "smoke_command: .*/examples/os_mode_smoke.py --timeout 30 --wait-exit-after-ready 60 --output .*/smoke.json --expect-root /dev/vda --expect-console ttyAMA0 -- .*/examples/os_mode" "$tmpdir/manifest-print-commands-smoke-output.out"; then
    echo "manifest checker smoke-output command did not include JSON output path" >&2
    cat "$tmpdir/manifest-print-commands-smoke-output.out" >&2
    exit 1
fi
examples/os_mode_manifest_check.py --require-apfs --print-commands --perf-output perf.json "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-perf-output.out"
if ! grep -q "perf_command: .*/examples/os_mode_perf.py --timeout 30 --output .*/perf.json --require-pid1-marker --expect-root /dev/vda --expect-console ttyAMA0 -- .*/examples/os_mode --kernel .*/kernel.img" "$tmpdir/manifest-print-commands-perf-output.out"; then
    echo "manifest checker perf-output command did not include timing output path and OS invariants" >&2
    cat "$tmpdir/manifest-print-commands-perf-output.out" >&2
    exit 1
fi
if grep -q -- "perf_command: .*--poweroff-after-ready" "$tmpdir/manifest-print-commands-perf-output.out"; then
    echo "manifest checker perf command unexpectedly included smoke-only poweroff flag" >&2
    cat "$tmpdir/manifest-print-commands-perf-output.out" >&2
    exit 1
fi
printf old-perf > "$tmpdir/manifest/existing-perf.json"
if examples/os_mode_manifest_check.py --require-apfs --print-commands --perf-output existing-perf.json "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-perf-output-exists.out" 2>"$tmpdir/manifest-print-commands-perf-output-exists.err"; then
    echo "manifest checker existing perf-output negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--perf-output destination already exists" "$tmpdir/manifest-print-commands-perf-output-exists.err"; then
    echo "manifest checker existing perf-output negative test did not report existing destination" >&2
    cat "$tmpdir/manifest-print-commands-perf-output-exists.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --perf-output root.raw "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-perf-output-root.out" 2>"$tmpdir/manifest-print-commands-perf-output-root.err"; then
    echo "manifest checker root-disk perf-output negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--perf-output must differ from root_disk" "$tmpdir/manifest-print-commands-perf-output-root.err"; then
    echo "manifest checker root-disk perf-output negative test did not report protected root disk" >&2
    cat "$tmpdir/manifest-print-commands-perf-output-root.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --perf-output vm-root.raw "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-perf-output-clone.out" 2>"$tmpdir/manifest-print-commands-perf-output-clone.err"; then
    echo "manifest checker clone-destination perf-output negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--perf-output must differ from clone_destination" "$tmpdir/manifest-print-commands-perf-output-clone.err"; then
    echo "manifest checker clone-destination perf-output negative test did not report protected clone destination" >&2
    cat "$tmpdir/manifest-print-commands-perf-output-clone.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --perf-output missing-dir/perf.json "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-perf-output-missing-parent.out" 2>"$tmpdir/manifest-print-commands-perf-output-missing-parent.err"; then
    echo "manifest checker missing-parent perf-output negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--perf-output parent directory does not exist" "$tmpdir/manifest-print-commands-perf-output-missing-parent.err"; then
    echo "manifest checker missing-parent perf-output negative test did not report missing parent" >&2
    cat "$tmpdir/manifest-print-commands-perf-output-missing-parent.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --smoke-output same-evidence.json --perf-output same-evidence.json "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-perf-smoke-collision.out" 2>"$tmpdir/manifest-print-commands-perf-smoke-collision.err"; then
    echo "manifest checker perf/smoke-output collision negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--perf-output must differ from --smoke-output" "$tmpdir/manifest-print-commands-perf-smoke-collision.err"; then
    echo "manifest checker perf/smoke-output collision test did not report output collision" >&2
    cat "$tmpdir/manifest-print-commands-perf-smoke-collision.err" >&2
    exit 1
fi
printf old-smoke > "$tmpdir/manifest/existing-smoke.json"
if examples/os_mode_manifest_check.py --require-apfs --print-commands --smoke-output existing-smoke.json "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-smoke-output-exists.out" 2>"$tmpdir/manifest-print-commands-smoke-output-exists.err"; then
    echo "manifest checker existing smoke-output negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--smoke-output destination already exists" "$tmpdir/manifest-print-commands-smoke-output-exists.err"; then
    echo "manifest checker existing smoke-output negative test did not report existing destination" >&2
    cat "$tmpdir/manifest-print-commands-smoke-output-exists.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --smoke-output root.raw "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-smoke-output-root.out" 2>"$tmpdir/manifest-print-commands-smoke-output-root.err"; then
    echo "manifest checker root-disk smoke-output negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--smoke-output must differ from root_disk" "$tmpdir/manifest-print-commands-smoke-output-root.err"; then
    echo "manifest checker root-disk smoke-output negative test did not report protected root disk" >&2
    cat "$tmpdir/manifest-print-commands-smoke-output-root.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --smoke-output vm-root.raw "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-smoke-output-clone.out" 2>"$tmpdir/manifest-print-commands-smoke-output-clone.err"; then
    echo "manifest checker clone-destination smoke-output negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--smoke-output must differ from clone_destination" "$tmpdir/manifest-print-commands-smoke-output-clone.err"; then
    echo "manifest checker clone-destination smoke-output negative test did not report protected clone destination" >&2
    cat "$tmpdir/manifest-print-commands-smoke-output-clone.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --smoke-output missing-dir/smoke.json "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-smoke-output-missing-parent.out" 2>"$tmpdir/manifest-print-commands-smoke-output-missing-parent.err"; then
    echo "manifest checker missing-parent smoke-output negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--smoke-output parent directory does not exist" "$tmpdir/manifest-print-commands-smoke-output-missing-parent.err"; then
    echo "manifest checker missing-parent smoke-output negative test did not report missing parent" >&2
    cat "$tmpdir/manifest-print-commands-smoke-output-missing-parent.err" >&2
    exit 1
fi
examples/os_mode_manifest_check.py --require-apfs --print-commands --smoke-output smoke.json --write-runbook replay.sh "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-runbook.out"
if ! grep -q "runbook: .*/replay.sh" "$tmpdir/manifest-print-commands-runbook.out"; then
    echo "manifest checker runbook output did not report written script" >&2
    cat "$tmpdir/manifest-print-commands-runbook.out" >&2
    exit 1
fi
if [ ! -x "$tmpdir/manifest/replay.sh" ]; then
    echo "manifest checker did not write an executable runbook" >&2
    exit 1
fi
sh -n "$tmpdir/manifest/replay.sh"
if ! grep -q ".*/examples/os_mode_apfs_clone.sh .*/root.raw .*/vm-root.raw" "$tmpdir/manifest/replay.sh"; then
    echo "manifest checker runbook did not include APFS clone command" >&2
    cat "$tmpdir/manifest/replay.sh" >&2
    exit 1
fi
if ! grep -q ".*/examples/os_mode_smoke.py --timeout 30 --wait-exit-after-ready 60 --output .*/smoke.json --expect-root /dev/vda --expect-console ttyAMA0 -- .*/examples/os_mode" "$tmpdir/manifest/replay.sh"; then
    echo "manifest checker runbook did not include smoke command" >&2
    cat "$tmpdir/manifest/replay.sh" >&2
    exit 1
fi
examples/os_mode_manifest_check.py --require-apfs --print-commands --smoke-output smoke-with-perf.json --perf-output perf-with-runbook.json --write-runbook replay-with-perf.sh "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-runbook-perf.out"
if ! grep -q "runbook: .*/replay-with-perf.sh" "$tmpdir/manifest-print-commands-runbook-perf.out"; then
    echo "manifest checker perf runbook output did not report written script" >&2
    cat "$tmpdir/manifest-print-commands-runbook-perf.out" >&2
    exit 1
fi
if [ ! -x "$tmpdir/manifest/replay-with-perf.sh" ]; then
    echo "manifest checker did not write an executable perf runbook" >&2
    exit 1
fi
sh -n "$tmpdir/manifest/replay-with-perf.sh"
if ! grep -q ".*/examples/os_mode_perf.py --timeout 30 --output .*/perf-with-runbook.json --require-pid1-marker --expect-root /dev/vda --expect-console ttyAMA0 -- .*/examples/os_mode" "$tmpdir/manifest/replay-with-perf.sh"; then
    echo "manifest checker perf runbook did not include perf command" >&2
    cat "$tmpdir/manifest/replay-with-perf.sh" >&2
    exit 1
fi
if grep -q "os_mode_perf.py .*--poweroff-after-ready" "$tmpdir/manifest/replay-with-perf.sh"; then
    echo "manifest checker perf runbook included smoke-only poweroff flag in perf command" >&2
    cat "$tmpdir/manifest/replay-with-perf.sh" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --write-runbook replay.sh "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-runbook-exists.out" 2>"$tmpdir/manifest-print-commands-runbook-exists.err"; then
    echo "manifest checker existing runbook negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--write-runbook destination already exists" "$tmpdir/manifest-print-commands-runbook-exists.err"; then
    echo "manifest checker existing runbook negative test did not report existing destination" >&2
    cat "$tmpdir/manifest-print-commands-runbook-exists.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --write-runbook root.raw "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-runbook-root.out" 2>"$tmpdir/manifest-print-commands-runbook-root.err"; then
    echo "manifest checker root-disk runbook negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--write-runbook must differ from root_disk" "$tmpdir/manifest-print-commands-runbook-root.err"; then
    echo "manifest checker root-disk runbook negative test did not report protected root disk" >&2
    cat "$tmpdir/manifest-print-commands-runbook-root.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --write-runbook vm-root.raw "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-runbook-clone.out" 2>"$tmpdir/manifest-print-commands-runbook-clone.err"; then
    echo "manifest checker clone-destination runbook negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--write-runbook must differ from clone_destination" "$tmpdir/manifest-print-commands-runbook-clone.err"; then
    echo "manifest checker clone-destination runbook negative test did not report protected clone destination" >&2
    cat "$tmpdir/manifest-print-commands-runbook-clone.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --smoke-output same-path --write-runbook same-path "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-runbook-smoke-output.out" 2>"$tmpdir/manifest-print-commands-runbook-smoke-output.err"; then
    echo "manifest checker runbook/smoke-output collision negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--write-runbook must differ from --smoke-output" "$tmpdir/manifest-print-commands-runbook-smoke-output.err"; then
    echo "manifest checker runbook/smoke-output collision test did not report output collision" >&2
    cat "$tmpdir/manifest-print-commands-runbook-smoke-output.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --perf-output same-path --write-runbook same-path "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-runbook-perf-output.out" 2>"$tmpdir/manifest-print-commands-runbook-perf-output.err"; then
    echo "manifest checker runbook/perf-output collision negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--write-runbook must differ from --perf-output" "$tmpdir/manifest-print-commands-runbook-perf-output.err"; then
    echo "manifest checker runbook/perf-output collision test did not report output collision" >&2
    cat "$tmpdir/manifest-print-commands-runbook-perf-output.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --write-runbook missing-dir/replay.sh "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-runbook-missing-parent.out" 2>"$tmpdir/manifest-print-commands-runbook-missing-parent.err"; then
    echo "manifest checker missing-parent runbook negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--write-runbook parent directory does not exist" "$tmpdir/manifest-print-commands-runbook-missing-parent.err"; then
    echo "manifest checker missing-parent runbook negative test did not report missing parent" >&2
    cat "$tmpdir/manifest-print-commands-runbook-missing-parent.err" >&2
    exit 1
fi
examples/os_mode_manifest_check.py --require-apfs --print-commands --clone-dest vm-root-2.raw "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-override.out"
if ! grep -q "apfs_clone_command: .*/examples/os_mode_apfs_clone.sh .*/root.raw .*/vm-root-2.raw" "$tmpdir/manifest-print-commands-override.out"; then
    echo "manifest checker clone-dest output did not include overridden APFS clone destination" >&2
    cat "$tmpdir/manifest-print-commands-override.out" >&2
    exit 1
fi
if ! grep -q -- "--root-disk .*/vm-root-2.raw" "$tmpdir/manifest-print-commands-override.out"; then
    echo "manifest checker clone-dest output did not include overridden os_mode root disk" >&2
    cat "$tmpdir/manifest-print-commands-override.out" >&2
    exit 1
fi
printf old-clone > "$tmpdir/manifest/existing-clone.raw"
if examples/os_mode_manifest_check.py --require-apfs --print-commands --clone-dest existing-clone.raw "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-existing-clone-dest.out" 2>"$tmpdir/manifest-print-commands-existing-clone-dest.err"; then
    echo "manifest checker existing clone-dest negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--clone-dest destination already exists" "$tmpdir/manifest-print-commands-existing-clone-dest.err"; then
    echo "manifest checker existing clone-dest negative test did not report existing destination" >&2
    cat "$tmpdir/manifest-print-commands-existing-clone-dest.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --clone-dest missing-dir/vm-root.raw "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-missing-parent-clone-dest.out" 2>"$tmpdir/manifest-print-commands-missing-parent-clone-dest.err"; then
    echo "manifest checker missing-parent clone-dest negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--clone-dest parent directory does not exist" "$tmpdir/manifest-print-commands-missing-parent-clone-dest.err"; then
    echo "manifest checker missing-parent clone-dest negative test did not report missing parent" >&2
    cat "$tmpdir/manifest-print-commands-missing-parent-clone-dest.err" >&2
    exit 1
fi
printf old-default-clone > "$tmpdir/manifest/vm-root.raw"
if examples/os_mode_manifest_check.py --require-apfs --print-commands "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-existing-default-clone.out" 2>"$tmpdir/manifest-print-commands-existing-default-clone.err"; then
    echo "manifest checker existing default clone-dest negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "apfs_clone_command destination already exists" "$tmpdir/manifest-print-commands-existing-default-clone.err"; then
    echo "manifest checker existing default clone-dest negative test did not report existing destination" >&2
    cat "$tmpdir/manifest-print-commands-existing-default-clone.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --clone-dest root.raw "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-bad-dest.out" 2>"$tmpdir/manifest-print-commands-bad-dest.err"; then
    echo "manifest checker clone-dest root_disk negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--clone-dest must differ from root_disk" "$tmpdir/manifest-print-commands-bad-dest.err"; then
    echo "manifest checker clone-dest root_disk negative test did not report invalid clone destination" >&2
    cat "$tmpdir/manifest-print-commands-bad-dest.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --clone-dest "" "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-empty-dest.out" 2>"$tmpdir/manifest-print-commands-empty-dest.err"; then
    echo "manifest checker empty clone-dest negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "path must be non-empty" "$tmpdir/manifest-print-commands-empty-dest.err"; then
    echo "manifest checker empty clone-dest negative test did not report empty path" >&2
    cat "$tmpdir/manifest-print-commands-empty-dest.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --clone-dest vm-root-2.raw "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-clone-dest-without-print.out" 2>"$tmpdir/manifest-clone-dest-without-print.err"; then
    echo "manifest checker clone-dest without print negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--clone-dest requires --print-commands" "$tmpdir/manifest-clone-dest-without-print.err"; then
    echo "manifest checker clone-dest without print negative test did not report invalid option combination" >&2
    cat "$tmpdir/manifest-clone-dest-without-print.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --smoke-output "" "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-empty-smoke-output.out" 2>"$tmpdir/manifest-print-commands-empty-smoke-output.err"; then
    echo "manifest checker empty smoke-output negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "path must be non-empty" "$tmpdir/manifest-print-commands-empty-smoke-output.err"; then
    echo "manifest checker empty smoke-output negative test did not report empty path" >&2
    cat "$tmpdir/manifest-print-commands-empty-smoke-output.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --smoke-output smoke.json "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-smoke-output-without-print.out" 2>"$tmpdir/manifest-smoke-output-without-print.err"; then
    echo "manifest checker smoke-output without print negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--smoke-output requires --print-commands" "$tmpdir/manifest-smoke-output-without-print.err"; then
    echo "manifest checker smoke-output without print negative test did not report invalid option combination" >&2
    cat "$tmpdir/manifest-smoke-output-without-print.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --perf-output perf.json "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-perf-output-without-print.out" 2>"$tmpdir/manifest-perf-output-without-print.err"; then
    echo "manifest checker perf-output without print negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--perf-output requires --print-commands" "$tmpdir/manifest-perf-output-without-print.err"; then
    echo "manifest checker perf-output without print negative test did not report invalid option combination" >&2
    cat "$tmpdir/manifest-perf-output-without-print.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --perf-output "" "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-empty-perf-output.out" 2>"$tmpdir/manifest-print-commands-empty-perf-output.err"; then
    echo "manifest checker empty perf-output negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "path must be non-empty" "$tmpdir/manifest-print-commands-empty-perf-output.err"; then
    echo "manifest checker empty perf-output negative test did not report empty path" >&2
    cat "$tmpdir/manifest-print-commands-empty-perf-output.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands --write-runbook "" "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-print-commands-empty-runbook.out" 2>"$tmpdir/manifest-print-commands-empty-runbook.err"; then
    echo "manifest checker empty runbook negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "path must be non-empty" "$tmpdir/manifest-print-commands-empty-runbook.err"; then
    echo "manifest checker empty runbook negative test did not report empty path" >&2
    cat "$tmpdir/manifest-print-commands-empty-runbook.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --write-runbook replay.sh "$tmpdir/manifest/manifest.json" >"$tmpdir/manifest-runbook-without-print.out" 2>"$tmpdir/manifest-runbook-without-print.err"; then
    echo "manifest checker runbook without print negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q -- "--write-runbook requires --print-commands" "$tmpdir/manifest-runbook-without-print.err"; then
    echo "manifest checker runbook without print negative test did not report invalid option combination" >&2
    cat "$tmpdir/manifest-runbook-without-print.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-manifest.json" >"$tmpdir/manifest-bad.out" 2>"$tmpdir/manifest-bad.err"; then
    echo "manifest checker negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "missing required field: source_digest" "$tmpdir/manifest-bad.err"; then
    echo "manifest checker negative test did not report missing source_digest" >&2
    cat "$tmpdir/manifest-bad.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-schema-version-manifest.json" >"$tmpdir/manifest-bad-schema-version.out" 2>"$tmpdir/manifest-bad-schema-version.err"; then
    echo "manifest checker schema-version negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "manifest_schema_version must be 1" "$tmpdir/manifest-bad-schema-version.err"; then
    echo "manifest checker schema-version negative test did not report unsupported schema" >&2
    cat "$tmpdir/manifest-bad-schema-version.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-schema-bool-manifest.json" >"$tmpdir/manifest-bad-schema-bool.out" 2>"$tmpdir/manifest-bad-schema-bool.err"; then
    echo "manifest checker schema-version bool negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "manifest_schema_version must be 1" "$tmpdir/manifest-bad-schema-bool.err"; then
    echo "manifest checker schema-version bool negative test did not reject boolean schema" >&2
    cat "$tmpdir/manifest-bad-schema-bool.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-created-at-manifest.json" >"$tmpdir/manifest-bad-created-at.out" 2>"$tmpdir/manifest-bad-created-at.err"; then
    echo "manifest checker created-at negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "created_at_utc must be an ISO 8601 UTC timestamp ending in Z" "$tmpdir/manifest-bad-created-at.err"; then
    echo "manifest checker created-at negative test did not report invalid timestamp" >&2
    cat "$tmpdir/manifest-bad-created-at.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-source-digest-shape-manifest.json" >"$tmpdir/manifest-bad-source-digest-shape.out" 2>"$tmpdir/manifest-bad-source-digest-shape.err"; then
    echo "manifest checker source-digest shape negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "source_digest must be <64 hex>, sha256:<64 hex>, or image@sha256:<64 hex>" "$tmpdir/manifest-bad-source-digest-shape.err"; then
    echo "manifest checker source-digest shape negative test did not report malformed source digest" >&2
    cat "$tmpdir/manifest-bad-source-digest-shape.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-builder-digest-shape-manifest.json" >"$tmpdir/manifest-bad-builder-digest-shape.out" 2>"$tmpdir/manifest-bad-builder-digest-shape.err"; then
    echo "manifest checker builder-digest shape negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "builder_digest must be <64 hex>, sha256:<64 hex>, or image@sha256:<64 hex>" "$tmpdir/manifest-bad-builder-digest-shape.err"; then
    echo "manifest checker builder-digest shape negative test did not report malformed builder digest" >&2
    cat "$tmpdir/manifest-bad-builder-digest-shape.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-missing-builder-digest-manifest.json" >"$tmpdir/manifest-bad-missing-builder-digest.out" 2>"$tmpdir/manifest-bad-missing-builder-digest.err"; then
    echo "manifest checker missing builder-digest negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "missing required field: builder_digest" "$tmpdir/manifest-bad-missing-builder-digest.err"; then
    echo "manifest checker missing builder-digest negative test did not report missing field" >&2
    cat "$tmpdir/manifest-bad-missing-builder-digest.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-build-host-manifest.json" >"$tmpdir/manifest-bad-build-host.out" 2>"$tmpdir/manifest-bad-build-host.err"; then
    echo "manifest checker build-host negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "build_host.system must be a non-empty string" "$tmpdir/manifest-bad-build-host.err"; then
    echo "manifest checker build-host negative test did not report invalid host metadata" >&2
    cat "$tmpdir/manifest-bad-build-host.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-builder-script-manifest.json" >"$tmpdir/manifest-bad-builder-script.out" 2>"$tmpdir/manifest-bad-builder-script.err"; then
    echo "manifest checker builder-script negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "builder_script_sha256 must be <64 hex>, sha256:<64 hex>, or image@sha256:<64 hex>" "$tmpdir/manifest-bad-builder-script.err"; then
    echo "manifest checker builder-script negative test did not report malformed script digest" >&2
    cat "$tmpdir/manifest-bad-builder-script.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-builder-manifest.json" >"$tmpdir/manifest-bad-builder.out" 2>"$tmpdir/manifest-bad-builder.err"; then
    echo "manifest checker builder negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "builder must be examples/os_mode_build_container_rootfs.py" "$tmpdir/manifest-bad-builder.err"; then
    echo "manifest checker builder negative test did not report invalid builder" >&2
    cat "$tmpdir/manifest-bad-builder.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-runtime-manifest.json" >"$tmpdir/manifest-bad-runtime.out" 2>"$tmpdir/manifest-bad-runtime.err"; then
    echo "manifest checker runtime negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "runtime must be docker or podman" "$tmpdir/manifest-bad-runtime.err"; then
    echo "manifest checker runtime negative test did not report invalid runtime" >&2
    cat "$tmpdir/manifest-bad-runtime.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-runtime-version-manifest.json" >"$tmpdir/manifest-bad-runtime-version.out" 2>"$tmpdir/manifest-bad-runtime-version.err"; then
    echo "manifest checker runtime-version negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "runtime_version must be a non-empty string" "$tmpdir/manifest-bad-runtime-version.err"; then
    echo "manifest checker runtime-version negative test did not report invalid runtime version" >&2
    cat "$tmpdir/manifest-bad-runtime-version.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-systemd-mask-manifest.json" >"$tmpdir/manifest-bad-systemd-mask.out" 2>"$tmpdir/manifest-bad-systemd-mask.err"; then
    echo "manifest checker systemd-mask negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "systemd_masks contains invalid systemd unit name" "$tmpdir/manifest-bad-systemd-mask.err"; then
    echo "manifest checker systemd-mask negative test did not report invalid unit" >&2
    cat "$tmpdir/manifest-bad-systemd-mask.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-systemd-mask-type-manifest.json" >"$tmpdir/manifest-bad-systemd-mask-type.out" 2>"$tmpdir/manifest-bad-systemd-mask-type.err"; then
    echo "manifest checker systemd-mask type negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "systemd_default_masks must be boolean" "$tmpdir/manifest-bad-systemd-mask-type.err"; then
    echo "manifest checker systemd-mask type negative test did not report invalid type" >&2
    cat "$tmpdir/manifest-bad-systemd-mask-type.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-missing-apfs-manifest.json" >"$tmpdir/manifest-bad-missing-apfs.out" 2>"$tmpdir/manifest-bad-missing-apfs.err"; then
    echo "manifest checker missing-APFS negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "missing required field: output_dir_apfs" "$tmpdir/manifest-bad-missing-apfs.err"; then
    echo "manifest checker missing-APFS negative test did not report missing output_dir_apfs" >&2
    cat "$tmpdir/manifest-bad-missing-apfs.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-apfs-shape-manifest.json" >"$tmpdir/manifest-bad-apfs-shape.out" 2>"$tmpdir/manifest-bad-apfs-shape.err"; then
    echo "manifest checker APFS shape negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "output_dir_apfs.checked must be boolean" "$tmpdir/manifest-bad-apfs-shape.err"; then
    echo "manifest checker APFS shape negative test did not report malformed checked field" >&2
    cat "$tmpdir/manifest-bad-apfs-shape.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-apfs-checked-manifest.json" >"$tmpdir/manifest-bad-apfs-checked.out" 2>"$tmpdir/manifest-bad-apfs-checked.err"; then
    echo "manifest checker APFS checked negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "output_dir_apfs.filesystem must be a non-empty string when checked" "$tmpdir/manifest-bad-apfs-checked.err"; then
    echo "manifest checker APFS checked negative test did not report missing filesystem evidence" >&2
    cat "$tmpdir/manifest-bad-apfs-checked.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --check-kernel-paths "$tmpdir/manifest/bad-kernel-manifest.json" >"$tmpdir/manifest-bad-kernel.out" 2>"$tmpdir/manifest-bad-kernel.err"; then
    echo "manifest checker kernel-path negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "kernel does not exist or is not a file" "$tmpdir/manifest-bad-kernel.err"; then
    echo "manifest checker kernel-path negative test did not report missing kernel" >&2
    cat "$tmpdir/manifest-bad-kernel.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs --print-commands "$tmpdir/manifest/bad-kernel-manifest.json" >"$tmpdir/manifest-bad-kernel-print.out" 2>"$tmpdir/manifest-bad-kernel-print.err"; then
    echo "manifest checker print-commands missing-kernel negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "kernel does not exist or is not a file" "$tmpdir/manifest-bad-kernel-print.err"; then
    echo "manifest checker print-commands missing-kernel test did not report missing kernel" >&2
    cat "$tmpdir/manifest-bad-kernel-print.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-missing-kernel-field-manifest.json" >"$tmpdir/manifest-bad-missing-kernel-field.out" 2>"$tmpdir/manifest-bad-missing-kernel-field.err"; then
    echo "manifest checker missing-kernel-field negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "missing required field: kernel" "$tmpdir/manifest-bad-missing-kernel-field.err"; then
    echo "manifest checker missing-kernel-field negative test did not report missing kernel field" >&2
    cat "$tmpdir/manifest-bad-missing-kernel-field.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-kernel-format-manifest.json" >"$tmpdir/manifest-bad-kernel-format.out" 2>"$tmpdir/manifest-bad-kernel-format.err"; then
    echo "manifest checker kernel-format negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "kernel_format must be an integer from 0 through 5" "$tmpdir/manifest-bad-kernel-format.err"; then
    echo "manifest checker kernel-format negative test did not report invalid kernel_format" >&2
    cat "$tmpdir/manifest-bad-kernel-format.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-kernel-format-bool-manifest.json" >"$tmpdir/manifest-bad-kernel-format-bool.out" 2>"$tmpdir/manifest-bad-kernel-format-bool.err"; then
    echo "manifest checker bool kernel-format negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "kernel_format must be an integer from 0 through 5" "$tmpdir/manifest-bad-kernel-format-bool.err"; then
    echo "manifest checker bool kernel-format negative test did not reject boolean format" >&2
    cat "$tmpdir/manifest-bad-kernel-format-bool.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-init-mode-manifest.json" >"$tmpdir/manifest-bad-init-mode.out" 2>"$tmpdir/manifest-bad-init-mode.err"; then
    echo "manifest checker init-mode negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "init_mode must be inject-smoke, validate-existing, or systemd" "$tmpdir/manifest-bad-init-mode.err"; then
    echo "manifest checker init-mode negative test did not report invalid init_mode" >&2
    cat "$tmpdir/manifest-bad-init-mode.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-platform-manifest.json" >"$tmpdir/manifest-bad-platform.out" 2>"$tmpdir/manifest-bad-platform.err"; then
    echo "manifest checker platform negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "platform must be linux/arm64 or linux/amd64" "$tmpdir/manifest-bad-platform.err"; then
    echo "manifest checker platform negative test did not report invalid platform" >&2
    cat "$tmpdir/manifest-bad-platform.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-root-device-token-manifest.json" >"$tmpdir/manifest-bad-root-device-token.out" 2>"$tmpdir/manifest-bad-root-device-token.err"; then
    echo "manifest checker root-device token negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "root_device must be a single-token absolute /dev path, PARTUUID=..., or UUID=..." "$tmpdir/manifest-bad-root-device-token.err"; then
    echo "manifest checker root-device token negative test did not report invalid root_device" >&2
    cat "$tmpdir/manifest-bad-root-device-token.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-expected-root-token-manifest.json" >"$tmpdir/manifest-bad-expected-root-token.out" 2>"$tmpdir/manifest-bad-expected-root-token.err"; then
    echo "manifest checker expected-root token negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "expected_root must be a single-token absolute /dev path, PARTUUID=..., or UUID=..." "$tmpdir/manifest-bad-expected-root-token.err"; then
    echo "manifest checker expected-root token negative test did not report invalid expected_root" >&2
    cat "$tmpdir/manifest-bad-expected-root-token.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-root-device-kind-manifest.json" >"$tmpdir/manifest-bad-root-device-kind.out" 2>"$tmpdir/manifest-bad-root-device-kind.err"; then
    echo "manifest checker root-device kind negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "root_device must be a single-token absolute /dev path, PARTUUID=..., or UUID=..." "$tmpdir/manifest-bad-root-device-kind.err"; then
    echo "manifest checker root-device kind negative test did not report unsupported root_device" >&2
    cat "$tmpdir/manifest-bad-root-device-kind.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-root-fstype-token-manifest.json" >"$tmpdir/manifest-bad-root-fstype-token.out" 2>"$tmpdir/manifest-bad-root-fstype-token.err"; then
    echo "manifest checker root-fstype token negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "root_fstype must be a non-empty single token" "$tmpdir/manifest-bad-root-fstype-token.err"; then
    echo "manifest checker root-fstype token negative test did not report invalid root_fstype" >&2
    cat "$tmpdir/manifest-bad-root-fstype-token.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-root-options-token-manifest.json" >"$tmpdir/manifest-bad-root-options-token.out" 2>"$tmpdir/manifest-bad-root-options-token.err"; then
    echo "manifest checker root-options token negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "root_options must be null or a non-empty single token" "$tmpdir/manifest-bad-root-options-token.err"; then
    echo "manifest checker root-options token negative test did not report invalid root_options" >&2
    cat "$tmpdir/manifest-bad-root-options-token.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-root-options-command-manifest.json" >"$tmpdir/manifest-bad-root-options-command.out" 2>"$tmpdir/manifest-bad-root-options-command.err"; then
    echo "manifest checker root-options command negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command root options mismatch" "$tmpdir/manifest-bad-root-options-command.err"; then
    echo "manifest checker root-options command negative test did not report command mismatch" >&2
    cat "$tmpdir/manifest-bad-root-options-command.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-command-manifest.json" >"$tmpdir/manifest-bad-command.out" 2>"$tmpdir/manifest-bad-command.err"; then
    echo "manifest checker command negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command kernel mismatch" "$tmpdir/manifest-bad-command.err"; then
    echo "manifest checker command negative test did not report kernel mismatch" >&2
    cat "$tmpdir/manifest-bad-command.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-launches-base-manifest.json" >"$tmpdir/manifest-bad-launches-base.out" 2>"$tmpdir/manifest-bad-launches-base.err"; then
    echo "manifest checker launch-base negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command root disk must match apfs_clone_command destination" "$tmpdir/manifest-bad-launches-base.err"; then
    echo "manifest checker launch-base negative test did not report root disk clone mismatch" >&2
    cat "$tmpdir/manifest-bad-launches-base.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-command-kernel-format-manifest.json" >"$tmpdir/manifest-bad-command-kernel-format.out" 2>"$tmpdir/manifest-bad-command-kernel-format.err"; then
    echo "manifest checker command kernel-format negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command kernel format mismatch" "$tmpdir/manifest-bad-command-kernel-format.err"; then
    echo "manifest checker command kernel-format negative test did not report kernel format mismatch" >&2
    cat "$tmpdir/manifest-bad-command-kernel-format.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-duplicate-option-manifest.json" >"$tmpdir/manifest-bad-duplicate-option.out" 2>"$tmpdir/manifest-bad-duplicate-option.err"; then
    echo "manifest checker duplicate-option negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command must not repeat --root-disk" "$tmpdir/manifest-bad-duplicate-option.err"; then
    echo "manifest checker duplicate-option negative test did not report repeated root disk option" >&2
    cat "$tmpdir/manifest-bad-duplicate-option.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-missing-option-value-manifest.json" >"$tmpdir/manifest-bad-missing-option-value.out" 2>"$tmpdir/manifest-bad-missing-option-value.err"; then
    echo "manifest checker missing-option-value negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command option --root-disk requires a non-empty value" "$tmpdir/manifest-bad-missing-option-value.err"; then
    echo "manifest checker missing-option-value negative test did not report malformed root disk option" >&2
    cat "$tmpdir/manifest-bad-missing-option-value.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-nonstring-command-manifest.json" >"$tmpdir/manifest-bad-nonstring-command.out" 2>"$tmpdir/manifest-bad-nonstring-command.err"; then
    echo "manifest checker non-string command negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command entries must all be strings" "$tmpdir/manifest-bad-nonstring-command.err"; then
    echo "manifest checker non-string command negative test did not report non-string command item" >&2
    cat "$tmpdir/manifest-bad-nonstring-command.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-unknown-argument-manifest.json" >"$tmpdir/manifest-bad-unknown-argument.out" 2>"$tmpdir/manifest-bad-unknown-argument.err"; then
    echo "manifest checker unknown-argument negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command has unexpected argument: --unknown" "$tmpdir/manifest-bad-unknown-argument.err"; then
    echo "manifest checker unknown-argument negative test did not report unknown option" >&2
    cat "$tmpdir/manifest-bad-unknown-argument.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-os-mode-helper-manifest.json" >"$tmpdir/manifest-bad-os-mode-helper.out" 2>"$tmpdir/manifest-bad-os-mode-helper.err"; then
    echo "manifest checker os_mode helper negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command must start with examples/os_mode" "$tmpdir/manifest-bad-os-mode-helper.err"; then
    echo "manifest checker os_mode helper negative test did not report invalid helper" >&2
    cat "$tmpdir/manifest-bad-os-mode-helper.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-console-manifest.json" >"$tmpdir/manifest-bad-console.out" 2>"$tmpdir/manifest-bad-console.err"; then
    echo "manifest checker console negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command must set --console ttyAMA0 for linux/arm64" "$tmpdir/manifest-bad-console.err"; then
    echo "manifest checker console negative test did not report arm64 console mismatch" >&2
    cat "$tmpdir/manifest-bad-console.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-amd64-console-manifest.json" >"$tmpdir/manifest-bad-amd64-console.out" 2>"$tmpdir/manifest-bad-amd64-console.err"; then
    echo "manifest checker amd64 console negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command must set --console ttyS0 for linux/amd64" "$tmpdir/manifest-bad-amd64-console.err"; then
    echo "manifest checker amd64 console negative test did not report amd64 console mismatch" >&2
    cat "$tmpdir/manifest-bad-amd64-console.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-systemd-manifest.json" >"$tmpdir/manifest-bad-systemd.out" 2>"$tmpdir/manifest-bad-systemd.err"; then
    echo "manifest checker systemd command negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command must set systemd.unit=multi-user.target for systemd init mode" "$tmpdir/manifest-bad-systemd.err"; then
    echo "manifest checker systemd command negative test did not report missing systemd cmdline" >&2
    cat "$tmpdir/manifest-bad-systemd.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-network-smoke-marker-manifest.json" >"$tmpdir/manifest-bad-network-smoke-marker.out" 2>"$tmpdir/manifest-bad-network-smoke-marker.err"; then
    echo "manifest checker network-smoke marker negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "network_smoke requires expected marker KRUN_OSMODE: network=up" "$tmpdir/manifest-bad-network-smoke-marker.err"; then
    echo "manifest checker network-smoke marker negative test did not report missing expected marker" >&2
    cat "$tmpdir/manifest-bad-network-smoke-marker.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-network-smoke-cmdline-manifest.json" >"$tmpdir/manifest-bad-network-smoke-cmdline.out" 2>"$tmpdir/manifest-bad-network-smoke-cmdline.err"; then
    echo "manifest checker network-smoke cmdline negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "os_mode_command must set KRUN_OSMODE_NET=1 for network smoke" "$tmpdir/manifest-bad-network-smoke-cmdline.err"; then
    echo "manifest checker network-smoke cmdline negative test did not report missing network cmdline" >&2
    cat "$tmpdir/manifest-bad-network-smoke-cmdline.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-expected-markers-type-manifest.json" >"$tmpdir/manifest-bad-expected-markers-type.out" 2>"$tmpdir/manifest-bad-expected-markers-type.err"; then
    echo "manifest checker expected-markers type negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "expected_markers contains invalid marker" "$tmpdir/manifest-bad-expected-markers-type.err"; then
    echo "manifest checker expected-markers type negative test did not report invalid marker" >&2
    cat "$tmpdir/manifest-bad-expected-markers-type.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-smoke-timeout-manifest.json" >"$tmpdir/manifest-bad-smoke-timeout.out" 2>"$tmpdir/manifest-bad-smoke-timeout.err"; then
    echo "manifest checker smoke-timeout negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "smoke_timeout_sec must be a positive number" "$tmpdir/manifest-bad-smoke-timeout.err"; then
    echo "manifest checker smoke-timeout negative test did not report invalid timeout" >&2
    cat "$tmpdir/manifest-bad-smoke-timeout.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-smoke-poweroff-type-manifest.json" >"$tmpdir/manifest-bad-smoke-poweroff-type.out" 2>"$tmpdir/manifest-bad-smoke-poweroff-type.err"; then
    echo "manifest checker smoke-poweroff type negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "smoke_poweroff_after_ready must be boolean" "$tmpdir/manifest-bad-smoke-poweroff-type.err"; then
    echo "manifest checker smoke-poweroff type negative test did not report invalid type" >&2
    cat "$tmpdir/manifest-bad-smoke-poweroff-type.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-smoke-wait-exit-manifest.json" >"$tmpdir/manifest-bad-smoke-wait-exit.out" 2>"$tmpdir/manifest-bad-smoke-wait-exit.err"; then
    echo "manifest checker smoke-wait-exit negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "smoke_wait_exit_after_ready_sec must be null or a positive number" "$tmpdir/manifest-bad-smoke-wait-exit.err"; then
    echo "manifest checker smoke-wait-exit negative test did not report invalid wait" >&2
    cat "$tmpdir/manifest-bad-smoke-wait-exit.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-timing-total-manifest.json" >"$tmpdir/manifest-bad-timing-total.out" 2>"$tmpdir/manifest-bad-timing-total.err"; then
    echo "manifest checker timing-total negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "timings_ms.total must be at least export_rootfs + build_ext4" "$tmpdir/manifest-bad-timing-total.err"; then
    echo "manifest checker timing-total negative test did not report inconsistent total" >&2
    cat "$tmpdir/manifest-bad-timing-total.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-timing-bool-manifest.json" >"$tmpdir/manifest-bad-timing-bool.out" 2>"$tmpdir/manifest-bad-timing-bool.err"; then
    echo "manifest checker timing-bool negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "timings_ms.export_rootfs must be a non-negative integer" "$tmpdir/manifest-bad-timing-bool.err"; then
    echo "manifest checker timing-bool negative test did not report boolean timing" >&2
    cat "$tmpdir/manifest-bad-timing-bool.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-checksum-manifest.json" >"$tmpdir/manifest-bad-checksum.out" 2>"$tmpdir/manifest-bad-checksum.err"; then
    echo "manifest checker checksum-presence negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "root_disk_sha256 must be a non-empty string" "$tmpdir/manifest-bad-checksum.err"; then
    echo "manifest checker checksum-presence negative test did not report missing checksum" >&2
    cat "$tmpdir/manifest-bad-checksum.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-root-size-manifest.json" >"$tmpdir/manifest-bad-root-size.out" 2>"$tmpdir/manifest-bad-root-size.err"; then
    echo "manifest checker root-disk size negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "root_disk size mismatch" "$tmpdir/manifest-bad-root-size.err"; then
    echo "manifest checker root-disk size negative test did not report size mismatch" >&2
    cat "$tmpdir/manifest-bad-root-size.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-root-size-mb-manifest.json" >"$tmpdir/manifest-bad-root-size-mb.out" 2>"$tmpdir/manifest-bad-root-size-mb.err"; then
    echo "manifest checker root-disk size-mb negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "root_disk_size_bytes must equal root_disk_size_mb MiB" "$tmpdir/manifest-bad-root-size-mb.err"; then
    echo "manifest checker root-disk size-mb negative test did not report MiB mismatch" >&2
    cat "$tmpdir/manifest-bad-root-size-mb.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-rootfs-size-manifest.json" >"$tmpdir/manifest-bad-rootfs-size.out" 2>"$tmpdir/manifest-bad-rootfs-size.err"; then
    echo "manifest checker rootfs-tar size negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "rootfs_tar size mismatch" "$tmpdir/manifest-bad-rootfs-size.err"; then
    echo "manifest checker rootfs-tar size negative test did not report size mismatch" >&2
    cat "$tmpdir/manifest-bad-rootfs-size.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-overlay-checksum-manifest.json" >"$tmpdir/manifest-bad-overlay-checksum.out" 2>"$tmpdir/manifest-bad-overlay-checksum.err"; then
    echo "manifest checker overlay checksum negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "overlay_tar_sha256 must be null when overlay_tar is null" "$tmpdir/manifest-bad-overlay-checksum.err"; then
    echo "manifest checker overlay checksum negative test did not report stale checksum" >&2
    cat "$tmpdir/manifest-bad-overlay-checksum.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-overlay-size-null-manifest.json" >"$tmpdir/manifest-bad-overlay-size-null.out" 2>"$tmpdir/manifest-bad-overlay-size-null.err"; then
    echo "manifest checker overlay size-null negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "overlay_tar_size_bytes must be null when overlay_tar is null" "$tmpdir/manifest-bad-overlay-size-null.err"; then
    echo "manifest checker overlay size-null negative test did not report stale overlay size" >&2
    cat "$tmpdir/manifest-bad-overlay-size-null.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-clone-dest-manifest.json" >"$tmpdir/manifest-bad-clone-dest.out" 2>"$tmpdir/manifest-bad-clone-dest.err"; then
    echo "manifest checker APFS clone destination negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "apfs_clone_command destination must be a non-empty string" "$tmpdir/manifest-bad-clone-dest.err"; then
    echo "manifest checker APFS clone destination negative test did not report missing destination" >&2
    cat "$tmpdir/manifest-bad-clone-dest.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-clone-nonstring-manifest.json" >"$tmpdir/manifest-bad-clone-nonstring.out" 2>"$tmpdir/manifest-bad-clone-nonstring.err"; then
    echo "manifest checker APFS clone non-string negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "apfs_clone_command entries must all be strings" "$tmpdir/manifest-bad-clone-nonstring.err"; then
    echo "manifest checker APFS clone non-string negative test did not report non-string command item" >&2
    cat "$tmpdir/manifest-bad-clone-nonstring.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-clone-helper-manifest.json" >"$tmpdir/manifest-bad-clone-helper.out" 2>"$tmpdir/manifest-bad-clone-helper.err"; then
    echo "manifest checker APFS clone helper negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "apfs_clone_command must start with examples/os_mode_apfs_clone.sh" "$tmpdir/manifest-bad-clone-helper.err"; then
    echo "manifest checker APFS clone helper negative test did not report invalid helper" >&2
    cat "$tmpdir/manifest-bad-clone-helper.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-clone-dest-resolved-manifest.json" >"$tmpdir/manifest-bad-clone-dest-resolved.out" 2>"$tmpdir/manifest-bad-clone-dest-resolved.err"; then
    echo "manifest checker APFS clone resolved destination negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "apfs_clone_command destination must resolve differently from root_disk" "$tmpdir/manifest-bad-clone-dest-resolved.err"; then
    echo "manifest checker APFS clone resolved destination negative test did not report base-image alias" >&2
    cat "$tmpdir/manifest-bad-clone-dest-resolved.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-clone-dest-rootfs-manifest.json" >"$tmpdir/manifest-bad-clone-dest-rootfs.out" 2>"$tmpdir/manifest-bad-clone-dest-rootfs.err"; then
    echo "manifest checker APFS clone rootfs-tar destination negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "apfs_clone_command destination must resolve differently from rootfs_tar" "$tmpdir/manifest-bad-clone-dest-rootfs.err"; then
    echo "manifest checker APFS clone rootfs-tar destination negative test did not report protected rootfs tar" >&2
    cat "$tmpdir/manifest-bad-clone-dest-rootfs.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-clone-dest-overlay-manifest.json" >"$tmpdir/manifest-bad-clone-dest-overlay.out" 2>"$tmpdir/manifest-bad-clone-dest-overlay.err"; then
    echo "manifest checker APFS clone overlay destination negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "apfs_clone_command destination must resolve differently from overlay_tar" "$tmpdir/manifest-bad-clone-dest-overlay.err"; then
    echo "manifest checker APFS clone overlay destination negative test did not report protected overlay tar" >&2
    cat "$tmpdir/manifest-bad-clone-dest-overlay.err" >&2
    exit 1
fi
if examples/os_mode_manifest_check.py --require-apfs "$tmpdir/manifest/bad-clone-dest-manifestfile-manifest.json" >"$tmpdir/manifest-bad-clone-dest-manifestfile.out" 2>"$tmpdir/manifest-bad-clone-dest-manifestfile.err"; then
    echo "manifest checker APFS clone manifest destination negative test unexpectedly succeeded" >&2
    exit 1
fi
if ! grep -q "apfs_clone_command destination must resolve differently from manifest" "$tmpdir/manifest-bad-clone-dest-manifestfile.err"; then
    echo "manifest checker APFS clone manifest destination negative test did not report protected manifest file" >&2
    cat "$tmpdir/manifest-bad-clone-dest-manifestfile.err" >&2
    exit 1
fi

echo "==> host-independent OS-mode checks passed"
