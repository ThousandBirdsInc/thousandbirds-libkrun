#!/usr/bin/env python3
"""Validate an os_mode_build_container_rootfs.py manifest."""

import argparse
import hashlib
import json
import re
import shlex
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


REQUIRED_FIELDS = (
    "manifest_schema_version",
    "created_at_utc",
    "builder",
    "builder_script_sha256",
    "builder_image",
    "builder_digest",
    "build_host",
    "runtime",
    "runtime_version",
    "source_image",
    "source_digest",
    "platform",
    "init_mode",
    "rootfs_tar",
    "rootfs_tar_sha256",
    "rootfs_tar_size_bytes",
    "root_disk",
    "root_disk_sha256",
    "root_disk_size_bytes",
    "root_disk_size_mb",
    "root_device",
    "expected_root",
    "root_fstype",
    "root_options",
    "disk_sync",
    "kernel",
    "kernel_format",
    "initramfs",
    "init",
    "timings_ms",
    "output_dir_apfs",
    "network_smoke",
    "smoke_timeout_sec",
    "smoke_poweroff_after_ready",
    "smoke_wait_exit_after_ready_sec",
    "expected_markers",
    "os_mode_command",
    "apfs_clone_command",
)

OS_MODE_OPTIONS_WITH_VALUES = (
    "--kernel",
    "--kernel-format",
    "--initramfs",
    "--root-disk",
    "--disk-sync",
    "--root-device",
    "--root-fstype",
    "--root-options",
    "--guest-init",
    "--console",
    "--kernel-cmdline",
)

SUPPORTED_PLATFORMS = ("linux/arm64", "linux/amd64")
SUPPORTED_RUNTIMES = ("docker", "podman")

PLATFORM_CONSOLES = {
    "linux/arm64": "ttyAMA0",
    "linux/amd64": "ttyS0",
}
REPO_ROOT = Path(__file__).resolve().parent.parent

SHA256_IDENTITY_RE = re.compile(r"^(?:(?:.+@)?sha256:)?[0-9a-fA-F]{64}$")
SYSTEMD_UNIT_RE = re.compile(r"^[A-Za-z0-9_.@:-]+\.(service|timer|socket|target|mount|path)$")


def non_empty_path_arg(value: str) -> Path:
    if value == "":
        raise argparse.ArgumentTypeError("path must be non-empty")
    return Path(value)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate the artifacts referenced by a libkrun OS-mode manifest."
    )
    parser.add_argument("manifest", type=Path)
    parser.add_argument(
        "--require-apfs",
        action="store_true",
        help="Require manifest output_dir_apfs.checked=true and is_apfs=true.",
    )
    parser.add_argument(
        "--check-kernel-paths",
        action="store_true",
        help="Require non-null kernel and initramfs paths in the manifest to exist.",
    )
    parser.add_argument(
        "--print-commands",
        action="store_true",
        help="After validation, print replayable APFS clone and os_mode launch commands.",
    )
    parser.add_argument(
        "--clone-dest",
        type=non_empty_path_arg,
        default=None,
        help=(
            "With --print-commands, override the APFS clone destination and "
            "printed os_mode --root-disk path. Relative paths resolve against "
            "the manifest directory."
        ),
    )
    parser.add_argument(
        "--smoke-output",
        type=non_empty_path_arg,
        default=None,
        help=(
            "With --print-commands, add os_mode_smoke.py --output PATH to the "
            "printed smoke command. Relative paths resolve against the manifest "
            "directory."
        ),
    )
    parser.add_argument(
        "--perf-output",
        type=non_empty_path_arg,
        default=None,
        help=(
            "With --print-commands, add an os_mode_perf.py command that writes "
            "timing JSON to PATH. Relative paths resolve against the manifest "
            "directory."
        ),
    )
    parser.add_argument(
        "--write-runbook",
        type=non_empty_path_arg,
        default=None,
        help=(
            "With --print-commands, write an executable shell script that runs "
            "the APFS clone command followed by the smoke command. Relative "
            "paths resolve against the manifest directory."
        ),
    )
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def manifest_path(manifest_dir: Path, value: Any) -> Path | None:
    if value is None:
        return None
    if not isinstance(value, str) or value == "":
        return None
    path = Path(value)
    if path.is_absolute():
        return path
    return manifest_dir / path


def manifest_path_string(manifest_dir: Path, value: Any) -> str | None:
    path = manifest_path(manifest_dir, value)
    if path is None:
        return None
    return str(path.expanduser().resolve())


def repo_path(value: Any) -> Path | None:
    if not isinstance(value, str) or value == "":
        return None
    path = Path(value)
    if path.is_absolute():
        return path.expanduser().resolve()
    return (REPO_ROOT / path).resolve()


def repo_path_string(value: Any) -> str | None:
    path = repo_path(value)
    if path is None:
        return None
    return str(path)


def required_repo_file_error(label: str, path: str | None) -> str | None:
    if path is None:
        return f"{label} path could not be resolved"
    if not Path(path).is_file():
        return f"{label} does not exist or is not a file: {path}"
    return None


def same_manifest_path(manifest_dir: Path, left: Any, right: Any) -> bool:
    left_path = manifest_path(manifest_dir, left)
    right_path = manifest_path(manifest_dir, right)
    if left_path is None or right_path is None:
        return False
    return left_path.expanduser().resolve() == right_path.expanduser().resolve()


def same_path(left: Path, right: Path) -> bool:
    return left.expanduser().resolve() == right.expanduser().resolve()


def output_path_conflict(
    path: Path,
    protected_paths: dict[str, Path | None],
) -> str | None:
    for label, protected_path in protected_paths.items():
        if protected_path is not None and same_path(path, protected_path):
            return label
    return None


def parent_dir_error(option: str, path: Path) -> str | None:
    parent = path.parent
    if not parent.is_dir():
        return f"{option} parent directory does not exist: {parent}"
    return None


def validate_output_candidate(option: str, path: Path) -> str | None:
    parent_error = parent_dir_error(option, path)
    if parent_error is not None:
        return parent_error
    if path.exists():
        return f"{option} destination already exists"
    return None


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def is_sha256_identity(value: Any) -> bool:
    return isinstance(value, str) and SHA256_IDENTITY_RE.fullmatch(value) is not None


def is_systemd_unit_name(value: Any) -> bool:
    return (
        isinstance(value, str)
        and value != ""
        and "/" not in value
        and not value.startswith(".")
        and SYSTEMD_UNIT_RE.fullmatch(value) is not None
    )


def is_single_kernel_cmdline_token(value: Any) -> bool:
    return isinstance(value, str) and value != "" and not any(char.isspace() for char in value)


def is_root_device_token(value: Any) -> bool:
    return is_single_kernel_cmdline_token(value) and (
        value.startswith("/dev/")
        or value.startswith("PARTUUID=")
        or value.startswith("UUID=")
    )


def is_positive_number(value: Any) -> bool:
    return (
        not isinstance(value, bool)
        and isinstance(value, (int, float))
        and value > 0
    )


def is_non_negative_integer(value: Any) -> bool:
    return not isinstance(value, bool) and isinstance(value, int) and value >= 0


def is_positive_integer(value: Any) -> bool:
    return not isinstance(value, bool) and isinstance(value, int) and value > 0


def is_utc_timestamp(value: Any) -> bool:
    if not isinstance(value, str) or value == "" or not value.endswith("Z"):
        return False
    try:
        datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError:
        return False
    return True


def format_seconds(value: int | float) -> str:
    if isinstance(value, int) or value.is_integer():
        return str(int(value))
    return str(value)


def command_value(command: list[Any], option: str) -> str | None:
    try:
        index = command.index(option)
    except ValueError:
        return None
    if index + 1 >= len(command):
        return None
    value = command[index + 1]
    return value if isinstance(value, str) else None


def set_command_value(command: list[str], option: str, value: str) -> None:
    command[command.index(option) + 1] = value


def command_option_count(command: list[Any], option: str) -> int:
    return sum(1 for item in command if item == option)


def command_option_value_error(command: list[Any], option: str) -> str | None:
    try:
        index = command.index(option)
    except ValueError:
        return None
    if index + 1 >= len(command):
        return f"os_mode_command option {option} requires a value"
    value = command[index + 1]
    if (
        not isinstance(value, str)
        or value == ""
        or value.startswith("--")
        or value in OS_MODE_OPTIONS_WITH_VALUES
    ):
        return f"os_mode_command option {option} requires a non-empty value"
    return None


def command_structure_errors(command: list[Any]) -> list[str]:
    errors: list[str] = []
    index = 1
    while index < len(command):
        item = command[index]
        if not isinstance(item, str):
            index += 1
            continue
        if item not in OS_MODE_OPTIONS_WITH_VALUES:
            errors.append(f"os_mode_command has unexpected argument: {item}")
            index += 1
            continue
        index += 2
    return errors


def validate_manifest(manifest_file: Path) -> tuple[dict[str, Any] | None, list[str]]:
    try:
        payload = json.loads(manifest_file.read_text(encoding="utf-8"))
    except OSError as err:
        return None, [f"could not read manifest: {err}"]
    except json.JSONDecodeError as err:
        return None, [f"manifest is not valid JSON: {err}"]

    if not isinstance(payload, dict):
        return None, ["manifest root must be a JSON object"]
    return payload, []


def check_manifest_payload(
    manifest: dict[str, Any],
    manifest_dir: Path,
    *,
    manifest_file: Path | None = None,
    require_apfs: bool = False,
    check_kernel_paths: bool = False,
) -> list[str]:
    errors: list[str] = []

    for field in REQUIRED_FIELDS:
        require(field in manifest, f"missing required field: {field}", errors)

    require(
        is_positive_integer(manifest.get("manifest_schema_version"))
        and manifest.get("manifest_schema_version") == 1,
        "manifest_schema_version must be 1",
        errors,
    )
    require(
        is_utc_timestamp(manifest.get("created_at_utc")),
        "created_at_utc must be an ISO 8601 UTC timestamp ending in Z",
        errors,
    )

    for field in (
        "builder",
        "builder_script_sha256",
        "builder_image",
        "builder_digest",
        "runtime",
        "runtime_version",
        "source_image",
        "source_digest",
        "platform",
    ):
        value = manifest.get(field)
        require(
            isinstance(value, str) and value != "",
            f"{field} must be a non-empty string",
            errors,
        )
    require(
        manifest.get("builder") == "examples/os_mode_build_container_rootfs.py",
        "builder must be examples/os_mode_build_container_rootfs.py",
        errors,
    )
    require(
        is_sha256_identity(manifest.get("builder_script_sha256")),
        "builder_script_sha256 must be <64 hex>, sha256:<64 hex>, or image@sha256:<64 hex>",
        errors,
    )
    require(
        manifest.get("runtime") in SUPPORTED_RUNTIMES,
        "runtime must be docker or podman",
        errors,
    )
    require(
        is_sha256_identity(manifest.get("source_digest")),
        "source_digest must be <64 hex>, sha256:<64 hex>, or image@sha256:<64 hex>",
        errors,
    )
    require(
        is_sha256_identity(manifest.get("builder_digest")),
        "builder_digest must be <64 hex>, sha256:<64 hex>, or image@sha256:<64 hex>",
        errors,
    )
    build_host = manifest.get("build_host")
    if not isinstance(build_host, dict):
        errors.append("build_host must be an object")
    else:
        for field in ("system", "release", "machine", "python_version"):
            value = build_host.get(field)
            require(
                isinstance(value, str) and value != "",
                f"build_host.{field} must be a non-empty string",
                errors,
            )

    rootfs_tar = manifest_path(manifest_dir, manifest.get("rootfs_tar"))
    root_disk = manifest_path(manifest_dir, manifest.get("root_disk"))
    overlay_tar = manifest_path(manifest_dir, manifest.get("overlay_tar"))

    for label, path, checksum_field, size_field in (
        ("rootfs_tar", rootfs_tar, "rootfs_tar_sha256", "rootfs_tar_size_bytes"),
        ("root_disk", root_disk, "root_disk_sha256", "root_disk_size_bytes"),
        ("overlay_tar", overlay_tar, "overlay_tar_sha256", "overlay_tar_size_bytes"),
    ):
        if path is None:
            if label != "overlay_tar":
                errors.append(f"{label} must be a non-empty path")
            else:
                require(
                    manifest.get(checksum_field) is None,
                    f"{checksum_field} must be null when overlay_tar is null",
                    errors,
                )
                require(
                    manifest.get(size_field) is None,
                    f"{size_field} must be null when overlay_tar is null",
                    errors,
                )
            continue
        if not path.is_file():
            errors.append(f"{label} does not exist or is not a file: {path}")
            continue
        expected = manifest.get(checksum_field)
        require(
            isinstance(expected, str) and expected != "",
            f"{checksum_field} must be a non-empty string",
            errors,
        )
        if not isinstance(expected, str) or expected == "":
            continue
        actual = sha256_file(path)
        require(
            actual == expected,
            f"{label} checksum mismatch: expected {expected}, got {actual}",
            errors,
        )
        expected_size = manifest.get(size_field)
        require(
            is_positive_integer(expected_size),
            f"{size_field} must be a positive integer",
            errors,
        )
        if is_positive_integer(expected_size):
            actual_size = path.stat().st_size
            require(
                actual_size == expected_size,
                f"{label} size mismatch: expected {expected_size}, got {actual_size}",
                errors,
            )

    root_disk_size_mb = manifest.get("root_disk_size_mb")
    require(
        is_positive_integer(root_disk_size_mb),
        "root_disk_size_mb must be a positive integer",
        errors,
    )
    root_disk_size_bytes = manifest.get("root_disk_size_bytes")
    if (
        is_positive_integer(root_disk_size_mb)
        and is_positive_integer(root_disk_size_bytes)
    ):
        expected_root_disk_bytes = root_disk_size_mb * 1024 * 1024
        require(
            root_disk_size_bytes == expected_root_disk_bytes,
            (
                "root_disk_size_bytes must equal root_disk_size_mb MiB: "
                f"expected {expected_root_disk_bytes}, got {root_disk_size_bytes}"
            ),
            errors,
        )

    require(manifest.get("init") == "/sbin/init", "init must be /sbin/init", errors)
    require(
        manifest.get("disk_sync") in ("relaxed", "full", "none"),
        "disk_sync must be relaxed, full, or none",
        errors,
    )
    require(
        manifest.get("init_mode") in ("inject-smoke", "validate-existing", "systemd"),
        "init_mode must be inject-smoke, validate-existing, or systemd",
        errors,
    )
    require(
        manifest.get("platform") in SUPPORTED_PLATFORMS,
        "platform must be linux/arm64 or linux/amd64",
        errors,
    )
    for field in (
        "require_dhcp_client",
        "network_smoke",
        "smoke_poweroff_after_ready",
        "systemd_default_masks",
        "systemd_serial_control_shell",
    ):
        if field in manifest:
            require(isinstance(manifest.get(field), bool), f"{field} must be boolean", errors)
    require(
        is_positive_number(manifest.get("smoke_timeout_sec")),
        "smoke_timeout_sec must be a positive number",
        errors,
    )
    smoke_wait_exit = manifest.get("smoke_wait_exit_after_ready_sec")
    require(
        smoke_wait_exit is None or is_positive_number(smoke_wait_exit),
        "smoke_wait_exit_after_ready_sec must be null or a positive number",
        errors,
    )
    expected_markers = manifest.get("expected_markers")
    if not isinstance(expected_markers, list):
        errors.append("expected_markers must be an array")
    else:
        for marker in expected_markers:
            require(
                isinstance(marker, str) and marker != "",
                f"expected_markers contains invalid marker: {marker}",
                errors,
            )
    if manifest.get("network_smoke") is True:
        require(
            manifest.get("require_dhcp_client") is True,
            "network_smoke requires require_dhcp_client=true",
            errors,
        )
        require(
            isinstance(expected_markers, list)
            and "KRUN_OSMODE: network=up" in expected_markers,
            "network_smoke requires expected marker KRUN_OSMODE: network=up",
            errors,
        )
    for field in ("systemd_masks", "systemd_effective_masks"):
        if field not in manifest:
            continue
        value = manifest.get(field)
        if not isinstance(value, list):
            errors.append(f"{field} must be an array")
            continue
        for unit in value:
            require(is_systemd_unit_name(unit), f"{field} contains invalid systemd unit name: {unit}", errors)
    for field in ("kernel", "initramfs"):
        value = manifest.get(field)
        require(
            value is None or (isinstance(value, str) and value != ""),
            f"{field} must be null or a non-empty string",
            errors,
        )
    kernel_format = manifest.get("kernel_format")
    require(
        not isinstance(kernel_format, bool)
        and isinstance(kernel_format, int)
        and 0 <= kernel_format <= 5,
        "kernel_format must be an integer from 0 through 5",
        errors,
    )
    require(
        is_root_device_token(manifest.get("root_device")),
        "root_device must be a single-token absolute /dev path, PARTUUID=..., or UUID=...",
        errors,
    )
    require(
        is_root_device_token(manifest.get("expected_root")),
        "expected_root must be a single-token absolute /dev path, PARTUUID=..., or UUID=...",
        errors,
    )
    require(
        is_single_kernel_cmdline_token(manifest.get("root_fstype")),
        "root_fstype must be a non-empty single token",
        errors,
    )
    root_options = manifest.get("root_options")
    require(
        root_options is None or is_single_kernel_cmdline_token(root_options),
        "root_options must be null or a non-empty single token",
        errors,
    )

    timings = manifest.get("timings_ms")
    if not isinstance(timings, dict):
        errors.append("timings_ms must be an object")
    else:
        for key in ("export_rootfs", "build_ext4", "total"):
            value = timings.get(key)
            require(
                is_non_negative_integer(value),
                f"timings_ms.{key} must be a non-negative integer",
                errors,
            )
        export_ms = timings.get("export_rootfs")
        build_ms = timings.get("build_ext4")
        total_ms = timings.get("total")
        if (
            is_non_negative_integer(export_ms)
            and is_non_negative_integer(build_ms)
            and is_non_negative_integer(total_ms)
        ):
            require(
                total_ms >= export_ms + build_ms,
                "timings_ms.total must be at least export_rootfs + build_ext4",
                errors,
            )

    output_apfs = manifest.get("output_dir_apfs")
    require(isinstance(output_apfs, dict), "output_dir_apfs must be an object", errors)
    if isinstance(output_apfs, dict):
        require(isinstance(output_apfs.get("checked"), bool), "output_dir_apfs.checked must be boolean", errors)
        if output_apfs.get("checked") is True:
            require(isinstance(output_apfs.get("is_apfs"), bool), "output_dir_apfs.is_apfs must be boolean when checked", errors)
            require(
                isinstance(output_apfs.get("filesystem"), str) and output_apfs["filesystem"] != "",
                "output_dir_apfs.filesystem must be a non-empty string when checked",
                errors,
            )
            require(
                isinstance(output_apfs.get("device"), str) and output_apfs["device"] != "",
                "output_dir_apfs.device must be a non-empty string when checked",
                errors,
            )
            require(
                isinstance(output_apfs.get("mount_point"), str) and output_apfs["mount_point"] != "",
                "output_dir_apfs.mount_point must be a non-empty string when checked",
                errors,
            )
        elif output_apfs.get("checked") is False:
            require(
                isinstance(output_apfs.get("reason"), str) and output_apfs["reason"] != "",
                "output_dir_apfs.reason must be a non-empty string when unchecked",
                errors,
            )

    os_mode_command = manifest.get("os_mode_command")
    if not isinstance(os_mode_command, list) or not os_mode_command:
        errors.append("os_mode_command must be a non-empty array")
    else:
        require(
            all(isinstance(item, str) for item in os_mode_command),
            "os_mode_command entries must all be strings",
            errors,
        )
        errors.extend(command_structure_errors(os_mode_command))
        for option in OS_MODE_OPTIONS_WITH_VALUES:
            require(
                command_option_count(os_mode_command, option) <= 1,
                f"os_mode_command must not repeat {option}",
                errors,
            )
            value_error = command_option_value_error(os_mode_command, option)
            if value_error:
                errors.append(value_error)
        require(
            os_mode_command[0] == "examples/os_mode",
            "os_mode_command must start with examples/os_mode",
            errors,
        )
        command_disk_sync = command_value(os_mode_command, "--disk-sync")
        require(command_disk_sync == manifest.get("disk_sync"), "os_mode_command disk sync mismatch", errors)
        command_kernel = command_value(os_mode_command, "--kernel")
        command_kernel_format = command_value(os_mode_command, "--kernel-format")
        command_initramfs = command_value(os_mode_command, "--initramfs")
        if manifest.get("kernel") is None:
            require(command_kernel is None, "os_mode_command kernel should be omitted", errors)
            require(
                command_kernel_format is None,
                "os_mode_command kernel format should be omitted when kernel is omitted",
                errors,
            )
        else:
            require(command_kernel == manifest.get("kernel"), "os_mode_command kernel mismatch", errors)
            require(
                command_kernel_format == str(manifest.get("kernel_format")),
                "os_mode_command kernel format mismatch",
                errors,
            )
        if manifest.get("initramfs") is None:
            require(command_initramfs is None, "os_mode_command initramfs should be omitted", errors)
        else:
            require(
                command_initramfs == manifest.get("initramfs"),
                "os_mode_command initramfs mismatch",
                errors,
            )
        require(
            command_value(os_mode_command, "--root-device") == manifest.get("root_device"),
            "os_mode_command root device mismatch",
            errors,
        )
        require(
            command_value(os_mode_command, "--root-fstype") == manifest.get("root_fstype"),
            "os_mode_command root filesystem mismatch",
            errors,
        )
        command_root_options = command_value(os_mode_command, "--root-options")
        if manifest.get("root_options") is None:
            require(command_root_options is None, "os_mode_command root options should be omitted", errors)
        else:
            require(
                command_root_options == manifest.get("root_options"),
                "os_mode_command root options mismatch",
                errors,
            )
        require(
            command_value(os_mode_command, "--guest-init") == "/sbin/init",
            "os_mode_command must set --guest-init /sbin/init",
            errors,
        )
        expected_console = PLATFORM_CONSOLES.get(manifest.get("platform"))
        if expected_console is not None:
            require(
                command_value(os_mode_command, "--console") == expected_console,
                f"os_mode_command must set --console {expected_console} for {manifest.get('platform')}",
                errors,
            )
        if manifest.get("init_mode") == "systemd":
            command_kernel_cmdline = command_value(os_mode_command, "--kernel-cmdline")
            require(
                command_kernel_cmdline is not None
                and "systemd.unit=multi-user.target" in command_kernel_cmdline.split(),
                "os_mode_command must set systemd.unit=multi-user.target for systemd init mode",
                errors,
            )
        if manifest.get("network_smoke") is True:
            command_kernel_cmdline = command_value(os_mode_command, "--kernel-cmdline")
            require(
                command_kernel_cmdline is not None
                and "KRUN_OSMODE_NET=1" in command_kernel_cmdline.split(),
                "os_mode_command must set KRUN_OSMODE_NET=1 for network smoke",
                errors,
            )

    apfs_clone_command = manifest.get("apfs_clone_command")
    if not isinstance(apfs_clone_command, list) or len(apfs_clone_command) != 3:
        errors.append("apfs_clone_command must be a three-item array")
    else:
        require(
            all(isinstance(item, str) for item in apfs_clone_command),
            "apfs_clone_command entries must all be strings",
            errors,
        )
        clone_source = apfs_clone_command[1]
        clone_dest = apfs_clone_command[2]
        require(
            apfs_clone_command[0] == "examples/os_mode_apfs_clone.sh",
            "apfs_clone_command must start with examples/os_mode_apfs_clone.sh",
            errors,
        )
        require(
            clone_source == manifest.get("root_disk"),
            "apfs_clone_command source must match root_disk",
            errors,
        )
        require(
            same_manifest_path(manifest_dir, clone_source, manifest.get("root_disk")),
            "apfs_clone_command source must resolve to root_disk",
            errors,
        )
        require(
            isinstance(clone_dest, str) and clone_dest != "",
            "apfs_clone_command destination must be a non-empty string",
            errors,
        )
        require(
            clone_dest != manifest.get("root_disk"),
            "apfs_clone_command destination must differ from root_disk",
            errors,
        )
        require(
            not same_manifest_path(manifest_dir, clone_dest, manifest.get("root_disk")),
            "apfs_clone_command destination must resolve differently from root_disk",
            errors,
        )
        for protected_label, protected_value in (
            ("rootfs_tar", manifest.get("rootfs_tar")),
            ("overlay_tar", manifest.get("overlay_tar")),
        ):
            if protected_value is not None:
                require(
                    not same_manifest_path(manifest_dir, clone_dest, protected_value),
                    f"apfs_clone_command destination must resolve differently from {protected_label}",
                    errors,
                )
        if manifest_file is not None:
            clone_dest_path = manifest_path(manifest_dir, clone_dest)
            if clone_dest_path is not None:
                require(
                    clone_dest_path.expanduser().resolve()
                    != manifest_file.expanduser().resolve(),
                    "apfs_clone_command destination must resolve differently from manifest",
                    errors,
                )
        if isinstance(os_mode_command, list):
            require(
                command_value(os_mode_command, "--root-disk") == clone_dest,
                "os_mode_command root disk must match apfs_clone_command destination",
                errors,
            )

    if require_apfs:
        if isinstance(output_apfs, dict):
            require(output_apfs.get("checked") is True, "output_dir_apfs.checked must be true", errors)
            require(output_apfs.get("is_apfs") is True, "output_dir_apfs.is_apfs must be true", errors)

    if check_kernel_paths:
        for field in ("kernel", "initramfs"):
            path = manifest_path(manifest_dir, manifest.get(field))
            if path is not None:
                require(path.is_file(), f"{field} does not exist or is not a file: {path}", errors)

    return errors


def main() -> int:
    args = parse_args()
    if args.clone_dest is not None and not args.print_commands:
        print("--clone-dest requires --print-commands", file=sys.stderr)
        return 2
    if args.smoke_output is not None and not args.print_commands:
        print("--smoke-output requires --print-commands", file=sys.stderr)
        return 2
    if args.perf_output is not None and not args.print_commands:
        print("--perf-output requires --print-commands", file=sys.stderr)
        return 2
    if args.write_runbook is not None and not args.print_commands:
        print("--write-runbook requires --print-commands", file=sys.stderr)
        return 2

    manifest_file = args.manifest
    manifest_dir = manifest_file.parent
    manifest, errors = validate_manifest(manifest_file)
    if manifest is None:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    errors = check_manifest_payload(
        manifest,
        manifest_dir,
        manifest_file=manifest_file,
        require_apfs=args.require_apfs,
        check_kernel_paths=args.check_kernel_paths or args.print_commands,
    )
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(f"manifest ok: {manifest_file}")
    if args.print_commands:
        apfs_clone_command = list(manifest["apfs_clone_command"])
        os_mode_command = list(manifest["os_mode_command"])
        apfs_clone_helper = repo_path_string(apfs_clone_command[0])
        os_mode_binary = repo_path_string(os_mode_command[0])
        if apfs_clone_helper is not None:
            apfs_clone_command[0] = apfs_clone_helper
        if os_mode_binary is not None:
            os_mode_command[0] = os_mode_binary
        smoke_command = []
        smoke_helper = repo_path_string("examples/os_mode_smoke.py")
        if smoke_helper is not None:
            smoke_command = [smoke_helper]
        perf_command = []
        perf_helper = repo_path_string("examples/os_mode_perf.py")
        if perf_helper is not None:
            perf_command = [perf_helper]
        for label, helper_path in (
            ("apfs_clone_helper", apfs_clone_helper),
            ("smoke_helper", smoke_helper),
        ):
            helper_error = required_repo_file_error(label, helper_path)
            if helper_error is not None:
                print(helper_error, file=sys.stderr)
                return 1
        if args.perf_output is not None:
            perf_helper_error = required_repo_file_error("perf_helper", perf_helper)
            if perf_helper_error is not None:
                print(perf_helper_error, file=sys.stderr)
                return 1
        clone_source = manifest_path_string(manifest_dir, apfs_clone_command[1])
        clone_dest = manifest_path_string(manifest_dir, apfs_clone_command[2])
        if clone_source is not None:
            apfs_clone_command[1] = clone_source
        if clone_dest is not None:
            apfs_clone_command[2] = clone_dest
            set_command_value(os_mode_command, "--root-disk", clone_dest)
        for option in ("--kernel", "--initramfs"):
            value = command_value(os_mode_command, option)
            resolved = manifest_path_string(manifest_dir, value)
            if resolved is not None:
                set_command_value(os_mode_command, option, resolved)
        if args.clone_dest is not None:
            clone_dest = args.clone_dest.expanduser()
            if not clone_dest.is_absolute():
                clone_dest = (manifest_dir / clone_dest).resolve()
            root_disk = manifest_path(manifest_dir, manifest.get("root_disk"))
            if root_disk is not None and clone_dest == root_disk.expanduser().resolve():
                print("--clone-dest must differ from root_disk", file=sys.stderr)
                return 1
            clone_dest_error = validate_output_candidate("--clone-dest", clone_dest)
            if clone_dest_error is not None:
                print(clone_dest_error, file=sys.stderr)
                return 1
            apfs_clone_command[2] = str(clone_dest)
            set_command_value(os_mode_command, "--root-disk", str(clone_dest))
        else:
            current_clone_dest = Path(apfs_clone_command[2]).expanduser()
            if not current_clone_dest.is_absolute():
                current_clone_dest = (manifest_dir / current_clone_dest).resolve()
            clone_dest_error = validate_output_candidate(
                "apfs_clone_command", current_clone_dest
            )
            if clone_dest_error is not None:
                print(clone_dest_error, file=sys.stderr)
                return 1
        protected_output_paths = {
            "manifest": manifest_file,
            "rootfs_tar": manifest_path(manifest_dir, manifest.get("rootfs_tar")),
            "root_disk": manifest_path(manifest_dir, manifest.get("root_disk")),
            "overlay_tar": manifest_path(manifest_dir, manifest.get("overlay_tar")),
            "clone_destination": Path(apfs_clone_command[2]),
        }
        expected_console = command_value(os_mode_command, "--console")
        expected_root = manifest.get("expected_root")
        smoke_timeout = manifest.get("smoke_timeout_sec")
        if is_positive_number(smoke_timeout):
            smoke_command.extend(["--timeout", format_seconds(smoke_timeout)])
            perf_command.extend(["--timeout", format_seconds(smoke_timeout)])
        smoke_wait_exit = manifest.get("smoke_wait_exit_after_ready_sec")
        if is_positive_number(smoke_wait_exit):
            smoke_command.extend(
                ["--wait-exit-after-ready", format_seconds(smoke_wait_exit)]
            )
        if args.smoke_output is not None:
            smoke_output = args.smoke_output.expanduser()
            if not smoke_output.is_absolute():
                smoke_output = (manifest_dir / smoke_output).resolve()
            smoke_conflict = output_path_conflict(smoke_output, protected_output_paths)
            if smoke_conflict is not None:
                print(f"--smoke-output must differ from {smoke_conflict}", file=sys.stderr)
                return 1
            smoke_output_error = validate_output_candidate("--smoke-output", smoke_output)
            if smoke_output_error is not None:
                print(smoke_output_error, file=sys.stderr)
                return 1
            smoke_command.extend(["--output", str(smoke_output)])
        perf_output = None
        if args.perf_output is not None:
            perf_output = args.perf_output.expanduser()
            if not perf_output.is_absolute():
                perf_output = (manifest_dir / perf_output).resolve()
            perf_conflict = output_path_conflict(perf_output, protected_output_paths)
            if perf_conflict is not None:
                print(f"--perf-output must differ from {perf_conflict}", file=sys.stderr)
                return 1
            if args.smoke_output is not None and same_path(perf_output, smoke_output):
                print("--perf-output must differ from --smoke-output", file=sys.stderr)
                return 1
            perf_output_error = validate_output_candidate("--perf-output", perf_output)
            if perf_output_error is not None:
                print(perf_output_error, file=sys.stderr)
                return 1
            perf_command.extend(["--output", str(perf_output)])
            perf_command.append("--require-pid1-marker")
        if isinstance(expected_root, str):
            smoke_command.extend(["--expect-root", expected_root])
            perf_command.extend(["--expect-root", expected_root])
        if expected_console is not None:
            smoke_command.extend(["--expect-console", expected_console])
            perf_command.extend(["--expect-console", expected_console])
        for marker in manifest.get("expected_markers", []):
            smoke_command.extend(["--expect-marker", marker])
        perf_command.extend(["--", *os_mode_command])
        smoke_os_mode_command = list(os_mode_command)
        if manifest.get("smoke_poweroff_after_ready") is True:
            smoke_os_mode_command.append("--poweroff-after-ready")
        smoke_command.extend(["--", *smoke_os_mode_command])
        print(f"apfs_clone_command: {shlex.join(apfs_clone_command)}")
        print(f"os_mode_command: {shlex.join(os_mode_command)}")
        print(f"smoke_command: {shlex.join(smoke_command)}")
        if args.perf_output is not None:
            print(f"perf_command: {shlex.join(perf_command)}")
        if args.write_runbook is not None:
            runbook = args.write_runbook.expanduser()
            if not runbook.is_absolute():
                runbook = (manifest_dir / runbook).resolve()
            runbook_conflict = output_path_conflict(runbook, protected_output_paths)
            if runbook_conflict is not None:
                print(f"--write-runbook must differ from {runbook_conflict}", file=sys.stderr)
                return 1
            if args.smoke_output is not None and same_path(runbook, smoke_output):
                print("--write-runbook must differ from --smoke-output", file=sys.stderr)
                return 1
            if perf_output is not None and same_path(runbook, perf_output):
                print("--write-runbook must differ from --perf-output", file=sys.stderr)
                return 1
            runbook_error = validate_output_candidate("--write-runbook", runbook)
            if runbook_error is not None:
                print(runbook_error, file=sys.stderr)
                return 1
            runbook_commands = [
                shlex.join(apfs_clone_command),
                shlex.join(smoke_command),
            ]
            if args.perf_output is not None:
                runbook_commands.append(shlex.join(perf_command))
            runbook.write_text(
                "\n".join(
                    [
                        "#!/bin/sh",
                        "set -eu",
                        "",
                        *runbook_commands,
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            runbook.chmod(0o755)
            print(f"runbook: {runbook}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
