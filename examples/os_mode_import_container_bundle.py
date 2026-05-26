#!/usr/bin/env python3
"""Import a libkrun OS-mode bundle from an OCI image or extracted directory.

The bundle image is a packaging format, not the runtime. This helper extracts
or validates host files, creates a command that APFS-clones the immutable
root.raw, and launches examples/os_mode on the macOS host when --run is used.
"""

import argparse
import hashlib
import json
import platform
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


BUNDLE_KIND = "libkrun.os-bundle.v1"
BUNDLE_SCHEMA_VERSION = 1
BUNDLE_DIR_IN_IMAGE = "/libkrun-os-bundle"
IMPORT_METADATA_FILE = ".libkrun-os-bundle-import.json"
SUPPORTED_PLATFORMS = ("linux/arm64", "linux/amd64")
PLATFORM_CONSOLES = {
    "linux/arm64": "ttyAMA0",
    "linux/amd64": "ttyS0",
}
SUPPORTED_KERNEL_FORMATS = (0, 1, 2, 3)
SUPPORTED_ROOT_FSTYPES = ("ext4",)
SUPPORTED_RUNTIMES = ("docker", "podman")
REPO_ROOT = Path(__file__).resolve().parent.parent


class BundleError(Exception):
    pass


def diagnostic_category(error: BaseException | str) -> str:
    message = str(error)
    lowered = message.lower()

    if "reuse-extracted-output-dir" in message or "import metadata" in lowered:
        return "cache-reuse"
    if "strict-digest with --image" in message or "no supported container runtime" in lowered:
        return "image-resolution"
    if (
        "command failed:" in lowered
        or "failed to copy" in lowered
        or "create did not return" in lowered
        or BUNDLE_DIR_IN_IMAGE.lower() in lowered
    ):
        return "image-extraction"
    if (
        "destination already exists" in lowered
        or "parent directory does not exist" in lowered
        or "must differ from" in lowered
        or "output-dir already contains files" in lowered
    ):
        return "output-path"
    if "bundle directory must be on apfs" in lowered or "apfs clone command failed" in lowered:
        return "apfs-clone"
    if "required repo helper" in lowered or "examples/os_mode" in lowered:
        return "host-launcher"
    if (
        "smoke evidence" in lowered
        or "smoke command failed" in lowered
        or "observed root" in lowered
        or "observed consoles" in lowered
        or "observed pid 1" in lowered
    ):
        return "guest-readiness"
    if (
        "manifest" in lowered
        or "sha256" in lowered
        or "root_disk" in lowered
        or "kernel" in lowered
        or "platform" in lowered
        or "console" in lowered
        or "expected_pid1" in lowered
        or "allow_full_copy_fallback" in lowered
        or "must stay inside" in lowered
    ):
        return "manifest-validation"
    return "usage"


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
            "Validate a libkrun OS-mode bundle and print or run the host-side "
            "APFS clone plus examples/os_mode launch commands."
        )
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument(
        "--bundle-dir",
        type=non_empty_path,
        help="Already extracted libkrun-os-bundle directory.",
    )
    source.add_argument(
        "--image",
        type=non_empty_arg,
        help="Docker/Podman image containing /libkrun-os-bundle.",
    )
    parser.add_argument(
        "--output-dir",
        type=non_empty_path,
        default=None,
        help="Host directory for extracting --image bundles.",
    )
    parser.add_argument(
        "--reuse-extracted-output-dir",
        action="store_true",
        help=(
            "With --image, reuse an existing --output-dir only when it contains "
            "a previously imported bundle whose import metadata matches the "
            "same image reference."
        ),
    )
    parser.add_argument(
        "--runtime",
        choices=("auto",) + SUPPORTED_RUNTIMES,
        default="auto",
        help="Container runtime used only for bundle extraction.",
    )
    parser.add_argument(
        "--pull",
        action="store_true",
        help="With --image, explicitly pull the bundle image before extraction and record pull timing.",
    )
    parser.add_argument(
        "--clone-dest",
        type=non_empty_path,
        default=None,
        help="APFS clone destination. Relative paths resolve against the bundle directory.",
    )
    parser.add_argument(
        "--smoke-output",
        type=non_empty_path,
        default=None,
        help="Optional smoke JSON output path. Relative paths resolve against the bundle directory.",
    )
    parser.add_argument(
        "--perf-output",
        type=non_empty_path,
        default=None,
        help="Optional perf JSON output path. Relative paths resolve against the bundle directory.",
    )
    parser.add_argument(
        "--require-apfs",
        action="store_true",
        help="Require the bundle directory to live on APFS before printing or running commands.",
    )
    parser.add_argument(
        "--strict-digest",
        action="store_true",
        help="Require the manifest source_digest to look like an immutable sha256 identity.",
    )
    parser.add_argument(
        "--run",
        action="store_true",
        help="Run the APFS clone command followed by the smoke wrapper on the macOS host.",
    )
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def command_quote(command: list[str]) -> str:
    return " ".join(shlex.quote(item) for item in command)


def repo_file(relative: str, *, require_exists: bool = True) -> Path:
    path = (REPO_ROOT / relative).resolve()
    if require_exists and not path.is_file():
        raise BundleError(f"required repo helper does not exist: {path}")
    return path


def resolve_bundle_path(bundle_dir: Path, value: Any, label: str, errors: list[str]) -> Path | None:
    if not isinstance(value, str) or value == "":
        errors.append(f"{label} must be a non-empty relative path")
        return None

    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        errors.append(f"{label} must stay inside the bundle directory")
        return None

    candidate = bundle_dir / path
    try:
        resolved = candidate.resolve(strict=True)
        bundle_resolved = bundle_dir.resolve(strict=True)
    except FileNotFoundError:
        errors.append(f"{label} does not exist: {candidate}")
        return None

    try:
        resolved.relative_to(bundle_resolved)
    except ValueError:
        errors.append(f"{label} resolves outside the bundle directory: {value}")
        return None

    if not resolved.is_file():
        errors.append(f"{label} is not a regular file: {value}")
        return None
    return resolved


def optional_bundle_path(
    bundle_dir: Path,
    value: Any,
    checksum: Any,
    label: str,
    errors: list[str],
) -> Path | None:
    if value is None:
        require(checksum is None, f"{label}_sha256 must be null when {label} is null", errors)
        return None
    return resolve_bundle_path(bundle_dir, value, label, errors)


def single_kernel_token(value: Any, label: str, errors: list[str], allow_null: bool = False) -> str | None:
    if value is None and allow_null:
        return None
    if not isinstance(value, str) or value == "":
        errors.append(f"{label} must be a non-empty string")
        return None
    if value.split() != [value]:
        errors.append(f"{label} must be a single kernel command-line token")
    return value


def valid_root_token(value: Any, label: str, errors: list[str]) -> str | None:
    token = single_kernel_token(value, label, errors)
    if token is None:
        return None
    if not (
        token.startswith("/dev/")
        or token.startswith("PARTUUID=")
        or token.startswith("UUID=")
    ):
        errors.append(f"{label} must start with /dev/, PARTUUID=, or UUID=")
    return token


def digest_identity(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    if value.startswith("sha256:"):
        hex_part = value.removeprefix("sha256:")
    elif "@sha256:" in value:
        hex_part = value.rsplit("@sha256:", 1)[1]
    else:
        hex_part = value
    return len(hex_part) == 64 and all(char in "0123456789abcdefABCDEF" for char in hex_part)


def image_reference_is_digest_pinned(value: str) -> bool:
    if "@sha256:" not in value:
        return False
    return digest_identity(value.rsplit("@", 1)[1])


def validate_file_digest(path: Path | None, manifest: dict[str, Any], key: str, errors: list[str]) -> None:
    expected = manifest.get(key)
    if path is None:
        return
    require(isinstance(expected, str) and digest_identity(expected), f"{key} must be a sha256 digest", errors)
    if isinstance(expected, str) and digest_identity(expected):
        digest = expected.rsplit(":", 1)[-1] if ":" in expected else expected
        actual = sha256_file(path)
        require(actual.lower() == digest.lower(), f"{key} does not match {path.name}", errors)


def validate_positive_int(value: Any, label: str, errors: list[str]) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        errors.append(f"{label} must be a positive integer")
        return None
    return value


def allocated_size_bytes(path: Path) -> int | None:
    blocks = getattr(path.stat(), "st_blocks", None)
    if blocks is None:
        return None
    return int(blocks) * 512


def validate_manifest(bundle_dir: Path, strict_digest: bool = False) -> dict[str, Any]:
    manifest_path = bundle_dir / "manifest.json"
    if not manifest_path.is_file():
        raise BundleError(f"bundle manifest does not exist: {manifest_path}")

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise BundleError(f"bundle manifest is invalid JSON: {err}") from err

    errors: list[str] = []
    require(isinstance(manifest, dict), "manifest must be a JSON object", errors)
    if not isinstance(manifest, dict):
        raise BundleError("\n".join(errors))

    require(manifest.get("kind") == BUNDLE_KIND, f"kind must be {BUNDLE_KIND}", errors)
    require(
        manifest.get("manifest_schema_version") == BUNDLE_SCHEMA_VERSION
        and not isinstance(manifest.get("manifest_schema_version"), bool),
        f"manifest_schema_version must be {BUNDLE_SCHEMA_VERSION}",
        errors,
    )
    require(isinstance(manifest.get("source_image"), str) and manifest["source_image"], "source_image is required", errors)
    source_digest = manifest.get("source_digest")
    require(
        source_digest is None or digest_identity(source_digest),
        "source_digest must be null or a sha256 identity",
        errors,
    )
    if strict_digest:
        require(digest_identity(source_digest), "--strict-digest requires source_digest to be a sha256 identity", errors)

    platform_name = manifest.get("platform")
    require(platform_name in SUPPORTED_PLATFORMS, f"platform must be one of {SUPPORTED_PLATFORMS}", errors)
    expected_console = PLATFORM_CONSOLES.get(platform_name)
    console = single_kernel_token(manifest.get("console"), "console", errors)
    if expected_console is not None:
        require(console == expected_console, f"console must be {expected_console} for {platform_name}", errors)

    kernel_format = manifest.get("kernel_format")
    require(
        isinstance(kernel_format, int)
        and not isinstance(kernel_format, bool)
        and kernel_format in SUPPORTED_KERNEL_FORMATS,
        f"kernel_format must be one of {SUPPORTED_KERNEL_FORMATS}",
        errors,
    )

    root_fstype = single_kernel_token(manifest.get("root_fstype"), "root_fstype", errors)
    require(root_fstype in SUPPORTED_ROOT_FSTYPES, f"root_fstype must be one of {SUPPORTED_ROOT_FSTYPES}", errors)
    valid_root_token(manifest.get("root_device"), "root_device", errors)
    expected_root = valid_root_token(manifest.get("expected_root"), "expected_root", errors)
    root_options = single_kernel_token(manifest.get("root_options"), "root_options", errors, allow_null=True)
    init = single_kernel_token(manifest.get("init"), "init", errors)
    require(init == "/sbin/init" or (isinstance(init, str) and init.startswith("/")), "init must be an absolute guest path", errors)

    root_disk = resolve_bundle_path(bundle_dir, manifest.get("root_disk"), "root_disk", errors)
    kernel = resolve_bundle_path(bundle_dir, manifest.get("kernel"), "kernel", errors)
    initramfs = optional_bundle_path(
        bundle_dir,
        manifest.get("initramfs"),
        manifest.get("initramfs_sha256"),
        "initramfs",
        errors,
    )
    validate_file_digest(root_disk, manifest, "root_disk_sha256", errors)
    validate_file_digest(kernel, manifest, "kernel_sha256", errors)
    validate_file_digest(initramfs, manifest, "initramfs_sha256", errors)

    root_size = validate_positive_int(manifest.get("root_disk_size_bytes"), "root_disk_size_bytes", errors)
    if root_disk is not None and root_size is not None:
        require(root_disk.stat().st_size == root_size, "root_disk_size_bytes does not match root_disk", errors)
        manifest_allocated_size = manifest.get("root_disk_allocated_bytes")
        if manifest_allocated_size is not None:
            require(
                isinstance(manifest_allocated_size, int)
                and not isinstance(manifest_allocated_size, bool)
                and manifest_allocated_size >= 0,
                "root_disk_allocated_bytes must be a non-negative integer or null",
                errors,
            )

    smoke_timeout = validate_positive_int(manifest.get("smoke_timeout_sec"), "smoke_timeout_sec", errors)
    if smoke_timeout is None:
        smoke_timeout = 30
    smoke_poweroff = manifest.get("smoke_poweroff_after_ready", True)
    require(isinstance(smoke_poweroff, bool), "smoke_poweroff_after_ready must be boolean", errors)
    smoke_wait = manifest.get("smoke_wait_exit_after_ready_sec")
    if smoke_wait is not None:
        validate_positive_int(smoke_wait, "smoke_wait_exit_after_ready_sec", errors)

    expected_markers = manifest.get("expected_markers", [])
    require(
        isinstance(expected_markers, list)
        and all(isinstance(marker, str) and marker for marker in expected_markers),
        "expected_markers must be a list of non-empty strings",
        errors,
    )
    expected_pid1 = single_kernel_token(manifest.get("expected_pid1"), "expected_pid1", errors, allow_null=True)
    if expected_pid1 == "init.krun":
        errors.append("expected_pid1 must not be init.krun")

    require_apfs_clone = manifest.get("require_apfs_clone", True)
    allow_full_copy_fallback = manifest.get("allow_full_copy_fallback", False)
    require(isinstance(require_apfs_clone, bool), "require_apfs_clone must be boolean", errors)
    require(isinstance(allow_full_copy_fallback, bool), "allow_full_copy_fallback must be boolean", errors)
    if allow_full_copy_fallback:
        errors.append("allow_full_copy_fallback=true is not accepted for the macOS product path yet")

    if errors:
        raise BundleError("\n".join(errors))

    return manifest


def choose_runtime(requested: str) -> str:
    candidates = SUPPORTED_RUNTIMES if requested == "auto" else (requested,)
    for runtime in candidates:
        if shutil.which(runtime):
            return runtime
    raise BundleError(
        "no supported container runtime found; install Docker or Podman, "
        "or use --bundle-dir with an already extracted bundle"
    )


def run_capture(command: list[str]) -> str:
    proc = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise BundleError(
            f"command failed: {command_quote(command)}\n{proc.stderr.strip()}"
        )
    return proc.stdout


def run(command: list[str]) -> None:
    proc = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise BundleError(
            f"command failed: {command_quote(command)}\n{proc.stderr.strip()}"
        )


def pull_image(runtime: str, image: str) -> None:
    run([runtime, "pull", image])


def import_metadata_path(output_dir: Path) -> Path:
    return output_dir / IMPORT_METADATA_FILE


def write_import_metadata(output_dir: Path, image: str, runtime: str, bundle_dir: Path) -> None:
    metadata = {
        "schema_version": 1,
        "image_reference": image,
        "runtime": runtime,
        "bundle_dir": str(bundle_dir),
        "bundle_dir_name": bundle_dir.name,
    }
    metadata_path = import_metadata_path(output_dir)
    if metadata_path.exists():
        raise BundleError(f"import metadata destination already exists: {metadata_path}")
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def reuse_existing_image_bundle(image: str, output_dir: Path) -> Path:
    if not output_dir.exists():
        raise BundleError(f"--output-dir does not exist for reuse: {output_dir}")
    if not output_dir.is_dir():
        raise BundleError(f"--output-dir exists and is not a directory: {output_dir}")

    bundle_dest = output_dir / "libkrun-os-bundle"
    if not bundle_dest.is_dir():
        raise BundleError(
            "--reuse-extracted-output-dir requires an existing libkrun-os-bundle directory"
        )

    metadata_path = import_metadata_path(output_dir)
    if not metadata_path.is_file():
        raise BundleError(
            f"--reuse-extracted-output-dir requires import metadata: {metadata_path}"
        )
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise BundleError(f"import metadata is invalid JSON: {err}") from err
    if not isinstance(metadata, dict):
        raise BundleError("import metadata must be a JSON object")
    if metadata.get("schema_version") != 1:
        raise BundleError("import metadata has unsupported schema_version")
    if metadata.get("image_reference") != image:
        raise BundleError("--reuse-extracted-output-dir image reference does not match metadata")
    if metadata.get("bundle_dir_name") != "libkrun-os-bundle":
        raise BundleError("import metadata bundle_dir_name is not libkrun-os-bundle")
    return bundle_dest


def extract_image_bundle(image: str, output_dir: Path, requested_runtime: str) -> Path:
    if output_dir.exists() and any(output_dir.iterdir()):
        raise BundleError(f"--output-dir already contains files: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    runtime = choose_runtime(requested_runtime)
    bundle_dest = output_dir / "libkrun-os-bundle"
    container_id = run_capture([runtime, "create", image, "true"]).strip()
    if not container_id:
        raise BundleError(f"{runtime} create did not return a container id")
    try:
        subprocess.run(
            [runtime, "cp", f"{container_id}:{BUNDLE_DIR_IN_IMAGE}", str(output_dir)],
            check=True,
        )
    except subprocess.CalledProcessError as err:
        raise BundleError(
            f"failed to copy {BUNDLE_DIR_IN_IMAGE} from {image}; "
            "the image is not a libkrun OS bundle"
        ) from err
    finally:
        subprocess.run([runtime, "rm", "-f", container_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    if not bundle_dest.is_dir():
        raise BundleError(f"extracted bundle directory does not exist: {bundle_dest}")
    write_import_metadata(output_dir, image, runtime, bundle_dest)
    return bundle_dest


def resolve_output_path(bundle_dir: Path, value: Path | None, default_name: str) -> Path:
    path = bundle_dir / default_name if value is None else value
    if not path.is_absolute():
        path = bundle_dir / path
    return path.expanduser().resolve()


def validate_output_candidate(option: str, path: Path, protected: dict[str, Path | None]) -> None:
    if not path.parent.is_dir():
        raise BundleError(f"{option} parent directory does not exist: {path.parent}")
    if path.exists():
        raise BundleError(f"{option} destination already exists: {path}")
    for label, protected_path in protected.items():
        if protected_path is not None and path == protected_path:
            raise BundleError(f"{option} must differ from {label}: {path}")


def apfs_info(path: Path) -> dict[str, Any]:
    if platform.system() != "Darwin":
        return {"checked": False, "reason": "not macOS", "is_apfs": None}

    try:
        df_result = subprocess.run(
            ["df", "-P", str(path)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        lines = [line for line in df_result.stdout.splitlines() if line.strip()]
        if len(lines) < 2:
            return {"checked": True, "reason": f"could not parse df output for {path}", "is_apfs": None}
        fields = lines[-1].split()
        device = fields[0]
        mount_point = fields[-1]
        mount_result = subprocess.run(
            ["mount"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as err:
        return {"checked": True, "reason": str(err), "is_apfs": None}

    filesystem = None
    for line in mount_result.stdout.splitlines():
        marker = f" on {mount_point} ("
        if marker not in line:
            continue
        filesystem = line.split(marker, 1)[1].split(",", 1)[0].rstrip(")")
        break

    return {
        "checked": True,
        "filesystem": filesystem,
        "is_apfs": filesystem == "apfs",
        "device": device,
        "mount_point": mount_point,
    }


def build_commands(
    bundle_dir: Path,
    manifest: dict[str, Any],
    clone_dest: Path,
    smoke_output: Path | None,
    perf_output: Path | None,
    *,
    require_launcher: bool = False,
) -> tuple[list[str], list[str], list[str], list[str] | None]:
    clone_helper = repo_file("examples/os_mode_apfs_clone.sh")
    os_mode = repo_file("examples/os_mode", require_exists=require_launcher)
    smoke_helper = repo_file("examples/os_mode_smoke.py")
    perf_helper = repo_file("examples/os_mode_perf.py")

    kernel = resolve_bundle_path(bundle_dir, manifest["kernel"], "kernel", [])
    root_disk = resolve_bundle_path(bundle_dir, manifest["root_disk"], "root_disk", [])
    initramfs = None
    if manifest.get("initramfs") is not None:
        initramfs = resolve_bundle_path(bundle_dir, manifest["initramfs"], "initramfs", [])

    assert kernel is not None
    assert root_disk is not None

    launch = [
        str(os_mode),
        "--kernel",
        str(kernel),
        "--kernel-format",
        str(manifest["kernel_format"]),
    ]
    if initramfs is not None:
        launch.extend(["--initramfs", str(initramfs)])
    launch.extend(
        [
            "--root-disk",
            str(clone_dest),
            "--root-device",
            manifest["root_device"],
            "--root-fstype",
            manifest["root_fstype"],
        ]
    )
    if manifest.get("root_options") is not None:
        launch.extend(["--root-options", manifest["root_options"]])
    launch.extend(["--guest-init", manifest["init"], "--console", manifest["console"]])

    smoke = [
        str(smoke_helper),
        "--timeout",
        str(manifest["smoke_timeout_sec"]),
    ]
    if manifest.get("smoke_wait_exit_after_ready_sec") is not None:
        smoke.extend(["--wait-exit-after-ready", str(manifest["smoke_wait_exit_after_ready_sec"])])
    if smoke_output is not None:
        smoke.extend(["--output", str(smoke_output)])
    smoke.extend(["--expect-root", manifest["expected_root"], "--expect-console", manifest["console"]])
    if manifest.get("expected_pid1") is not None:
        smoke.extend(["--expect-pid1", manifest["expected_pid1"]])
    for marker in manifest.get("expected_markers", []):
        smoke.extend(["--expect-marker", marker])
    smoke.append("--")
    smoke.extend(launch)
    if manifest.get("smoke_poweroff_after_ready", True):
        smoke.append("--poweroff-after-ready")

    perf = None
    if perf_output is not None:
        perf = [
            str(perf_helper),
            "--timeout",
            str(manifest["smoke_timeout_sec"]),
            "--output",
            str(perf_output),
            "--require-pid1-marker",
            "--expect-root",
            manifest["expected_root"],
            "--expect-console",
            manifest["console"],
            "--",
            *launch,
        ]

    clone = [str(clone_helper), str(root_disk), str(clone_dest)]
    return clone, launch, smoke, perf


def print_commands(
    clone: list[str],
    launch: list[str],
    smoke: list[str],
    perf: list[str] | None,
) -> None:
    print(f"apfs_clone_command: {command_quote(clone)}")
    print(f"os_mode_command: {command_quote(launch)}")
    print(f"smoke_command: {command_quote(smoke)}")
    if perf is not None:
        print(f"perf_command: {command_quote(perf)}")


def enrich_smoke_evidence(
    smoke_output: Path,
    *,
    bundle_dir: Path,
    manifest: dict[str, Any],
    clone_dest: Path,
    launch: list[str],
    clone: list[str],
    smoke: list[str],
    timings_ms: dict[str, int | None] | None = None,
    extraction_reused: bool = False,
    image_reference: str | None = None,
) -> None:
    if not smoke_output.is_file():
        raise BundleError(f"smoke evidence was not written: {smoke_output}")
    try:
        evidence = json.loads(smoke_output.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise BundleError(f"smoke evidence is invalid JSON: {err}") from err
    if not isinstance(evidence, dict):
        raise BundleError("smoke evidence must be a JSON object")
    if evidence.get("ready") is not True:
        raise BundleError("smoke evidence did not record ready=true")

    observed_root = evidence.get("observed_root")
    if observed_root != manifest["expected_root"]:
        raise BundleError(
            f"smoke evidence observed root {observed_root!r} does not match expected root {manifest['expected_root']!r}"
        )

    observed_consoles = evidence.get("observed_consoles")
    if not isinstance(observed_consoles, list) or manifest["console"] not in observed_consoles:
        raise BundleError(
            f"smoke evidence observed consoles {observed_consoles!r} do not include expected console {manifest['console']!r}"
        )

    observed_pid1 = evidence.get("observed_pid1")
    if observed_pid1 == "init.krun":
        raise BundleError("smoke evidence observed init.krun as PID 1")
    if manifest.get("expected_pid1") is not None and observed_pid1 != manifest["expected_pid1"]:
        raise BundleError(
            f"smoke evidence observed PID 1 {observed_pid1!r} does not match expected PID 1 {manifest['expected_pid1']!r}"
        )

    evidence["bundle"] = {
        "kind": manifest["kind"],
        "manifest_schema_version": manifest["manifest_schema_version"],
        "bundle_dir": str(bundle_dir),
        "source_image": manifest["source_image"],
        "source_digest": manifest.get("source_digest"),
        "platform": manifest["platform"],
        "root_disk": str(resolve_bundle_path(bundle_dir, manifest["root_disk"], "root_disk", [])),
        "root_disk_sha256": manifest["root_disk_sha256"],
        "root_disk_size_bytes": manifest["root_disk_size_bytes"],
        "root_disk_allocated_bytes": allocated_size_bytes(
            resolve_bundle_path(bundle_dir, manifest["root_disk"], "root_disk", [])
        ),
        "clone_dest": str(clone_dest),
        "expected_root": manifest["expected_root"],
        "expected_console": manifest["console"],
        "expected_pid1": manifest.get("expected_pid1"),
        "apfs_clone_command": clone,
        "os_mode_command": launch,
        "smoke_command": smoke,
        "timings_ms": timings_ms or {},
        "bundle_extraction_reused": extraction_reused,
        "imported_image": image_reference,
    }
    smoke_output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run_commands(
    clone: list[str],
    smoke: list[str],
    *,
    smoke_output: Path,
    bundle_dir: Path,
    manifest: dict[str, Any],
    clone_dest: Path,
    launch: list[str],
    image_pull_ms: int | None,
    extraction_ms: int | None,
    extraction_reused: bool,
    importer_started: float,
    image_reference: str | None,
) -> None:
    started = time.monotonic()
    clone_started = time.monotonic()
    clone_proc = subprocess.run(clone)
    clone_ms = int((time.monotonic() - clone_started) * 1000)
    if clone_proc.returncode != 0:
        raise BundleError(f"APFS clone command failed with status {clone_proc.returncode}")
    smoke_started = time.monotonic()
    proc = subprocess.run(smoke)
    smoke_ms = int((time.monotonic() - smoke_started) * 1000)
    if smoke_output.exists():
        enrich_smoke_evidence(
            smoke_output,
            bundle_dir=bundle_dir,
            manifest=manifest,
            clone_dest=clone_dest,
            launch=launch,
            clone=clone,
            smoke=smoke,
            timings_ms={
                "image_pull": image_pull_ms,
                "bundle_extraction": extraction_ms,
                "apfs_clone": clone_ms,
                "smoke": smoke_ms,
                "post_extraction_run": int((time.monotonic() - started) * 1000),
                "importer_total": int((time.monotonic() - importer_started) * 1000),
            },
            extraction_reused=extraction_reused,
            image_reference=image_reference,
        )
    if proc.returncode != 0:
        raise BundleError(f"smoke command failed with status {proc.returncode}")


def main() -> None:
    args = parse_args()
    try:
        importer_started = time.monotonic()
        image_pull_ms = None
        extraction_ms = None
        extraction_reused = False
        if args.image is not None:
            if args.output_dir is None:
                raise BundleError("--output-dir is required with --image")
            if args.strict_digest and not image_reference_is_digest_pinned(args.image):
                raise BundleError("--strict-digest with --image requires image@sha256:<digest>")
            output_dir = args.output_dir.expanduser().resolve()
            if args.reuse_extracted_output_dir and output_dir.exists() and any(output_dir.iterdir()):
                bundle_dir = reuse_existing_image_bundle(args.image, output_dir)
                extraction_ms = 0
                extraction_reused = True
            else:
                runtime = args.runtime
                if args.pull:
                    runtime = choose_runtime(args.runtime)
                    pull_started = time.monotonic()
                    pull_image(runtime, args.image)
                    image_pull_ms = int((time.monotonic() - pull_started) * 1000)
                extraction_started = time.monotonic()
                bundle_dir = extract_image_bundle(args.image, output_dir, runtime)
                extraction_ms = int((time.monotonic() - extraction_started) * 1000)
        else:
            if args.output_dir is not None:
                raise BundleError("--output-dir is only valid with --image")
            if args.reuse_extracted_output_dir:
                raise BundleError("--reuse-extracted-output-dir is only valid with --image")
            if args.pull:
                raise BundleError("--pull is only valid with --image")
            bundle_dir = args.bundle_dir.expanduser().resolve()

        if not bundle_dir.is_dir():
            raise BundleError(f"bundle directory does not exist: {bundle_dir}")

        manifest = validate_manifest(bundle_dir, strict_digest=args.strict_digest)

        clone_dest = resolve_output_path(bundle_dir, args.clone_dest, "vm-root.raw")
        smoke_output = (
            resolve_output_path(bundle_dir, args.smoke_output, "smoke.json")
            if args.smoke_output is not None or args.run
            else None
        )
        perf_output = (
            None
            if args.perf_output is None
            else resolve_output_path(bundle_dir, args.perf_output, "perf.json")
        )
        root_disk = resolve_bundle_path(bundle_dir, manifest["root_disk"], "root_disk", [])
        protected = {
            "manifest": (bundle_dir / "manifest.json").resolve(),
            "root_disk": root_disk,
        }
        validate_output_candidate("--clone-dest", clone_dest, protected)
        if smoke_output is not None:
            smoke_protected = dict(protected)
            smoke_protected["clone_dest"] = clone_dest
            validate_output_candidate("--smoke-output", smoke_output, smoke_protected)
        if perf_output is not None:
            perf_protected = dict(protected)
            perf_protected["clone_dest"] = clone_dest
            validate_output_candidate("--perf-output", perf_output, perf_protected)
            if smoke_output is not None and perf_output == smoke_output:
                raise BundleError("--perf-output must differ from --smoke-output")

        if args.require_apfs or args.run:
            info = apfs_info(bundle_dir)
            if info.get("is_apfs") is not True:
                raise BundleError(f"bundle directory must be on APFS for clone-backed launch: {info}")

        clone, launch, smoke, perf = build_commands(
            bundle_dir,
            manifest,
            clone_dest,
            smoke_output,
            perf_output,
            require_launcher=args.run,
        )
        print_commands(clone, launch, smoke, perf)
        if args.run:
            assert smoke_output is not None
            run_commands(
                clone,
                smoke,
                smoke_output=smoke_output,
                bundle_dir=bundle_dir,
                manifest=manifest,
                clone_dest=clone_dest,
                launch=launch,
                image_pull_ms=image_pull_ms,
                extraction_ms=extraction_ms,
                extraction_reused=extraction_reused,
                importer_started=importer_started,
                image_reference=args.image,
            )
    except BundleError as err:
        print(f"diagnostic_category={diagnostic_category(err)}", file=sys.stderr)
        print(err, file=sys.stderr)
        raise SystemExit(1) from err


if __name__ == "__main__":
    main()
