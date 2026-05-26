# OS Mode Guest Image Guide

This guide describes the first supported guest shape for libkrun OS mode: a
prepared raw ext4 root disk and a direct-boot Linux kernel. The image is
purpose-built for virtio-mmio and should not depend on firmware, PCI, GRUB, or
cloud metadata.

On macOS, OCI/container images have two supported roles. A normal container
image can be a rootfs source that Docker or Podman exports and adapts into a
raw virtio-blk root disk. A prepared OCI image can also be a libkrun OS bundle
that already contains `root.raw`, a guest kernel, optional initramfs, and a
manifest under `/libkrun-os-bundle/`. In both cases, the container image is not
the final runtime: libkrun boots the resulting APFS-cloned raw disk under HVF.

## Kernel Config Fragments

Use built-in drivers for the root path so the guest can mount `/` without
module loading. An initramfs is optional; if used, it must contain the same
storage and filesystem support.

Common fragment:

```text
CONFIG_VIRTIO=y
CONFIG_VIRTIO_MMIO=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_CONSOLE=y
CONFIG_HW_RANDOM=y
CONFIG_HW_RANDOM_VIRTIO=y
CONFIG_EXT4_FS=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_TMPFS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_UNIX=y
CONFIG_INET=y
CONFIG_PACKET=y
```

Memory reclaim (virtio-balloon free-page reporting):

```text
CONFIG_VIRTIO_BALLOON=y
CONFIG_PAGE_REPORTING=y
```

libkrun always attaches a virtio-balloon device and advertises
`VIRTIO_BALLOON_F_REPORTING`; its free-page-reporting queue handler returns
reported pages to the host with `madvise(MADV_DONTNEED)`. A guest built with
these two options therefore hands idle pages back automatically, so a long-lived
VM's host RSS tracks its live working set instead of its high-water mark — the
density lever in the agent-sandbox design (free-page reporting / #A). Without
`CONFIG_PAGE_REPORTING` the device still negotiates the feature but the guest
never reports, so no reclaim happens. These are independent of the optional
runtime *resize* path (`--control-socket` / `--balloon-initial-mib`), which
stays available when a higher ceiling is booted.

Shared read-only mounts with DAX (share host page cache across guests):

```text
CONFIG_VIRTIO_FS=y
CONFIG_FUSE_FS=y
CONFIG_FUSE_DAX=y
CONFIG_DAX=y
CONFIG_ZONE_DEVICE=y
```

With a DAX window (`krun_add_virtiofs2/3` `shm_size`, surfaced as os_mode's
`--virtiofs-dax-size`), a guest maps virtio-fs file pages directly from the host
page cache rather than copying them into guest RAM. Multiple guests mounting the
same read-only host directory then share those physical pages while staying
isolated — the cross-VM sharing lever (virtiofs DAX / #D). Without
`CONFIG_FUSE_DAX` the mount still works but falls back to per-guest caching.

x86_64 serial additions:

```text
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_PNP=y
CONFIG_SERIAL_8250_PCI=y
```

aarch64 PL011 serial additions:

```text
CONFIG_SERIAL_AMBA_PL011=y
CONFIG_SERIAL_AMBA_PL011_CONSOLE=y
```

Recommended development settings:

```text
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_GZIP=y
CONFIG_EARLY_PRINTK=y
```

Avoid relying on modules for the first images. OS mode intentionally does not
set `nomodule`, but built-in root-path drivers make boot failures easier to
diagnose and keep cold boot faster.

Known-good macOS/ARM64 HVF validation currently uses the Alpine aarch64 virt
kernel/initramfs profile with matching modules overlaid into the rootfs when
networking is required. Linux/KVM kernel validation remains deferred until a
Linux host or CI runner with `/dev/kvm` is available.

## Minimal BusyBox Rootfs

The first smoke image can be a BusyBox rootfs with `/sbin/init` as a shell
script:

```sh
#!/bin/sh
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t tmpfs tmpfs /run

echo "KRUN_OSMODE: init-started"
root_source=$(awk '$2 == "/" {print $1 " " $3 " " $4}' /proc/mounts)
echo "KRUN_OSMODE: root=${root_source}"
pid1_comm=$(cat /proc/1/comm 2>/dev/null || true)
pid1_exe=$(readlink /proc/1/exe 2>/dev/null || true)
echo "KRUN_OSMODE: pid1=${pid1_comm} ${pid1_exe}"
echo "KRUN_OSMODE: console=$(cat /sys/class/tty/console/active 2>/dev/null || true)"

if command -v udhcpc >/dev/null 2>&1 && ip link show eth0 >/dev/null 2>&1; then
    ip link set eth0 up || true
    udhcpc -i eth0 -q -t 3 && echo "KRUN_OSMODE: network=dhcp-ok" || echo "KRUN_OSMODE: network=dhcp-failed"
fi

echo "KRUN_OSMODE: ready"
exec sh
```

The image must include:

- `/bin/busybox` with applets linked or installed.
- `/sbin/init` executable.
- Empty mount points for `/dev`, `/proc`, `/sys`, and `/run`.
- A shell or getty reachable from the selected console.
- A DHCP client only if networking is part of the smoke test.

## OCI-Packaged OS Bundles

For macOS users consuming an already prepared OS, the preferred format is an
OCI image that contains a complete libkrun OS-mode bundle:

```text
/libkrun-os-bundle/manifest.json
/libkrun-os-bundle/root.raw
/libkrun-os-bundle/kernel
/libkrun-os-bundle/initramfs        # optional
```

This is the supported meaning of "run a Linux OS in a container from macOS."
The image is a packaging and transport format. The macOS host extracts the
bundle files, validates the manifest and SHA-256 digests, APFS-clones
`root.raw`, and starts `examples/os_mode` as a host-side HVF process. Docker
Desktop or Podman may be used to pull and copy files out of the image, but a
successful `docker run` or `podman run` is not runtime evidence for OS mode.

Import and run a prepared bundle image with:

```sh
export KRUN_OS_BUNDLE_CACHE="$HOME/Library/Caches/libkrun/os-bundles"
mkdir -p "$KRUN_OS_BUNDLE_CACHE"

examples/os_mode_import_container_bundle.py \
  --image example.com/linux-os/libkrun-bundle@sha256:... \
  --output-dir "$KRUN_OS_BUNDLE_CACHE/example-bundle" \
  --runtime auto \
  --strict-digest \
  --clone-dest vm-root.raw \
  --smoke-output smoke.json \
  --run
```

The bundle manifest must identify:

- `kind: libkrun.os-bundle.v1` and schema version `1`.
- guest platform, currently `linux/arm64` for the macOS/HVF product path;
- kernel path, kernel format, kernel SHA-256, and optional initramfs metadata;
- immutable `root.raw` path, apparent size, SHA-256, allocated-size metadata
  when available, filesystem type, root token, and root mount options;
- expected console, expected PID 1, expected root marker, smoke timeout, and
  clean-shutdown policy;
- APFS clone policy requiring clone-backed launch and disallowing silent
  full-copy fallback for the default macOS path.

For repeat launches, keep the extracted bundle directory and pass
`--reuse-extracted-output-dir` with the same image reference and a fresh
`--clone-dest`. Reuse skips Docker/Podman extraction only when import metadata
matches the requested image. It never reuses the writable VM root; every launch
still creates a new APFS clone unless the caller deliberately names a
persistent clone.

To publish a local test bundle from a validated rootfs-source artifact:

```sh
export KRUN_OS_WORKDIR="$HOME/Library/Caches/libkrun/os-mode-work"
mkdir -p "$KRUN_OS_WORKDIR"

examples/os_mode_publish_container_bundle.py \
  "$KRUN_OS_WORKDIR/container-alpine/manifest.json" \
  --output-dir "$KRUN_OS_WORKDIR/bundle-context" \
  --image-tag libkrun-osmode-alpine:arm64
```

The publisher packages the immutable base `root.raw`, not a per-VM APFS clone,
and rejects source manifests whose launch command attaches the immutable base
directly.

Known-good macOS bundle profiles:

| Bundle profile | Platform | Guest PID 1 | Console | Network | Status |
| --- | --- | --- | --- | --- | --- |
| Alpine/BusyBox smoke rootfs | `linux/arm64` | `init` | `ttyAMA0` | gvproxy validated when matching modules are overlaid | validated from APFS clone on macOS/ARM64 HVF |
| Debian `bookworm` systemd rootfs | `linux/arm64` | `systemd` | `ttyAMA0` | gvproxy validated with `udhcpc`, `af_packet`, and `virtio_net` available | validated from APFS clone on macOS/ARM64 HVF |
| Linux/KVM x86_64 smoke artifacts | `linux/amd64` | image-specific | `ttyS0` | passt unixstream | deferred until a Linux host with `/dev/kvm` is available |

## Container Image Rootfs Sources

A container image can provide most of the guest OS userspace. It must be turned
into a bootable root disk before libkrun can run it in OS mode.

Required macOS flow:

1. Pull or build an OCI image for the guest architecture, initially `linux/arm64`
   for macOS/ARM64 HVF.
2. Export the container filesystem with Docker or Podman.
3. Add or validate the boot contract: `/sbin/init`, mount points, console
   output, optional DHCP tooling, and readiness markers.
4. Pack the result into a raw ext4 disk from inside a Linux builder container.
5. Copy the raw disk to the macOS APFS volume as an immutable base image.
6. Create a per-VM APFS clone of that base image.
7. Boot the clone with `examples/os_mode`.

Illustrative export step:

```sh
image=alpine:3.23
name=krun-rootfs-export

podman create --platform linux/arm64 --name "$name" "$image"
podman export "$name" -o rootfs.tar
podman rm "$name"
```

Docker can be used the same way if it supports the target platform:

```sh
docker create --platform linux/arm64 --name "$name" "$image"
docker export "$name" -o rootfs.tar
docker rm "$name"
```

The exported tar is not enough by itself. Most application container images do
not include a real bootable init system or serial console configuration. The
builder must either:

- inject a minimal `/sbin/init` script, suitable for smoke images;
- validate and configure the image's existing init system;
- install and configure systemd plus a serial getty/readiness unit; or
- reject the image with a clear diagnostic.

The repo helper implements the first smoke path:

```sh
examples/os_mode_build_container_rootfs.py \
  --image alpine:3.23 \
  --output-dir "$KRUN_OS_WORKDIR/container-alpine" \
  --runtime auto \
  --platform linux/arm64 \
  --size-mb 256 \
  --require-apfs-output \
  --kernel /path/to/vmlinuz-virt \
  --kernel-format 2 \
  --initramfs /path/to/initramfs-virt-with-ext4.gz
```

By default it injects a small `/sbin/init` that mounts `/dev`, `/proc`, `/sys`,
and `/run`, emits `KRUN_OSMODE:*` readiness markers to the active console, and
then execs a shell on `/dev/console`. Use `--init-mode validate-existing` when
the source image should supply its own executable `/sbin/init`.
Use `--require-apfs-output` on macOS when the generated root disk will be
APFS-cloned before launch.
The default kernel format is `2` (`KRUN_KERNEL_FORMAT_PE_GZ`) for `linux/arm64`
and `1` (`KRUN_KERNEL_FORMAT_ELF`) for `linux/amd64`; pass `--kernel-format 0`
when using a raw arm64 `Image`.

For a systemd-capable source image, build the provided Debian image:

```sh
docker build \
  --platform linux/arm64 \
  -f ci/os_mode_debian_systemd.Containerfile \
  -t libkrun-osmode-debian-systemd:bookworm-arm64 \
  .
```

Then build the root disk with systemd adaptation:

```sh
examples/os_mode_build_container_rootfs.py \
  --image libkrun-osmode-debian-systemd:bookworm-arm64 \
  --output-dir "$KRUN_OS_WORKDIR/debian-systemd" \
  --runtime auto \
  --platform linux/arm64 \
  --size-mb 1024 \
  --require-apfs-output \
  --require-dhcp-client \
  --init-mode systemd \
  --kernel /path/to/vmlinuz-virt \
  --kernel-format 2 \
  --initramfs /path/to/initramfs-virt-with-ext4.gz
```

`--init-mode systemd` validates that systemd exists, ensures `/sbin/init`
resolves inside the guest rootfs, installs the readiness marker as a
`multi-user.target` one-shot service, enables the platform serial getty when
the template exists (`serial-getty@ttyAMA0.service` for `linux/arm64`,
`serial-getty@ttyS0.service` for `linux/amd64`), and adds a modules-load
drop-in for the network modules used by the current Alpine kernel validation
path. The validated Debian systemd path uses `linux/arm64` on macOS/ARM64 HVF.

For the validated Debian smoke profile, the builder also remounts `/`
read-write before readiness and masks units that either fail repeatedly or add
irrelevant maintenance work in this constrained VM: `systemd-logind.service`,
`apt-daily.timer`, `apt-daily-upgrade.timer`, `dpkg-db-backup.timer`, and
`e2scrub_all.timer`. Add profile-specific masks with `--systemd-mask UNIT`, or
pass `--no-default-systemd-masks` to use only the explicitly requested masks.
Additional mask names must be simple systemd unit basenames, such as
`custom.service` or `custom.timer`; names with slashes, whitespace, or missing
unit suffixes are rejected before the Docker/Podman build step.
For one-shot validation, pass `--poweroff-after-ready` to the `examples/os_mode`
launcher. The launcher appends the validation-only `KRUN_OSMODE_POWEROFF=1`
marker so the readiness service asks systemd to power off after printing
`KRUN_OSMODE: ready`.

The same readiness service supports persistent-write validation flags. Add
`KRUN_OSMODE_WRITE_TEST=1` to write a boot-id keyed marker under
`/var/lib/krun-osmode/write-test/` and verify journald readback when the journal
tools are present. Add `KRUN_OSMODE_APT_UPDATE=1` to run `apt-get update` and
emit a package-manager readiness marker. Use these flags on an APFS clone, not
the immutable base image, and record base checksum stability plus clone
allocated-size growth across repeated boots.

For automated persistent-VM validation, build the systemd root disk with
`--systemd-serial-control-shell`. This intentionally creates a validation-only
root shell on the selected platform serial console after the readiness service
runs and masks the normal serial getty plus `console-getty.service`. The
runtime test must omit
`--poweroff-after-ready`, send a command through the serial console with
`examples/os_mode_perf.py --control-command`, wait for an explicit
`KRUN_OSMODE: control=ok` marker, and then shut the guest down through that same
control path, for example with `poweroff -f`. This proves the guest remained
running after readiness and that the host retained a managed control channel.

If the source image does not carry the kernel modules that match the direct-boot
kernel, pass an overlay tarball:

```sh
examples/os_mode_build_container_rootfs.py \
  --image alpine:3.23 \
  --output-dir "$KRUN_OS_WORKDIR/container-alpine-net" \
  --overlay-tar /path/to/modules-overlay.tar \
  --require-dhcp-client \
  --kernel /path/to/vmlinuz-virt \
  --initramfs /path/to/initramfs-virt-with-ext4.gz
```

The validated gvproxy smoke path needed an overlay containing `/lib/modules`
from the Alpine `modloop-virt` matching the booted `vmlinuz-virt`; without it,
`udhcpc` failed because `AF_PACKET` support was unavailable in the guest.
`--require-dhcp-client` catches images that lack `udhcpc`, `dhclient`, or
`dhcpcd` before the raw root disk is built.

The container-derived image builder emits a manifest similar to:

```json
{
  "manifest_schema_version": 1,
  "created_at_utc": "2026-05-17T12:00:00Z",
  "builder": "examples/os_mode_build_container_rootfs.py",
  "builder_script_sha256": "...",
  "builder_image": "docker.io/library/alpine:3.23",
  "builder_digest": "alpine@sha256:...",
  "build_host": {
    "system": "Darwin",
    "release": "25.5.0",
    "machine": "arm64",
    "python_version": "3.13.3"
  },
  "runtime": "docker",
  "runtime_version": "Client: Docker Engine ...; Server: Docker Desktop ...",
  "require_dhcp_client": false,
  "network_smoke": false,
  "smoke_timeout_sec": 30,
  "smoke_poweroff_after_ready": true,
  "smoke_wait_exit_after_ready_sec": 60,
  "expected_markers": [],
  "init_mode": "inject-smoke",
  "systemd_default_masks": true,
  "systemd_masks": [],
  "systemd_effective_masks": [
    "systemd-logind.service",
    "apt-daily.timer",
    "apt-daily-upgrade.timer",
    "dpkg-db-backup.timer",
    "e2scrub_all.timer"
  ],
  "systemd_serial_control_shell": false,
  "output_dir_apfs": {
    "checked": true,
    "device": "/dev/disk3s1",
    "filesystem": "apfs",
    "is_apfs": true,
    "mount_point": "/System/Volumes/Data"
  },
  "source_image": "alpine:3.23",
  "source_digest": "alpine@sha256:...",
  "platform": "linux/arm64",
  "rootfs_tar": "/Users/example/Library/Caches/libkrun/os-mode-work/container-alpine/rootfs.tar",
  "rootfs_tar_sha256": "...",
  "rootfs_tar_size_bytes": 12345678,
  "overlay_tar": null,
  "overlay_tar_sha256": null,
  "overlay_tar_size_bytes": null,
  "root_disk": "/Users/example/Library/Caches/libkrun/os-mode-work/container-alpine/root.raw",
  "root_disk_sha256": "...",
  "root_disk_size_bytes": 268435456,
  "root_disk_size_mb": 256,
  "root_device": "/dev/vda",
  "expected_root": "/dev/vda",
  "root_fstype": "ext4",
  "root_options": null,
  "disk_sync": "relaxed",
  "kernel": "/path/to/vmlinuz-virt",
  "kernel_format": 2,
  "initramfs": "/path/to/initramfs-with-ext4.gz",
  "init": "/sbin/init",
  "timings_ms": {
    "export_rootfs": 178,
    "build_ext4": 1237,
    "total": 1555
  },
  "os_mode_command": [
    "examples/os_mode",
    "--kernel",
    "/path/to/vmlinuz-virt",
    "--kernel-format",
    "2",
    "--initramfs",
    "/path/to/initramfs-with-ext4.gz",
    "--root-disk",
    "/Users/example/Library/Caches/libkrun/os-mode-work/container-alpine/vm-root.raw",
    "--disk-sync",
    "relaxed",
    "--root-device",
    "/dev/vda",
    "--root-fstype",
    "ext4",
    "--guest-init",
    "/sbin/init",
    "--console",
    "ttyAMA0"
  ],
  "apfs_clone_command": [
    "examples/os_mode_apfs_clone.sh",
    "/Users/example/Library/Caches/libkrun/os-mode-work/container-alpine/root.raw",
    "/Users/example/Library/Caches/libkrun/os-mode-work/container-alpine/vm-root.raw"
  ]
}
```

The macOS runtime validation must boot the APFS clone of the generated disk, not
the Docker or Podman container. Docker Desktop on macOS is useful for building
Linux filesystem artifacts, but it does not validate libkrun/HVF behavior.

The builder runs `examples/os_mode_manifest_check.py` before reporting success.
Before boot, callers can also run the checker again against the generated
manifest. The checker verifies that the referenced rootfs tar and raw root disk
exist, that their SHA-256 checksums match the manifest, that the source image
identity is a SHA-256 digest or image ID from Docker/Podman, that APFS output
is recorded when required, that build-host, builder-image, runtime-version,
artifact-size, root-device, root-source, timing, and schema-version fields are
well formed, and that the recommended `examples/os_mode` command, including
kernel format and platform console, and APFS clone commands match the manifest
fields. The builder normalizes the output directory plus optional kernel,
initramfs, and overlay paths to absolute paths before writing artifact paths so
the manifest can be replayed from a different current working directory.

For the macOS container-to-VM path, replay validation should be generated from
the manifest rather than retyping paths:

```sh
examples/os_mode_manifest_check.py \
  --require-apfs \
  --print-commands \
  --smoke-output smoke.json \
  --perf-output perf.json \
  --write-runbook replay-smoke.sh \
  "$KRUN_OS_WORKDIR/container-alpine/manifest.json"

"$KRUN_OS_WORKDIR/container-alpine/replay-smoke.sh"
```

The runbook first creates a fresh APFS clone from the immutable `root.raw`
base image, then runs the smoke wrapper against the clone-backed
`examples/os_mode` command. The smoke wrapper must observe the expected
`KRUN_OSMODE:*` markers, reject `init.krun` as PID 1, check the expected root
source and console, and optionally wait for clean guest shutdown. Use
`--clone-dest`, `--smoke-output`, and `--perf-output` with fresh paths for
repeated launches so validation never overwrites the base image, existing APFS
clones, runbooks, or JSON evidence.

## Raw ext4 Disk Recipe

On Linux, create and partition a raw disk:

```sh
truncate -s 512M root.raw
parted -s root.raw mklabel gpt
parted -s root.raw mkpart root ext4 1MiB 100%
loop=$(losetup --find --show --partscan root.raw)
mkfs.ext4 "${loop}p1"
mkdir -p mnt
mount "${loop}p1" mnt
# populate mnt with the rootfs
umount mnt
losetup -d "$loop"
```

Record stable identifiers after formatting:

```sh
blkid "${loop}p1"
```

The examples use `/dev/vda1` for clarity. For more robust images, use
`root=PARTUUID=<uuid>` through `krun_set_os_root()` once the recipe records the
partition UUID.

## macOS Notes

macOS can host and APFS-clone raw disk image files, but it is not a convenient
environment for creating or modifying Linux ext4 filesystems directly. For a
prepared OS, prefer `examples/os_mode_import_container_bundle.py --image ...`
so the container image acts as the bundle transport and the macOS host only has
to extract, validate, APFS-clone, and launch. For authoring a new OS from an
ordinary OCI/container rootfs, use `examples/os_mode_build_container_rootfs.py`
on macOS with Docker Desktop or Podman: the container runtime provides the
Linux filesystem export and ext4 construction environment, while libkrun/HVF
remains the runtime proof. For rootfs sources that are not containers, build
the raw ext4 base image on Linux, copy it to the macOS APFS host volume, then
create per-VM clones with `examples/os_mode_apfs_clone.sh`.

The same aarch64 rootfs content should be usable on Linux/aarch64 KVM and
macOS/ARM64 HVF when the kernel, console name, and network backend are selected
for each host.

## Validation Requirements

The smoke test fails if:

- `KRUN_OSMODE: ready` does not appear before timeout.
- `KRUN_OSMODE: pid1=...` identifies `init.krun`.
- `KRUN_OSMODE: root=...` does not identify the configured virtio-blk root or
  stable root identifier.
- No early boot or init output appears on the selected console.

APFS clone validation must additionally prove:

- The VM boots from the per-VM clone path.
- Guest writes change only the clone.
- The base image checksum or read-only marker is unchanged after guest writes.
- Ephemeral clone cleanup removes the per-VM file and releases unique allocated
  blocks as expected by APFS.
- Distro write paths such as journald and package-manager metadata can run
  across repeated boots of a persistent clone without modifying the base image.

## Minimal systemd Rootfs

Use a systemd image only after the BusyBox readiness image works on the target
host. The minimal systemd profile should:

- Include the same built-in kernel root-path drivers described above.
- Boot to `multi-user.target` or a custom validation target, not a graphical
  target.
- Enable a serial getty on `ttyS0` for x86_64 or `ttyAMA0` for aarch64.
- Mask services that wait on unavailable hardware, firmware, cloud metadata,
  or persistent network naming assumptions.
- Include a one-shot readiness service that emits the `KRUN_OSMODE:*` markers
  to `/dev/console`.
- Run a normal guest DHCP client only when virtio-net validation is requested.

Example readiness unit:

```ini
[Unit]
Description=libkrun OS-mode readiness marker
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/krun-osmode-ready
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
```

The `/usr/local/libexec/krun-osmode-ready` script should print the same markers
as the BusyBox init path. Keep the script independent of networking for first
boot validation.

For macOS gvproxy validation with a systemd rootfs, the readiness path should
bring up the first non-loopback interface, load matching `af_packet` and
virtio-net modules when they are shipped as modules, and prefer a DHCP client
that works with the selected guest kernel. The validated Debian systemd profile
uses `udhcpc`; Debian's ISC `dhclient` failed against the current Alpine virt
kernel until `AF_PACKET` was loaded.

## Shutdown and Reboot

The first smoke tests should validate clean shutdown separately from boot. A
guest-initiated `poweroff` or `shutdown -h now` should let the VMM exit through
the existing libkrun shutdown path. Guest reboot behavior is not a first
milestone requirement; document the observed behavior for each host/backend
before relying on reboot loops in higher-level orchestration.
