#!/usr/bin/env python3
"""Publish a validated OS-mode artifact directory as a container bundle."""

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from os_mode_import_container_bundle import (
    BUNDLE_KIND,
    BUNDLE_SCHEMA_VERSION,
    PLATFORM_CONSOLES,
    SUPPORTED_RUNTIMES,
    allocated_size_bytes,
    command_quote,
    sha256_file,
    validate_manifest as validate_bundle_manifest,
)
from os_mode_manifest_check import (
    check_manifest_payload,
    command_value,
    manifest_path,
    validate_manifest as load_source_manifest,
)


class PublishError(Exception):
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
            "Create a Docker-compatible libkrun OS bundle image context from "
            "an os_mode_build_container_rootfs.py manifest."
        )
    )
    parser.add_argument("manifest", type=non_empty_path)
    parser.add_argument(
        "--output-dir",
        type=non_empty_path,
        required=True,
        help="Fresh directory that will receive Containerfile and libkrun-os-bundle/.",
    )
    parser.add_argument(
        "--image-tag",
        type=non_empty_arg,
        default=None,
        help="Optional Docker/Podman tag to build after writing the bundle context.",
    )
    parser.add_argument(
        "--push",
        action="store_true",
        help="Push --image-tag after building and print the digest-pinned pull reference.",
    )
    parser.add_argument(
        "--archive-output",
        type=non_empty_path,
        default=None,
        help="With --image-tag, save the built image to this fresh Docker-compatible archive.",
    )
    parser.add_argument(
        "--archive-sha256-output",
        type=non_empty_path,
        default=None,
        help="With --archive-output, write the archive SHA-256 to this fresh file.",
    )
    parser.add_argument(
        "--digest-output",
        type=non_empty_path,
        default=None,
        help="With --push, write the digest-pinned image reference to this fresh file.",
    )
    parser.add_argument(
        "--artifact-manifest-output",
        type=non_empty_path,
        default=None,
        help="Write a fresh JSON manifest describing the published sample artifact.",
    )
    parser.add_argument(
        "--runtime",
        choices=("auto",) + SUPPORTED_RUNTIMES,
        default="auto",
        help="Container runtime used only when --image-tag is provided.",
    )
    parser.add_argument(
        "--expected-pid1",
        type=non_empty_arg,
        default="auto",
        help="Expected guest PID 1 marker for bundle smoke validation, or auto.",
    )
    parser.add_argument(
        "--allow-existing-output-dir",
        action="store_true",
        help="Allow an existing empty output directory. Non-empty directories are always rejected.",
    )
    return parser.parse_args()


def resolve_required_path(manifest_dir: Path, value: Any, label: str) -> Path:
    path = manifest_path(manifest_dir, value)
    if path is None:
        raise PublishError(f"{label} must be a non-empty path")
    path = path.expanduser().resolve()
    if not path.is_file():
        raise PublishError(f"{label} does not exist or is not a file: {path}")
    return path


def resolve_optional_path(manifest_dir: Path, value: Any, label: str) -> Path | None:
    if value is None:
        return None
    return resolve_required_path(manifest_dir, value, label)


def prepare_output_dir(output_dir: Path, allow_existing_empty: bool) -> Path:
    output_dir = output_dir.expanduser().resolve()
    if output_dir.exists():
        if not output_dir.is_dir():
            raise PublishError(f"--output-dir exists and is not a directory: {output_dir}")
        if any(output_dir.iterdir()):
            raise PublishError(f"--output-dir already contains files: {output_dir}")
        if not allow_existing_empty:
            raise PublishError(
                f"--output-dir already exists; pass --allow-existing-output-dir for an empty directory: {output_dir}"
            )
    else:
        output_dir.mkdir(parents=True)
    return output_dir


def choose_runtime(requested: str) -> str:
    candidates = SUPPORTED_RUNTIMES if requested == "auto" else (requested,)
    for runtime in candidates:
        if shutil.which(runtime):
            return runtime
    raise PublishError("no supported container runtime found; install Docker or Podman")


def run(command: list[str]) -> None:
    proc = subprocess.run(command)
    if proc.returncode != 0:
        raise PublishError(f"command failed: {command_quote(command)}")


def run_capture(command: list[str]) -> str:
    proc = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise PublishError(f"command failed: {command_quote(command)}\n{proc.stderr.strip()}")
    return proc.stdout


def image_digest(runtime: str, image: str) -> str | None:
    payload_text = run_capture([runtime, "image", "inspect", image])
    try:
        payload = json.loads(payload_text)
    except json.JSONDecodeError as err:
        raise PublishError(f"could not parse {runtime} image inspect output: {err}") from err
    if not payload:
        return None
    repo_digests = payload[0].get("RepoDigests") or []
    for repo_digest in repo_digests:
        if isinstance(repo_digest, str) and "@sha256:" in repo_digest:
            return repo_digest
    return None


def write_digest_output(path: Path, digest_ref: str) -> None:
    write_text_output(path, digest_ref + "\n", "--digest-output")


def write_text_output(path: Path, text: str, label: str) -> None:
    path = path.expanduser().resolve()
    if not path.parent.is_dir():
        raise PublishError(f"{label} parent directory does not exist: {path.parent}")
    if path.exists():
        raise PublishError(f"{label} destination already exists: {path}")
    path.write_text(text, encoding="utf-8")


def validate_fresh_file_output(path: Path, label: str) -> Path:
    path = path.expanduser().resolve()
    if not path.parent.is_dir():
        raise PublishError(f"{label} parent directory does not exist: {path.parent}")
    if path.exists():
        raise PublishError(f"{label} destination already exists: {path}")
    return path


def save_image_archive(runtime: str, image: str, archive_output: Path) -> Path:
    archive_output = validate_fresh_file_output(archive_output, "--archive-output")
    run([runtime, "save", "-o", str(archive_output), image])
    if not archive_output.is_file():
        raise PublishError(f"{runtime} save did not create archive: {archive_output}")
    return archive_output


def utc_timestamp() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def build_artifact_manifest(
    *,
    image_tag: str | None,
    digest_ref: str | None,
    runtime: str | None,
    output_dir: Path,
    bundle_dir: Path,
    bundle_manifest: dict[str, Any],
    archive_path: Path | None,
    archive_sha256: str | None,
) -> dict[str, Any]:
    archive = None
    if archive_path is not None:
        archive = {
            "path": str(archive_path),
            "sha256": archive_sha256,
            "size_bytes": archive_path.stat().st_size,
            "load_command": [runtime or "docker", "load", "-i", str(archive_path)],
        }

    run_image = digest_ref or image_tag
    return {
        "schema_version": 1,
        "kind": "libkrun.os-bundle.artifact.v1",
        "created_at_utc": utc_timestamp(),
        "image_tag": image_tag,
        "digest_ref": digest_ref,
        "runtime": runtime,
        "output_dir": str(output_dir),
        "bundle_dir": str(bundle_dir),
        "bundle_manifest": {
            "path": str(bundle_dir / "manifest.json"),
            "sha256": sha256_file(bundle_dir / "manifest.json"),
            "kind": bundle_manifest.get("kind"),
            "platform": bundle_manifest.get("platform"),
            "expected_root": bundle_manifest.get("expected_root"),
            "expected_console": bundle_manifest.get("console"),
            "expected_pid1": bundle_manifest.get("expected_pid1"),
            "root_disk_sha256": bundle_manifest.get("root_disk_sha256"),
            "kernel_sha256": bundle_manifest.get("kernel_sha256"),
            "initramfs_sha256": bundle_manifest.get("initramfs_sha256"),
        },
        "archive": archive,
        "commands": {
            "load": archive["load_command"] if archive is not None else None,
            "run": (
                ["examples/krun_os_run.py", run_image]
                if run_image is not None
                else None
            ),
            "clean_host_preflight": (
                [
                    "examples/os_mode_clean_host_preflight.py",
                    digest_ref,
                    "--output-dir",
                    "RELEASE_EVIDENCE_DIR",
                    "--json-output",
                    "CLEAN_HOST_PREFLIGHT_JSON",
                ]
                if digest_ref is not None
                else None
            ),
            "clean_host_preflight_from_artifact": (
                [
                    "examples/os_mode_clean_host_preflight.py",
                    "--artifact-manifest",
                    "ARTIFACT_MANIFEST",
                    "--output-dir",
                    "RELEASE_EVIDENCE_DIR",
                    "--json-output",
                    "CLEAN_HOST_PREFLIGHT_JSON",
                ]
                if archive is not None
                else None
            ),
            "clean_host_baseline": (
                [
                    "examples/os_mode_clean_host_baseline.py",
                    digest_ref,
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
                ]
                if digest_ref is not None
                else None
            ),
            "clean_host_baseline_from_artifact": (
                [
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
                ]
                if archive is not None
                else None
            ),
            "release_gate": (
                [
                    "examples/os_mode_release_gate.py",
                    digest_ref,
                    "--output-dir",
                    "RELEASE_EVIDENCE_DIR",
                    "--preflight-json",
                    "CLEAN_HOST_PREFLIGHT_JSON",
                    "--clean-host-baseline",
                ]
                if digest_ref is not None
                else None
            ),
            "release_gate_from_artifact": (
                [
                    "examples/os_mode_release_gate.py",
                    "--artifact-manifest",
                    "ARTIFACT_MANIFEST",
                    "--output-dir",
                    "RELEASE_EVIDENCE_DIR",
                    "--preflight-json",
                    "CLEAN_HOST_PREFLIGHT_JSON",
                    "--clean-host-baseline",
                ]
                if archive is not None
                else None
            ),
        },
    }


def write_artifact_manifest(path: Path, manifest: dict[str, Any]) -> None:
    write_text_output(
        path,
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        "--artifact-manifest-output",
    )


def expected_pid1(source_manifest: dict[str, Any], requested: str) -> str:
    if requested != "auto":
        if requested == "init.krun":
            raise PublishError("--expected-pid1 must not be init.krun")
        return requested
    if source_manifest.get("init_mode") == "systemd":
        return "systemd"
    return "init"


def positive_int_manifest_value(source_manifest: dict[str, Any], key: str) -> int:
    value = source_manifest.get(key)
    if isinstance(value, bool):
        raise PublishError(f"{key} must be a positive integer")
    if isinstance(value, int):
        result = value
    elif isinstance(value, float) and value.is_integer():
        result = int(value)
    else:
        raise PublishError(f"{key} must be a positive integer")
    if result <= 0:
        raise PublishError(f"{key} must be a positive integer")
    return result


def optional_positive_int_manifest_value(source_manifest: dict[str, Any], key: str) -> int | None:
    value = source_manifest.get(key)
    if value is None:
        return None
    return positive_int_manifest_value(source_manifest, key)


def copy_file(src: Path, dst: Path) -> None:
    shutil.copy2(src, dst)


def build_bundle_manifest(
    source_manifest: dict[str, Any],
    source_manifest_file: Path,
    bundle_dir: Path,
    expected_pid1_value: str,
) -> dict[str, Any]:
    source_dir = source_manifest_file.parent
    root_disk = resolve_required_path(source_dir, source_manifest.get("root_disk"), "root_disk")
    kernel = resolve_required_path(source_dir, source_manifest.get("kernel"), "kernel")
    initramfs = resolve_optional_path(source_dir, source_manifest.get("initramfs"), "initramfs")

    apfs_clone = source_manifest.get("apfs_clone_command")
    if isinstance(apfs_clone, list) and len(apfs_clone) >= 3:
        clone_candidate = manifest_path(source_dir, apfs_clone[2])
        if clone_candidate is not None and clone_candidate.expanduser().resolve() == root_disk:
            raise PublishError("source manifest APFS clone destination resolves to immutable root_disk")

    launch_root = command_value(source_manifest.get("os_mode_command", []), "--root-disk")
    if launch_root is not None:
        launch_root_path = manifest_path(source_dir, launch_root)
        if launch_root_path is not None and launch_root_path.expanduser().resolve() == root_disk:
            raise PublishError("source manifest launch command attaches immutable root_disk directly")

    bundle_root = bundle_dir / "root.raw"
    bundle_kernel = bundle_dir / "kernel"
    bundle_initramfs = bundle_dir / "initramfs"
    copy_file(root_disk, bundle_root)
    copy_file(kernel, bundle_kernel)
    if initramfs is not None:
        copy_file(initramfs, bundle_initramfs)

    platform_name = source_manifest["platform"]
    bundle_manifest = {
        "kind": BUNDLE_KIND,
        "manifest_schema_version": BUNDLE_SCHEMA_VERSION,
        "source_manifest": "source-manifest.json",
        "source_manifest_sha256": sha256_file(source_manifest_file),
        "source_image": source_manifest["source_image"],
        "source_digest": source_manifest["source_digest"],
        "platform": platform_name,
        "kernel": "kernel",
        "kernel_sha256": sha256_file(bundle_kernel),
        "kernel_format": source_manifest["kernel_format"],
        "initramfs": "initramfs" if initramfs is not None else None,
        "initramfs_sha256": sha256_file(bundle_initramfs) if initramfs is not None else None,
        "root_disk": "root.raw",
        "root_disk_sha256": sha256_file(bundle_root),
        "root_disk_size_bytes": bundle_root.stat().st_size,
        "root_disk_allocated_bytes": allocated_size_bytes(bundle_root),
        "root_device": source_manifest["root_device"],
        "expected_root": source_manifest["expected_root"],
        "root_fstype": source_manifest["root_fstype"],
        "root_options": source_manifest["root_options"],
        "init": source_manifest["init"],
        "console": PLATFORM_CONSOLES[platform_name],
        "expected_pid1": expected_pid1_value,
        "expected_markers": source_manifest.get("expected_markers", []),
        "smoke_timeout_sec": positive_int_manifest_value(source_manifest, "smoke_timeout_sec"),
        "smoke_poweroff_after_ready": source_manifest["smoke_poweroff_after_ready"],
        "smoke_wait_exit_after_ready_sec": optional_positive_int_manifest_value(
            source_manifest,
            "smoke_wait_exit_after_ready_sec",
        ),
        "require_apfs_clone": True,
        "allow_full_copy_fallback": False,
    }
    return bundle_manifest


def write_containerfile(output_dir: Path) -> None:
    (output_dir / "Containerfile").write_text(
        "FROM scratch\n"
        "COPY libkrun-os-bundle /libkrun-os-bundle\n"
        'LABEL org.opencontainers.image.title="libkrun OS bundle"\n',
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()
    try:
        if args.push and args.image_tag is None:
            raise PublishError("--push requires --image-tag")
        if args.digest_output is not None and not args.push:
            raise PublishError("--digest-output requires --push")
        if args.archive_output is not None and args.image_tag is None:
            raise PublishError("--archive-output requires --image-tag")
        if args.archive_sha256_output is not None and args.archive_output is None:
            raise PublishError("--archive-sha256-output requires --archive-output")

        source_manifest_file = args.manifest.expanduser().resolve()
        source_manifest, load_errors = load_source_manifest(source_manifest_file)
        if load_errors:
            raise PublishError("\n".join(load_errors))
        assert source_manifest is not None

        source_errors = check_manifest_payload(
            source_manifest,
            source_manifest_file.parent,
            manifest_file=source_manifest_file,
            require_apfs=False,
            check_kernel_paths=True,
        )
        if source_errors:
            raise PublishError("\n".join(source_errors))

        pid1 = expected_pid1(source_manifest, args.expected_pid1)
        output_dir = prepare_output_dir(args.output_dir, args.allow_existing_output_dir)
        bundle_dir = output_dir / "libkrun-os-bundle"
        bundle_dir.mkdir()
        shutil.copy2(source_manifest_file, bundle_dir / "source-manifest.json")
        bundle_manifest = build_bundle_manifest(source_manifest, source_manifest_file, bundle_dir, pid1)
        manifest_file = bundle_dir / "manifest.json"
        manifest_file.write_text(json.dumps(bundle_manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        validate_bundle_manifest(bundle_dir, strict_digest=True)
        write_containerfile(output_dir)

        print(f"bundle_dir: {bundle_dir}")
        print(f"manifest: {manifest_file}")
        print(f"containerfile: {output_dir / 'Containerfile'}")
        runtime = None
        archive_path = None
        archive_sha = None
        digest_ref = None
        if args.image_tag is not None:
            runtime = choose_runtime(args.runtime)
            command = [runtime, "build", "-f", str(output_dir / "Containerfile"), "-t", args.image_tag, str(output_dir)]
            print(f"build_command: {command_quote(command)}")
            run(command)
            if args.archive_output is not None:
                archive_path = save_image_archive(runtime, args.image_tag, args.archive_output)
                archive_sha = sha256_file(archive_path)
                print(f"archive: {archive_path}")
                print(f"archive_sha256: {archive_sha}")
                print(f"load_command: {command_quote([runtime, 'load', '-i', str(archive_path)])}")
                if args.archive_sha256_output is not None:
                    write_text_output(
                        args.archive_sha256_output,
                        archive_sha + "\n",
                        "--archive-sha256-output",
                    )
            if args.push:
                push_command = [runtime, "push", args.image_tag]
                print(f"push_command: {command_quote(push_command)}")
                run(push_command)
                digest_ref = image_digest(runtime, args.image_tag)
                if digest_ref is None:
                    raise PublishError(f"could not determine pushed image digest for {args.image_tag}")
                print(f"digest_image: {digest_ref}")
                print(
                    "import_command: "
                    + command_quote(
                        [
                            "examples/os_mode_import_container_bundle.py",
                            "--image",
                            digest_ref,
                            "--output-dir",
                            "BUNDLE_OUTPUT_DIR",
                            "--strict-digest",
                        ]
                    )
                )
                if args.digest_output is not None:
                    write_digest_output(args.digest_output, digest_ref)
        if args.artifact_manifest_output is not None:
            artifact_manifest = build_artifact_manifest(
                image_tag=args.image_tag,
                digest_ref=digest_ref,
                runtime=runtime,
                output_dir=output_dir,
                bundle_dir=bundle_dir,
                bundle_manifest=bundle_manifest,
                archive_path=archive_path,
                archive_sha256=archive_sha,
            )
            write_artifact_manifest(args.artifact_manifest_output, artifact_manifest)
            print(f"artifact_manifest: {args.artifact_manifest_output.expanduser().resolve()}")
        return 0
    except PublishError as err:
        print(err, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
