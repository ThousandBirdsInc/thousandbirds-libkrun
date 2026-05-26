#!/usr/bin/env python3
"""Build an OS-mode root disk from an OCI/container image.

This helper is intended for macOS hosts. Docker or Podman is used only as a
Linux filesystem build/export environment; the generated raw disk is later run
by libkrun OS mode on the macOS host.
"""

import argparse
import hashlib
import json
import platform
import re
import shutil
import subprocess
import sys
import time
import uuid
from datetime import UTC, datetime
from pathlib import Path

from os_mode_manifest_check import check_manifest_payload


DEFAULT_BUILDER_IMAGE = "alpine:3.23"
DEFAULT_PLATFORM = "linux/arm64"
SUPPORTED_PLATFORMS = ("linux/arm64", "linux/amd64")
PLATFORM_CONSOLES = {
    "linux/arm64": "ttyAMA0",
    "linux/amd64": "ttyS0",
}
PLATFORM_KERNEL_FORMATS = {
    "linux/arm64": 2,  # KRUN_KERNEL_FORMAT_PE_GZ
    "linux/amd64": 1,  # KRUN_KERNEL_FORMAT_ELF
}
DEFAULT_ROOT_DEVICE = "/dev/vda"
DEFAULT_ROOT_FSTYPE = "ext4"
DEFAULT_SYSTEMD_MASKS = (
    "systemd-logind.service",
    "apt-daily.timer",
    "apt-daily-upgrade.timer",
    "dpkg-db-backup.timer",
    "e2scrub_all.timer",
)
SYSTEMD_UNIT_RE = re.compile(r"^[A-Za-z0-9_.@:-]+\.(service|timer|socket|target|mount|path)$")


BUILDER_SCRIPT = r"""
set -eu

apk add --no-cache e2fsprogs tar coreutils

rm -rf /build/rootfs
mkdir -p /build/rootfs
tar -xpf /work/rootfs.tar -C /build/rootfs
if [ -f /work/overlay.tar ]; then
    tar -xpf /work/overlay.tar -C /build/rootfs
fi

mkdir -p \
  /build/rootfs/dev \
  /build/rootfs/proc \
  /build/rootfs/sys \
  /build/rootfs/run \
  /build/rootfs/tmp \
  /build/rootfs/sbin \
  /build/rootfs/usr/local/libexec
chmod 1777 /build/rootfs/tmp

cat > /build/rootfs/usr/local/libexec/krun-osmode-ready <<'EOF'
#!/bin/sh
echo "KRUN_OSMODE: init-started"
root_source=$(awk '$2 == "/" {print $1 " " $3 " " $4}' /proc/mounts 2>/dev/null || true)
echo "KRUN_OSMODE: root=${root_source}"
pid1_comm=$(cat /proc/1/comm 2>/dev/null || true)
pid1_exe=$(readlink /proc/1/exe 2>/dev/null || true)
echo "KRUN_OSMODE: pid1=${pid1_comm} ${pid1_exe}"
echo "KRUN_OSMODE: console=$(cat /sys/class/tty/console/active 2>/dev/null || true)"

net_requested=${KRUN_OSMODE_NET:-0}
if grep -qw 'KRUN_OSMODE_NET=1' /proc/cmdline 2>/dev/null; then
    net_requested=1
fi
write_requested=${KRUN_OSMODE_WRITE_TEST:-0}
if grep -qw 'KRUN_OSMODE_WRITE_TEST=1' /proc/cmdline 2>/dev/null; then
    write_requested=1
fi
apt_update_requested=${KRUN_OSMODE_APT_UPDATE:-0}
if grep -qw 'KRUN_OSMODE_APT_UPDATE=1' /proc/cmdline 2>/dev/null; then
    apt_update_requested=1
fi

if [ "$net_requested" = "1" ]; then
    for mod in failover net_failover af_packet virtio_net; do
        for path in /lib/modules/*/*/"$mod".ko /lib/modules/*/*/*/"$mod".ko /lib/modules/*/*/*/*/"$mod".ko; do
            [ -f "$path" ] || continue
            insmod "$path" 2>/dev/null || true
        done
    done

    iface=${KRUN_OSMODE_NET_IFACE:-}
    ifaces=""
    for net_path in /sys/class/net/*; do
        name=${net_path##*/}
        ifaces="${ifaces}${name},"
        if [ -z "$iface" ] && [ "$name" != "lo" ]; then
            iface=$name
        fi
    done
    echo "KRUN_OSMODE: ifaces=${ifaces}"

    if [ -z "$iface" ]; then
        echo "KRUN_OSMODE: network=missing-interface"
    elif command -v ip >/dev/null 2>&1; then
        ip link set "$iface" up 2>/dev/null || true
        ip -o link show "$iface" 2>/dev/null | sed 's/^/KRUN_OSMODE: link-before-dhcp=/' || true
    elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig "$iface" up 2>/dev/null || true
    fi

    if [ -z "$iface" ]; then
        :
    elif command -v udhcpc >/dev/null 2>&1; then
        if udhcpc -i "$iface" -q -t 3 2>&1; then
            echo "KRUN_OSMODE: network=up"
        else
            echo "KRUN_OSMODE: network=down"
        fi
    elif command -v dhclient >/dev/null 2>&1; then
        if dhclient -4 -1 -v \
          -pf "/run/dhclient.${iface}.pid" \
          -lf "/run/dhclient.${iface}.leases" \
          "$iface" 2>&1; then
            echo "KRUN_OSMODE: network=up"
        else
            echo "KRUN_OSMODE: network=down"
        fi
    elif command -v dhcpcd >/dev/null 2>&1; then
        if dhcpcd -4 -w "$iface" 2>&1; then
            echo "KRUN_OSMODE: network=up"
        else
            echo "KRUN_OSMODE: network=down"
        fi
    else
        echo "KRUN_OSMODE: network=missing-dhcp-client"
    fi
    if command -v ip >/dev/null 2>&1 && [ -n "$iface" ]; then
        ip -o addr show "$iface" 2>/dev/null | sed 's/^/KRUN_OSMODE: addr-after-dhcp=/' || true
    fi
else
    echo "KRUN_OSMODE: network=skipped"
fi

if [ "$write_requested" = "1" ]; then
    boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)
    write_dir=/var/lib/krun-osmode/write-test
    write_file="$write_dir/$boot_id.txt"
    mkdir -p "$write_dir"
    if {
        echo "boot_id=$boot_id"
        echo "pid1=$(cat /proc/1/comm 2>/dev/null || true)"
        date -u 2>/dev/null || true
    } > "$write_file"; then
        sync
        echo "KRUN_OSMODE: write=ok path=$write_file"
    else
        echo "KRUN_OSMODE: write=failed path=$write_file"
    fi

    if command -v logger >/dev/null 2>&1 && command -v journalctl >/dev/null 2>&1; then
        journal_marker="krun-osmode-journal-write-$boot_id"
        logger -t krun-osmode "$journal_marker" || true
        journalctl --sync >/dev/null 2>&1 || true
        if journalctl -t krun-osmode --no-pager -n 50 2>/dev/null | grep -q "$journal_marker"; then
            echo "KRUN_OSMODE: journald=ok"
        else
            echo "KRUN_OSMODE: journald=down"
        fi
    else
        echo "KRUN_OSMODE: journald=missing-tools"
    fi
fi

if [ "$apt_update_requested" = "1" ]; then
    if command -v apt-get >/dev/null 2>&1; then
        if DEBIAN_FRONTEND=noninteractive apt-get update -o Acquire::Retries=1; then
            apt_lists_kib=$(du -sk /var/lib/apt/lists 2>/dev/null | awk '{print $1}' || true)
            echo "KRUN_OSMODE: package-manager=apt-update-ok lists_kib=${apt_lists_kib}"
        else
            echo "KRUN_OSMODE: package-manager=apt-update-failed"
        fi
    else
        echo "KRUN_OSMODE: package-manager=missing-apt-get"
    fi
fi

echo "KRUN_OSMODE: ready"

if grep -qw 'KRUN_OSMODE_POWEROFF=1' /proc/cmdline 2>/dev/null; then
    if [ "$(cat /proc/1/comm 2>/dev/null || true)" = "systemd" ] && command -v systemctl >/dev/null 2>&1; then
        systemctl --no-block poweroff || poweroff -f
    else
        poweroff -f
    fi
fi
EOF
chmod 0755 /build/rootfs/usr/local/libexec/krun-osmode-ready

if [ "${REQUIRE_DHCP_CLIENT:-0}" = "1" ]; then
    found_dhcp=0
    for path in \
      /build/rootfs/sbin/udhcpc \
      /build/rootfs/usr/sbin/udhcpc \
      /build/rootfs/bin/udhcpc \
      /build/rootfs/usr/bin/udhcpc \
      /build/rootfs/sbin/dhclient \
      /build/rootfs/usr/sbin/dhclient \
      /build/rootfs/sbin/dhcpcd \
      /build/rootfs/usr/sbin/dhcpcd; do
        if [ -x "$path" ]; then
            found_dhcp=1
            break
        fi
    done
    if [ "$found_dhcp" != "1" ]; then
        echo "networking was requested but no supported DHCP client was found in the rootfs" >&2
        echo "expected udhcpc, dhclient, or dhcpcd in a standard PATH directory" >&2
        exit 65
    fi
fi

rootfs_path_exists() {
    path="/build/rootfs$1"
    [ -e "$path" ] || [ -L "$path" ]
}

rootfs_executable() {
    path="/build/rootfs$1"
    if [ -x "$path" ]; then
        return 0
    fi
    if [ -L "$path" ]; then
        target=$(readlink "$path")
        case "$target" in
          /*) [ -x "/build/rootfs$target" ] && return 0 ;;
          *) [ -x "$(dirname "$path")/$target" ] && return 0 ;;
        esac
    fi
    return 1
}

case "$INIT_MODE" in
  inject-smoke)
    rm -f /build/rootfs/sbin/init
    cat > /build/rootfs/sbin/init <<'EOF'
#!/bin/sh
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t tmpfs tmpfs /run 2>/dev/null || true

if [ "${KRUN_OSMODE_NET:-0}" = "1" ]; then
    for mod in failover net_failover af_packet virtio_net; do
        for path in /lib/modules/*/*/"$mod".ko /lib/modules/*/*/*/"$mod".ko /lib/modules/*/*/*/*/"$mod".ko; do
            [ -f "$path" ] || continue
            insmod "$path" 2>/dev/null || true
        done
    done
fi

/usr/local/libexec/krun-osmode-ready

if [ -c /dev/console ]; then
    exec /bin/sh </dev/console >/dev/console 2>&1
fi
exec /bin/sh
EOF
    chmod 0755 /build/rootfs/sbin/init
    ;;
  validate-existing)
    if ! rootfs_executable /sbin/init; then
        echo "rootfs does not contain executable /sbin/init" >&2
        exit 64
    fi
    ;;
  systemd)
    if [ ! -x /build/rootfs/lib/systemd/systemd ] && [ ! -x /build/rootfs/usr/lib/systemd/systemd ]; then
        echo "rootfs does not contain executable systemd" >&2
        exit 64
    fi
    if ! rootfs_path_exists /sbin/init; then
        ln -s ../lib/systemd/systemd /build/rootfs/sbin/init
    fi
    if ! rootfs_executable /sbin/init; then
        echo "rootfs /sbin/init is not executable" >&2
        exit 64
    fi

    mkdir -p \
      /build/rootfs/etc/systemd/system/multi-user.target.wants \
      /build/rootfs/etc/systemd/system/getty.target.wants \
      /build/rootfs/etc/modules-load.d
    cat > /build/rootfs/etc/systemd/system/krun-osmode-ready.service <<'EOF'
[Unit]
Description=libkrun OS-mode readiness marker
After=local-fs.target systemd-udev-settle.service
Wants=systemd-udev-settle.service

[Service]
Type=oneshot
ExecStartPre=/bin/mount -o remount,rw /
ExecStart=/usr/local/libexec/krun-osmode-ready
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    ln -sf ../krun-osmode-ready.service \
      /build/rootfs/etc/systemd/system/multi-user.target.wants/krun-osmode-ready.service
    if [ -f /build/rootfs/lib/systemd/system/serial-getty@.service ] || \
       [ -f /build/rootfs/usr/lib/systemd/system/serial-getty@.service ]; then
        if [ "${ENABLE_SYSTEMD_SERIAL_CONTROL:-0}" != "1" ]; then
            ln -sf /lib/systemd/system/serial-getty@.service \
              "/build/rootfs/etc/systemd/system/getty.target.wants/serial-getty@${SERIAL_CONSOLE}.service"
        fi
    fi
    if [ "${ENABLE_SYSTEMD_SERIAL_CONTROL:-0}" = "1" ]; then
        cat > /build/rootfs/etc/systemd/system/krun-osmode-serial-control.service <<EOF
[Unit]
Description=libkrun OS-mode validation serial control shell
After=krun-osmode-ready.service
Conflicts=console-getty.service serial-getty@${SERIAL_CONSOLE}.service

[Service]
Type=simple
ExecStart=/bin/sh -i
StandardInput=tty
StandardOutput=tty
StandardError=tty
TTYPath=/dev/${SERIAL_CONSOLE}
TTYReset=yes
TTYVHangup=no
Restart=no

[Install]
WantedBy=multi-user.target
EOF
        ln -sf ../krun-osmode-serial-control.service \
          /build/rootfs/etc/systemd/system/multi-user.target.wants/krun-osmode-serial-control.service
        ln -sf /dev/null \
          "/build/rootfs/etc/systemd/system/serial-getty@${SERIAL_CONSOLE}.service"
        ln -sf /dev/null \
          /build/rootfs/etc/systemd/system/console-getty.service
    fi
    systemd_masks=""
    if [ "${USE_DEFAULT_SYSTEMD_MASKS:-1}" = "1" ]; then
        systemd_masks="$systemd_masks systemd-logind.service apt-daily.timer apt-daily-upgrade.timer dpkg-db-backup.timer e2scrub_all.timer"
    fi
    systemd_masks="$systemd_masks ${SYSTEMD_MASKS:-}"
    for unit in $systemd_masks; do
        [ -n "$unit" ] || continue
        ln -sf /dev/null "/build/rootfs/etc/systemd/system/$unit"
    done
    cat > /build/rootfs/etc/modules-load.d/krun-osmode.conf <<'EOF'
failover
net_failover
af_packet
virtio_net
EOF
    : > /build/rootfs/etc/machine-id
    ;;
  *)
    echo "unsupported INIT_MODE: $INIT_MODE" >&2
    exit 64
    ;;
esac

rm -f /work/root.raw.tmp
truncate -s "${SIZE_MB}M" /work/root.raw.tmp
mkfs.ext4 -F -q -L KRUNROOT -d /build/rootfs /work/root.raw.tmp
mv /work/root.raw.tmp /work/root.raw
"""


def positive_size_mb(value: str) -> int:
    try:
        parsed = int(value, 10)
    except ValueError as err:
        raise argparse.ArgumentTypeError("size must be an integer") from err
    if parsed <= 0:
        raise argparse.ArgumentTypeError("size must be greater than zero")
    return parsed


def positive_float(value: str) -> float:
    try:
        parsed = float(value)
    except ValueError as err:
        raise argparse.ArgumentTypeError("value must be a number") from err
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be greater than zero")
    return parsed


def non_empty_arg(value: str) -> str:
    if value == "":
        raise argparse.ArgumentTypeError("value must be non-empty")
    return value


def non_empty_path(value: str) -> Path:
    if value == "":
        raise argparse.ArgumentTypeError("path must be non-empty")
    return Path(value)


def single_kernel_cmdline_token(value: str) -> str:
    if value == "" or any(char.isspace() for char in value):
        raise argparse.ArgumentTypeError("value must be a non-empty single kernel command-line token")
    return value


def root_device_arg(value: str) -> str:
    value = single_kernel_cmdline_token(value)
    if not (
        value.startswith("/dev/")
        or value.startswith("PARTUUID=")
        or value.startswith("UUID=")
    ):
        raise argparse.ArgumentTypeError(
            "root device must be an absolute /dev path, PARTUUID=..., or UUID=..."
        )
    return value


def validate_systemd_unit_names(units: list[str]) -> list[str]:
    errors = []
    for unit in units:
        if not isinstance(unit, str) or unit == "":
            errors.append("systemd unit names must be non-empty strings")
        elif "/" in unit or unit.startswith(".") or not SYSTEMD_UNIT_RE.fullmatch(unit):
            errors.append(f"invalid systemd unit name: {unit}")
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a libkrun OS-mode raw ext4 root disk from an OCI image."
    )
    parser.add_argument("--image", required=True, type=non_empty_arg, help="OCI image reference to export.")
    parser.add_argument(
        "--output-dir",
        required=True,
        type=non_empty_path,
        help="Directory that will receive rootfs.tar, root.raw, and manifest.json.",
    )
    parser.add_argument(
        "--runtime",
        choices=("auto", "podman", "docker"),
        default="auto",
        help="Container runtime used for export/build steps.",
    )
    parser.add_argument("--platform", choices=SUPPORTED_PLATFORMS, default=DEFAULT_PLATFORM)
    parser.add_argument("--builder-image", type=non_empty_arg, default=DEFAULT_BUILDER_IMAGE)
    parser.add_argument("--size-mb", type=positive_size_mb, default=512)
    parser.add_argument(
        "--init-mode",
        choices=("inject-smoke", "validate-existing", "systemd"),
        default="inject-smoke",
        help="Whether to inject a smoke /sbin/init, require the image's init, or configure systemd.",
    )
    parser.add_argument("--kernel", type=non_empty_path, default=None, help="Optional kernel path for manifest command.")
    parser.add_argument(
        "--kernel-format",
        type=int,
        choices=range(0, 6),
        default=None,
        metavar="N",
        help=(
            "KRUN_KERNEL_FORMAT_* value for the generated os_mode command. "
            "Defaults to the platform-specific os_mode example default."
        ),
    )
    parser.add_argument(
        "--initramfs", type=non_empty_path, default=None, help="Optional initramfs path for manifest command."
    )
    parser.add_argument("--root-device", type=root_device_arg, default=DEFAULT_ROOT_DEVICE)
    parser.add_argument(
        "--expected-root",
        type=root_device_arg,
        default=None,
        help=(
            "Root source value expected in KRUN_OSMODE: root= smoke output. "
            "Defaults to --root-device; override when a stable root token "
            "resolves to a different /proc/mounts source."
        ),
    )
    parser.add_argument("--root-fstype", type=single_kernel_cmdline_token, default=DEFAULT_ROOT_FSTYPE)
    parser.add_argument(
        "--root-options",
        type=single_kernel_cmdline_token,
        default=None,
        help="Optional comma-separated root mount options for the generated os_mode command.",
    )
    parser.add_argument(
        "--disk-sync",
        choices=("relaxed", "full", "none"),
        default="relaxed",
        help="Root disk sync mode to include in the generated os_mode command.",
    )
    parser.add_argument(
        "--overlay-tar",
        type=non_empty_path,
        default=None,
        help="Optional tar archive extracted over the exported rootfs before packing.",
    )
    parser.add_argument(
        "--require-dhcp-client",
        action="store_true",
        help="Fail the build unless the rootfs contains a DHCP client usable by the smoke init.",
    )
    parser.add_argument(
        "--network-smoke",
        action="store_true",
        help=(
            "Generate a launch command that requests guest DHCP/network "
            "readiness markers and require DHCP tooling during image build."
        ),
    )
    parser.add_argument(
        "--smoke-timeout",
        type=positive_float,
        default=None,
        help=(
            "Recommended os_mode_smoke.py timeout in seconds for manifest "
            "replay commands. Defaults to 120 for systemd, 45 for network "
            "smoke, and 30 otherwise."
        ),
    )
    parser.add_argument(
        "--no-smoke-poweroff-after-ready",
        action="store_true",
        help=(
            "Do not ask replayed smoke commands to append the validation-only "
            "guest poweroff marker after readiness."
        ),
    )
    parser.add_argument(
        "--smoke-wait-exit-after-ready",
        type=positive_float,
        default=None,
        help=(
            "Recommended os_mode_smoke.py post-readiness process-exit wait in "
            "seconds. Defaults to 60 when smoke poweroff is enabled and is "
            "omitted otherwise."
        ),
    )
    parser.add_argument(
        "--require-apfs-output",
        action="store_true",
        help="Fail on macOS unless --output-dir is on APFS for clone-backed launch.",
    )
    parser.add_argument(
        "--systemd-mask",
        action="append",
        default=[],
        metavar="UNIT",
        help=(
            "Additional systemd unit to mask in --init-mode systemd. "
            "May be passed more than once."
        ),
    )
    parser.add_argument(
        "--no-default-systemd-masks",
        action="store_true",
        help="Do not apply the default constrained-VM systemd mask list.",
    )
    parser.add_argument(
        "--systemd-serial-control-shell",
        action="store_true",
        help=(
            "In --init-mode systemd, enable a validation-only root shell on "
            "the selected platform serial console after the readiness service runs."
        ),
    )
    parser.add_argument(
        "--pull",
        action="store_true",
        help="Pull the source and builder images before exporting/building.",
    )
    parser.add_argument(
        "--check-tools",
        action="store_true",
        help="Check for a usable container runtime and exit without building.",
    )
    return parser.parse_args()


def prepare_output_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path.resolve()


def output_artifact_paths(output_dir: Path) -> dict[str, Path]:
    return {
        "rootfs.tar": output_dir / "rootfs.tar",
        "overlay.tar": output_dir / "overlay.tar",
        "root.raw": output_dir / "root.raw",
        "vm-root.raw": output_dir / "vm-root.raw",
        "manifest.json": output_dir / "manifest.json",
    }


def existing_output_artifacts(output_dir: Path) -> list[Path]:
    return [
        path
        for path in output_artifact_paths(output_dir).values()
        if path.exists() or path.is_symlink()
    ]


def ensure_output_artifacts_absent(output_dir: Path) -> None:
    conflicts = existing_output_artifacts(output_dir)
    if conflicts:
        paths = ", ".join(str(path) for path in conflicts)
        raise SystemExit(
            "--output-dir already contains OS-mode output artifacts; "
            f"use a fresh directory or remove them first: {paths}"
        )


def normalize_optional_path(value: str | Path | None) -> str | None:
    if value is None:
        return None
    return str(Path(value).expanduser().resolve())


def choose_runtime(requested: str) -> str:
    candidates = ("podman", "docker") if requested == "auto" else (requested,)
    for candidate in candidates:
        if not shutil.which(candidate):
            continue
        probe = subprocess.run(
            [candidate, "version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if probe.returncode == 0:
            return candidate
    raise SystemExit(
        "a working podman or docker runtime is required. If using Podman on "
        "macOS, run `podman machine init` and `podman machine start` first."
    )


def runtime_version(runtime: str) -> str:
    result = run([runtime, "version"], capture=True)
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if not lines:
        raise SystemExit(f"could not determine {runtime} version")
    return "; ".join(lines)


def build_host_info() -> dict[str, str]:
    return {
        "system": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "python_version": platform.python_version(),
    }


def utc_timestamp() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def run(cmd: list[str], *, capture: bool = False) -> subprocess.CompletedProcess:
    print("+ " + " ".join(cmd), file=sys.stderr)
    return subprocess.run(
        cmd,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def apfs_output_info(path: Path) -> dict[str, object]:
    if sys.platform != "darwin":
        return {
            "checked": False,
            "reason": "not macOS",
            "is_apfs": None,
            "filesystem": None,
            "device": None,
        }

    df_result = run(["df", "-P", str(path)], capture=True)
    df_lines = [line for line in df_result.stdout.splitlines() if line.strip()]
    if len(df_lines) < 2:
        raise SystemExit(f"could not determine filesystem for {path}")

    df_fields = df_lines[-1].split()
    device = df_fields[0]
    mount_point = df_fields[-1]
    mount_result = run(["mount"], capture=True)
    filesystem = None
    for line in mount_result.stdout.splitlines():
        marker = f" on {mount_point} ("
        if marker not in line:
            continue
        suffix = line.split(marker, 1)[1]
        filesystem = suffix.split(",", 1)[0].rstrip(")")
        break

    return {
        "checked": True,
        "is_apfs": filesystem == "apfs",
        "filesystem": filesystem,
        "device": device,
        "mount_point": mount_point,
    }


def image_digest(runtime: str, image: str) -> str | None:
    try:
        result = run([runtime, "image", "inspect", image], capture=True)
        payload = json.loads(result.stdout)
        if not payload:
            return None
        repo_digests = payload[0].get("RepoDigests") or []
        if repo_digests:
            return repo_digests[0]
        return payload[0].get("Id")
    except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError):
        return None


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def export_rootfs(runtime: str, image: str, platform: str, output_tar: Path) -> None:
    name = f"krun-osmode-export-{uuid.uuid4().hex}"
    created = False
    try:
        run([runtime, "create", "--platform", platform, "--name", name, image])
        created = True
        run([runtime, "export", "-o", str(output_tar), name])
    finally:
        if created:
            subprocess.run([runtime, "rm", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def build_ext4(
    runtime: str,
    builder_image: str,
    platform: str,
    output_dir: Path,
    size_mb: int,
    init_mode: str,
    require_dhcp_client: bool,
    serial_console: str,
    use_default_systemd_masks: bool,
    systemd_masks: list[str],
    systemd_serial_control_shell: bool,
) -> None:
    env_args = [
        "-e",
        f"SIZE_MB={size_mb}",
        "-e",
        f"INIT_MODE={init_mode}",
        "-e",
        f"REQUIRE_DHCP_CLIENT={1 if require_dhcp_client else 0}",
        "-e",
        f"SERIAL_CONSOLE={serial_console}",
        "-e",
        f"USE_DEFAULT_SYSTEMD_MASKS={1 if use_default_systemd_masks else 0}",
        "-e",
        f"SYSTEMD_MASKS={' '.join(systemd_masks)}",
        "-e",
        f"ENABLE_SYSTEMD_SERIAL_CONTROL={1 if systemd_serial_control_shell else 0}",
    ]
    run(
        [
            runtime,
            "run",
            "--rm",
            "--platform",
            platform,
            "-v",
            f"{output_dir.resolve()}:/work",
            *env_args,
            builder_image,
            "sh",
            "-euxc",
            BUILDER_SCRIPT,
        ]
    )


def manifest_command(args: argparse.Namespace, launch_root_disk: Path) -> list[str]:
    command = [
        "examples/os_mode",
    ]
    if args.kernel:
        command.extend(["--kernel", args.kernel])
        command.extend(["--kernel-format", str(args.kernel_format)])
    if args.initramfs:
        command.extend(["--initramfs", args.initramfs])
    command.extend(
        [
            "--root-disk",
            str(launch_root_disk),
            "--disk-sync",
            args.disk_sync,
            "--root-device",
            args.root_device,
            "--root-fstype",
            args.root_fstype,
            "--guest-init",
            "/sbin/init",
        ]
    )
    if args.root_options:
        command.extend(["--root-options", args.root_options])
    command.extend(["--console", PLATFORM_CONSOLES[args.platform]])
    kernel_cmdline = []
    if args.init_mode == "systemd":
        kernel_cmdline.extend(["rw", "systemd.unit=multi-user.target"])
    if args.network_smoke:
        kernel_cmdline.append("KRUN_OSMODE_NET=1")
    if kernel_cmdline:
        command.extend(["--kernel-cmdline", " ".join(kernel_cmdline)])
    return command


def main() -> int:
    args = parse_args()
    unit_errors = validate_systemd_unit_names(args.systemd_mask)
    if unit_errors:
        for error in unit_errors:
            print(error, file=sys.stderr)
        return 2
    if args.kernel_format is None:
        args.kernel_format = PLATFORM_KERNEL_FORMATS[args.platform]
    if args.network_smoke:
        args.require_dhcp_client = True
    if args.expected_root is None:
        args.expected_root = args.root_device
    if args.smoke_timeout is None:
        if args.init_mode == "systemd":
            args.smoke_timeout = 120.0
        elif args.network_smoke:
            args.smoke_timeout = 45.0
        else:
            args.smoke_timeout = 30.0
    if args.smoke_wait_exit_after_ready is None and not args.no_smoke_poweroff_after_ready:
        args.smoke_wait_exit_after_ready = 60.0
    args.kernel = normalize_optional_path(args.kernel)
    args.initramfs = normalize_optional_path(args.initramfs)
    args.overlay_tar = (
        Path(normalize_optional_path(args.overlay_tar)) if args.overlay_tar is not None else None
    )

    args.output_dir = prepare_output_dir(args.output_dir)
    output_apfs = apfs_output_info(args.output_dir)
    if args.require_apfs_output and output_apfs.get("is_apfs") is not True:
        raise SystemExit(
            f"--output-dir must be on APFS for clone-backed launch; "
            f"detected filesystem={output_apfs.get('filesystem')!r}"
        )

    rootfs_tar = args.output_dir / "rootfs.tar"
    overlay_dst = args.output_dir / "overlay.tar"
    root_disk = args.output_dir / "root.raw"
    launch_root_disk = args.output_dir / "vm-root.raw"
    manifest_path = args.output_dir / "manifest.json"
    if not args.check_tools:
        ensure_output_artifacts_absent(args.output_dir)

    runtime = choose_runtime(args.runtime)
    runtime_version_text = runtime_version(runtime)

    if args.check_tools:
        print(f"runtime={runtime}")
        print(f"runtime_version={runtime_version_text}")
        print(f"output_dir_apfs={json.dumps(output_apfs, sort_keys=True)}")
        return 0

    started = time.monotonic()
    if args.pull:
        run([runtime, "pull", "--platform", args.platform, args.image])
        run([runtime, "pull", "--platform", args.platform, args.builder_image])

    source_digest = image_digest(runtime, args.image)
    if source_digest is None:
        raise SystemExit(f"could not determine source image digest or ID for {args.image}")

    export_started = time.monotonic()
    export_rootfs(runtime, args.image, args.platform, rootfs_tar)
    export_ms = int((time.monotonic() - export_started) * 1000)

    if args.overlay_tar:
        shutil.copyfile(args.overlay_tar, overlay_dst)
    elif overlay_dst.exists():
        overlay_dst.unlink()

    build_started = time.monotonic()
    build_ext4(
        runtime,
        args.builder_image,
        args.platform,
        args.output_dir,
        args.size_mb,
        args.init_mode,
        args.require_dhcp_client,
        PLATFORM_CONSOLES[args.platform],
        not args.no_default_systemd_masks,
        args.systemd_mask,
        args.systemd_serial_control_shell,
    )
    build_ms = int((time.monotonic() - build_started) * 1000)

    builder_digest = image_digest(runtime, args.builder_image)
    if builder_digest is None:
        raise SystemExit(f"could not determine builder image digest or ID for {args.builder_image}")

    root_disk_sha = sha256_file(root_disk)
    rootfs_tar_sha = sha256_file(rootfs_tar)
    manifest = {
        "manifest_schema_version": 1,
        "created_at_utc": utc_timestamp(),
        "builder": "examples/os_mode_build_container_rootfs.py",
        "builder_script_sha256": sha256_text(BUILDER_SCRIPT),
        "builder_image": args.builder_image,
        "builder_digest": builder_digest,
        "build_host": build_host_info(),
        "runtime": runtime,
        "runtime_version": runtime_version_text,
        "source_image": args.image,
        "source_digest": source_digest,
        "platform": args.platform,
        "init_mode": args.init_mode,
        "require_dhcp_client": args.require_dhcp_client,
        "network_smoke": args.network_smoke,
        "smoke_timeout_sec": args.smoke_timeout,
        "smoke_poweroff_after_ready": not args.no_smoke_poweroff_after_ready,
        "smoke_wait_exit_after_ready_sec": args.smoke_wait_exit_after_ready,
        "expected_markers": (
            ["KRUN_OSMODE: network=up"] if args.network_smoke else []
        ),
        "systemd_default_masks": not args.no_default_systemd_masks,
        "systemd_masks": args.systemd_mask,
        "systemd_serial_control_shell": args.systemd_serial_control_shell,
        "systemd_effective_masks": (
            list(DEFAULT_SYSTEMD_MASKS) if not args.no_default_systemd_masks else []
        )
        + args.systemd_mask,
        "output_dir_apfs": output_apfs,
        "rootfs_tar": str(rootfs_tar),
        "rootfs_tar_sha256": rootfs_tar_sha,
        "rootfs_tar_size_bytes": rootfs_tar.stat().st_size,
        "overlay_tar": str(overlay_dst) if overlay_dst.exists() else None,
        "overlay_tar_sha256": sha256_file(overlay_dst) if overlay_dst.exists() else None,
        "overlay_tar_size_bytes": overlay_dst.stat().st_size if overlay_dst.exists() else None,
        "root_disk": str(root_disk),
        "root_disk_sha256": root_disk_sha,
        "root_disk_size_bytes": root_disk.stat().st_size,
        "root_disk_size_mb": args.size_mb,
        "root_device": args.root_device,
        "expected_root": args.expected_root,
        "root_fstype": args.root_fstype,
        "root_options": args.root_options,
        "disk_sync": args.disk_sync,
        "kernel": args.kernel,
        "kernel_format": args.kernel_format,
        "initramfs": args.initramfs,
        "init": "/sbin/init",
        "timings_ms": {
            "export_rootfs": export_ms,
            "build_ext4": build_ms,
            "total": int((time.monotonic() - started) * 1000),
        },
        "os_mode_command": manifest_command(args, launch_root_disk),
        "apfs_clone_command": [
            "examples/os_mode_apfs_clone.sh",
            str(root_disk),
            str(launch_root_disk),
        ],
    }
    manifest_errors = check_manifest_payload(
        manifest,
        manifest_path.parent,
        manifest_file=manifest_path,
        require_apfs=args.require_apfs_output,
    )
    if manifest_errors:
        for error in manifest_errors:
            print(f"manifest validation failed: {error}", file=sys.stderr)
        return 1
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
