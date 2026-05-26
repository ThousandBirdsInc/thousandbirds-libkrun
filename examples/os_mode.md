# OS Mode Example

`os_mode.c` boots a prepared Linux root disk as a full guest OS. It uses direct
kernel boot, virtio-mmio, a raw virtio-blk root disk, and a serial console. It
does not boot firmware, GRUB, ISO installers, or arbitrary cloud images.

## Guest Contract

The guest kernel must include the drivers needed before the root filesystem is
mounted:

- `CONFIG_VIRTIO=y`
- `CONFIG_VIRTIO_MMIO=y`
- `CONFIG_VIRTIO_BLK=y`
- `CONFIG_VIRTIO_NET=y` if networking is used
- `CONFIG_VIRTIO_CONSOLE=y` if virtio-console is used
- `CONFIG_EXT4_FS=y` for the initial raw ext4 examples
- `CONFIG_DEVTMPFS=y` and `CONFIG_DEVTMPFS_MOUNT=y`
- x86_64 serial support for `ttyS0`
- aarch64 PL011 serial support for `ttyAMA0`

The root disk must contain `/sbin/init`, or the kernel command line must supply
an alternate `init=` value. The first example convention is `/dev/vda1`, but a
stable `PARTUUID=` root is better once the image recipe records one.

An OCI/container image can be used as the source for the root filesystem, but it
must be converted into a bootable raw root disk first. On macOS, Docker or
Podman can export and adapt the Linux rootfs; libkrun then boots the generated
disk as a VM under HVF. The container runtime is not the final runtime.

## Compatibility Matrix

| Host | Guest arch | Hypervisor | Kernel path | Root disk | Console | Network |
| --- | --- | --- | --- | --- | --- | --- |
| Linux/x86_64 | x86_64 | KVM | direct `krun_set_kernel()` | raw virtio-blk | `ttyS0` | passt unixstream |
| macOS/ARM64 | aarch64 | HVF | direct `krun_set_kernel()` | raw virtio-blk, optionally APFS clone-backed | `ttyAMA0` | gvproxy v0.8.8 validated without legacy `VFKT` magic |

The first milestone intentionally excludes firmware, PCI, OVMF, GRUB, ISO
installers, and unmodified cloud images that assume virtio-pci or firmware
metadata.

## API Shape

The example uses these OS-mode APIs:

- `krun_set_os_mode(ctx)` selects full-OS boot and disables workload handoff.
- `krun_set_kernel(ctx, ...)` supplies the direct-boot guest kernel.
- `krun_add_disk3(ctx, "root", ...)` attaches the raw root disk.
- `krun_set_os_root(ctx, device, fstype, options)` appends the guest `root=`
  command-line parameters.
- `krun_set_os_init(ctx, path)` optionally overrides the default
  `init=/sbin/init`.
- `krun_add_serial_console_default()` and `krun_set_kernel_console()` connect
  the selected serial console.

`krun_set_root()` and `krun_set_root_disk_remount()` are workload-mode APIs and
are rejected after `krun_set_os_mode()`. `krun_set_root_disk()` can still be
used as a legacy way to add a raw block disk, but `krun_set_os_root()` remains
the OS-mode API that chooses what the guest kernel mounts as `/`.
`krun_add_virtiofs*()` may still add non-root shared filesystems in OS mode, but
the special `KRUN_FS_ROOT_TAG` (`/dev/root`) is rejected so callers cannot
reintroduce a virtio-fs root behind the block-root OS contract.

The `examples/os_mode` launcher exposes this as `--virtiofs TAG=PATH`. Inside
the guest, mount it with `mount -t virtiofs TAG /mountpoint`; the shared
directory is for workspaces or data, not for the guest root filesystem.

## Security Model

Workload mode usually exposes a host directory through virtio-fs and runs
libkrun's guest init as the handoff layer. OS mode instead boots a guest-owned
block root and lets the guest's init become PID 1. This reduces dependence on
virtio-fs for the root filesystem, but the writable disk image becomes durable
guest-controlled state.

For template-based launches, never attach the base image read-write. Use a
per-VM copy or APFS clone and apply host filesystem permissions so the VMM
process can only modify the intended clone. Additional virtio-fs mounts, if
used later for data sharing, keep the same host-filesystem exposure risks as
workload mode.

## Build

From the `examples/` directory:

```sh
make os_mode
```

On macOS the `Makefile` signs the example with the same entitlement file used
by the other libkrun examples.

## macOS Clean-Machine Checklist

For the supported Apple Silicon OS-bundle flow, prepare the host before
building or importing images:

- Install Xcode command-line tools with `xcode-select --install`.
- Install the required Homebrew tools: `brew install llvm lld xz`.
- Install Docker Desktop or Podman. These are used to pull, build, or export
  OCI images and are not the libkrun runtime.
- Build libkrun with block and network support using Homebrew clang/lld:

```sh
LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib \
  PATH=/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:$PATH \
  make BLK=1 NET=1 CLANG=/opt/homebrew/opt/llvm/bin/clang
sudo make BLK=1 NET=1 install
cd examples
make os_mode
```

- Put bundle extraction directories and root-disk outputs on APFS. The macOS
  product path relies on APFS CoW clones for fast per-VM writable disks.
- Use an aarch64 guest kernel and `linux/arm64` bundle images on Apple Silicon.
- Expect the guest console to be `ttyAMA0`; a bundle manifest for macOS/HVF
  should declare that console.
- Use digest-pinned image references with `--strict-digest` for repeatable
  remote bundle launches.
- Treat `docker run` or `podman run` as build/export checks only. A runtime
  pass requires `examples/os_mode` to run as a macOS host process and the
  smoke helper to observe `KRUN_OSMODE:*` markers from the guest VM.

## Clean-Host macOS Prepared Bundle Runbook

This is the intended no-root-disk-build path for a fresh Apple Silicon Mac once
a prepared `libkrun.os-bundle.v1` image is available.

```sh
xcode-select --install
brew install llvm lld xz
```

Install Docker Desktop or Podman, then build and install libkrun and the
host-side launcher:

```sh
LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib \
  PATH=/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:$PATH \
  make BLK=1 NET=1 CLANG=/opt/homebrew/opt/llvm/bin/clang
sudo make BLK=1 NET=1 install
cd examples
make os_mode
```

Choose a digest-pinned prepared OS bundle image and an APFS-backed cache:

```sh
export KRUN_OS_BUNDLE_IMAGE="registry.example.com/libkrun-os/debian-systemd@sha256:..."
export KRUN_OS_BUNDLE_CACHE="$HOME/Library/Caches/libkrun/os-bundles"
mkdir -p "$KRUN_OS_BUNDLE_CACHE"
```

Preflight the clean-host assumptions before the first launch. This does not
pull, load, or boot the image; it checks the macOS/arm64 host metadata, Docker
or Podman availability, digest pinning, APFS placement, absent bundle cache
entry, and fresh release-evidence output path.

```sh
./os_mode_clean_host_preflight.py \
  "$KRUN_OS_BUNDLE_IMAGE" \
  --cache-dir "$KRUN_OS_BUNDLE_CACHE" \
  --output-dir "$KRUN_OS_BUNDLE_CACHE/debian-systemd-release-evidence" \
  --json-output "$KRUN_OS_BUNDLE_CACHE/debian-systemd-preflight.json"
```

Run the OS from the container image. Docker or Podman is used only to extract
the bundle; the VM is launched by the macOS host-side libkrun/HVF process.

```sh
./krun_os_run.py --pull "$KRUN_OS_BUNDLE_IMAGE"
```

The run is valid only if smoke evidence shows the expected root, `ttyAMA0`,
the bundle's expected guest PID 1, readiness, and clean shutdown. To inspect
the lower-level command without launching:

```sh
./krun_os_run.py "$KRUN_OS_BUNDLE_IMAGE" --print-only
```

Remove disposable wrapper-generated APFS clones and smoke evidence after test
runs:

```sh
./krun_os_run.py --clean-cache
```

## Linux/KVM

Example for an x86_64 host and x86_64 guest:

```sh
./os_mode \
  --kernel /path/to/bzImage-or-elf-kernel \
  --kernel-format 1 \
  --root-disk /path/to/root.raw \
  --root-device /dev/vda1 \
  --root-fstype ext4 \
  --guest-init /sbin/init \
  --console ttyS0
```

If the guest root image needs an initramfs:

```sh
./os_mode \
  --kernel /path/to/kernel \
  --initramfs /path/to/initramfs.img \
  --root-disk /path/to/root.raw \
  --root-device /dev/vda1
```

For passt networking, start passt with a unixstream socket and pass it to the
example:

```sh
passt -f --socket /tmp/libkrun-passt.sock

./os_mode \
  --kernel /path/to/kernel \
  --root-disk /path/to/root.raw \
  --passt-socket /tmp/libkrun-passt.sock
```

The guest must run its own DHCP client or static network configuration. OS mode
does not use `init.krun`, so `KRUN_DHCP=1` is not a substitute for guest
networking. TSI socket hijacking and `krun_set_port_map()` are also
workload-mode networking features; OS mode uses explicit virtio-net for normal
network access, while plain vsock without TSI can still be configured when a
guest OS service speaks vsock directly. If using `krun_add_vsock_port*()` in
OS mode, first disable implicit vsock and add an explicit non-TSI vsock device
with `krun_add_vsock(ctx, 0)`.

## macOS/ARM64 HVF

Example for an Apple Silicon host and aarch64 guest:

```sh
./os_mode \
  --kernel /path/to/arch/arm64/boot/Image \
  --kernel-format 0 \
  --root-disk /path/to/root.raw \
  --root-device /dev/vda1 \
  --root-fstype ext4 \
  --console ttyAMA0
```

The macOS path requires an aarch64 guest kernel. The default serial console is
`ttyAMA0` because libkrun's aarch64 serial device is PL011. Validate this
against the exact guest kernel config before treating it as a release gate.

For macOS networking, use a gvproxy or vmnet-helper setup that exposes a
unixgram endpoint compatible with libkrun's vfkit-style unixgram path. The
first smoke backend should be gvproxy/vmnet-helper over `krun_add_net_unixgram`
because that is the macOS-specific backend already modeled by libkrun. Current
gvproxy releases identify vfkit clients from the first Ethernet datagram, so the
example does not send the legacy `VFKT` magic by default. If an older helper
requires that handshake, pass `--gvproxy-vfkit-magic`.

## APFS CoW Root Disks

For fast per-VM disk provisioning on macOS, keep a base raw disk image immutable
and boot clones of that file. APFS clones are metadata-cheap when the source and
destination live on the same APFS volume.

One documented workflow is:

```sh
BASE=/path/to/base-root.raw
VM_DIR=/path/to/vms/vm-001
ROOT=$VM_DIR/root.raw

./os_mode_apfs_clone.sh "$BASE" "$ROOT"

./os_mode \
  --kernel /path/to/arch/arm64/boot/Image \
  --kernel-format 0 \
  --root-disk "$ROOT" \
  --disk-sync relaxed \
  --root-device /dev/vda1 \
  --console ttyAMA0
```

Keep the base image out of the VM launch path except as a clone source. Guest
writes must land in the per-VM clone. Measure APFS clone creation separately
from VM boot time; APFS cloning accelerates disk provisioning, not kernel or
userspace initialization.

For persistent VMs, retain the clone. For ephemeral VMs, delete the clone after
shutdown and record whether allocated size returns to the expected baseline.
If clone creation is unavailable, the helper fails unless `ALLOW_FULL_COPY=1`
is set. A full copy is correct but should be measured separately because it
removes the fast provisioning property.

The helper refuses to overwrite an existing clone path. Generate a fresh
per-VM destination name for each launch, or deliberately retain an existing
clone as that VM's persistent disk.

The example uses `--disk-sync relaxed` by default, matching libkrun's
recommended macOS behavior: guest flush requests are honored through host OS
buffers without forcing every flush through the physical drive cache. Use
`--disk-sync full` when validating stricter durability behavior, and use
`--disk-sync none` only for disposable performance experiments because guest
flushes are ignored.

## Container-Derived Root Disks

For macOS hosts, the expected full-OS image pipeline is:

```text
OCI image -> exported Linux rootfs -> boot contract injection -> raw ext4 base
image -> APFS clone -> libkrun/HVF OS-mode boot
```

The export/build steps can run inside Docker or Podman on macOS because they are
only producing filesystem artifacts. Runtime validation must still run through
`./os_mode` on the macOS host.

The helper for this path is:

```sh
export KRUN_OS_WORKDIR="$HOME/Library/Caches/libkrun/os-mode-work"
mkdir -p "$KRUN_OS_WORKDIR"

./os_mode_build_container_rootfs.py \
  --image alpine:3.23 \
  --output-dir "$KRUN_OS_WORKDIR/container-alpine" \
  --runtime auto \
  --platform linux/arm64 \
  --size-mb 256 \
  --disk-sync relaxed \
  --require-apfs-output \
  --kernel /path/to/vmlinuz-virt \
  --kernel-format 2 \
  --initramfs /path/to/initramfs-virt-with-ext4.gz
```

It writes `rootfs.tar`, `root.raw`, and `manifest.json`. The output directory
must not already contain `rootfs.tar`, `overlay.tar`, `root.raw`,
`vm-root.raw`, or `manifest.json`; use a fresh artifact directory for each
image build so old base images, APFS clone destinations, overlays, and
manifests cannot be mixed with the new run. The manifest records
the schema version, source image SHA-256 identity, builder script SHA-256,
builder image SHA-256 identity, UTC creation timestamp, selected Docker/Podman
runtime and version, build-host metadata, output checksums, requested root disk
size, artifact sizes, build timings, root disk sync mode, guest root device,
filesystem type, optional root mount options, expected root marker source,
guest platform, kernel format,
architecture-specific console, recommended smoke timeout, and the recommended
`./os_mode` command. The
recommended command uses the generated APFS clone destination (`vm-root.raw`)
as `--root-disk`; keep `root.raw` as the immutable base image and clone source.
The builder currently accepts `linux/arm64` and `linux/amd64`; the macOS/HVF
runtime path uses `linux/arm64` and `ttyAMA0`. The default kernel format is `2`
(`KRUN_KERNEL_FORMAT_PE_GZ`) for `linux/arm64` and `1`
(`KRUN_KERNEL_FORMAT_ELF`) for `linux/amd64`; pass `--kernel-format 0` when
launching a raw arm64 `Image`. The example launcher and manifest checker
reject kernel format values outside the `KRUN_KERNEL_FORMAT_*` range. `--runtime
auto` uses a working Podman or Docker runtime; on macOS, Docker Desktop is fine
for this build step even though the final boot still runs under libkrun/HVF.
Pass `--root-options rw,noatime` when the generated launch command should add
`rootflags=rw,noatime`; root device, filesystem type, and root options must be
single kernel-command-line tokens. The container-rootfs builder accepts
`/dev/...`, `PARTUUID=...`, and `UUID=...` root identifiers; prefer
`PARTUUID=...` once the image recipe records a stable partition UUID. The
manual `os_mode` launcher applies the same single-token rule to root, init, and
console values before calling libkrun. The public `krun_set_kernel_console()`
API also enforces this rule when OS mode is active, including when an invalid
console override was set before `krun_set_os_mode()`.
Pass `--expected-root /dev/vda` when the booted guest is expected to report a
different `/proc/mounts` root source from the `--root-device` token; this is
useful when launching with `PARTUUID=...` or `UUID=...` but validating the
resolved virtio-blk device marker.
Pass `--network-smoke` for images that should be validated with guest DHCP:
the generated launch command adds `KRUN_OSMODE_NET=1`, the builder requires a
supported DHCP client, and the manifest records `KRUN_OSMODE: network=up` as an
expected smoke marker.
Pass `--smoke-timeout SECONDS` to override the manifest's recommended
`os_mode_smoke.py` timeout. The default is 120 seconds for systemd images, 45
seconds for network smoke images, and 30 seconds otherwise.
By default, printed smoke replay commands also append
`--poweroff-after-ready` to the smoke-only launch command so the guest can shut
itself down cleanly after emitting readiness. Pass
`--no-smoke-poweroff-after-ready` when the image does not include the
`KRUN_OSMODE_POWEROFF=1` readiness hook and the smoke helper should terminate
the VMM after validation.
When smoke poweroff is enabled, the manifest also records a 60-second
post-readiness exit wait so the printed smoke wrapper fails if the guest does
not actually power off. Override it with
`--smoke-wait-exit-after-ready SECONDS` when a profile needs a different
shutdown budget.
`--require-apfs-output` fails early on macOS if the output directory is not on
APFS, which is required for metadata-cheap clone creation. The builder
normalizes `--output-dir`, `--kernel`, `--initramfs`, and `--overlay-tar` to
absolute paths before writing the manifest so the recorded artifact paths and
generated commands can be replayed from any current working directory.

The builder runs the same manifest validation before it reports success. You
can also validate the generated artifacts again before cloning or booting them:

```sh
./os_mode_manifest_check.py \
  --require-apfs \
  --print-commands \
  --smoke-output smoke.json \
  --perf-output perf.json \
  --write-runbook replay-smoke.sh \
  "$KRUN_OS_WORKDIR/container-alpine/manifest.json"
```

`--print-commands` prints the validated `examples/os_mode_apfs_clone.sh ...`
command first, followed by the clone-backed `examples/os_mode ...` command and
an `examples/os_mode_smoke.py ...` wrapper command that includes the manifest's
recommended timeout, expected root source, console, and smoke markers.
Pass `--perf-output perf.json` to also print an `examples/os_mode_perf.py ...`
timing command with the manifest's recommended timeout, expected root source,
and expected console. The perf command uses the production `os_mode_command`
and does not append the smoke-only `--poweroff-after-ready` flag.
When the manifest's `smoke_poweroff_after_ready` field is true, only the
printed smoke wrapper adds `--poweroff-after-ready`; the printed production
`os_mode_command` stays unchanged. When
`smoke_wait_exit_after_ready_sec` is set, the smoke wrapper also passes
`os_mode_smoke.py --wait-exit-after-ready ...` so clean shutdown becomes part
of the replayed validation.
Manifest-relative artifact paths and repo-relative helper paths are resolved
before printing, so the commands can be replayed from another current working
directory. Command printing also requires any non-null kernel and initramfs
paths in the manifest to exist, so replay/runbook generation fails before a
launch command is printed for missing boot artifacts. It also verifies the
repo-local APFS clone and smoke/perf helper scripts exist before printing
replay commands. Run the printed commands in order so the immutable `root.raw`
remains only the clone source and the VM boots the per-launch `vm-root.raw`
clone.
For repeated launches, pass `--clone-dest vm-root-$(date +%s).raw` to print
commands for a fresh clone path without editing `manifest.json`. `--clone-dest`
is only valid together with `--print-commands`; the clone destination parent
must already exist and the destination itself must not already exist. The
manifest's default APFS clone destination is checked the same way when
commands are printed.
Pass `--smoke-output smoke.json` to include a resolved
`os_mode_smoke.py --output ...` path in the printed smoke wrapper so the replay
run records JSON evidence next to the manifest. `--smoke-output` is only valid
together with `--print-commands`; the output path must not resolve to protected
manifest artifacts such as the base root disk or APFS clone destination, and
its parent directory must already exist. The output file itself must not
already exist; use a fresh path for each replayed validation run.
`--perf-output` follows the same fresh-file and protected-artifact rules as
`--smoke-output`, and the two output paths must differ.
Pass `--write-runbook replay-smoke.sh` to also write an executable shell script
that runs the validated APFS clone command followed by the smoke wrapper. This
keeps the production launch command visible for inspection while making the
validation replay step repeatable. When `--perf-output` is also set, the
runbook appends the printed perf command after the smoke command. The runbook
path must not already exist and must not resolve to the manifest, rootfs tar,
base root disk, overlay tar, or APFS clone destination. The runbook path must
also differ from `--smoke-output` and `--perf-output`, and its parent directory
must already exist.

## OCI-Packaged OS Bundles

For a prepared OS image, the container can be used as the distribution format
instead of as the rootfs source. In that model the image contains a
`/libkrun-os-bundle/` directory with:

```text
manifest.json
root.raw
kernel
initramfs    # optional
```

The macOS host extracts those files, validates their SHA-256 digests and boot
contract, APFS-clones `root.raw`, and runs `examples/os_mode` on the host. The
VMM process must not run inside Docker or Podman.

For a local already-extracted bundle:

```sh
./os_mode_import_container_bundle.py \
  --bundle-dir /path/to/libkrun-os-bundle \
  --clone-dest vm-root.raw \
  --smoke-output smoke.json
```

For an image containing `/libkrun-os-bundle/`, the shortest macOS launch path is:

```sh
./krun_os_run.py --pull example.com/linux-os/libkrun-bundle@sha256:...
```

`krun_os_run.py` stores extracted bundles under
`$KRUN_OS_BUNDLE_CACHE` when set, otherwise
`~/Library/Caches/libkrun/os-bundles` on macOS. It enables
`--reuse-extracted-output-dir`, derives a unique APFS clone path and smoke JSON
path for every launch, and defaults strict digest checking on for
`image@sha256:...` references. Pass `--print-only` to inspect the delegated
importer command without launching the VM.

For an image containing `/libkrun-os-bundle/`, the lower-level importer command
is:

```sh
export KRUN_OS_BUNDLE_CACHE="$HOME/Library/Caches/libkrun/os-bundles"
mkdir -p "$KRUN_OS_BUNDLE_CACHE"

./os_mode_import_container_bundle.py \
  --image example.com/linux-os/libkrun-bundle@sha256:... \
  --output-dir "$KRUN_OS_BUNDLE_CACHE/example-bundle" \
  --runtime auto \
  --pull \
  --strict-digest \
  --clone-dest vm-root.raw \
  --smoke-output smoke.json \
  --perf-output perf.json
```

Add `--run` to create the APFS clone and run the smoke wrapper immediately
from the macOS host:

```sh
./os_mode_import_container_bundle.py \
  --image example.com/linux-os/libkrun-bundle@sha256:... \
  --output-dir "$KRUN_OS_BUNDLE_CACHE/example-bundle-run" \
  --runtime auto \
  --pull \
  --strict-digest \
  --clone-dest vm-root.raw \
  --smoke-output smoke.json \
  --run
```

To create that Docker-compatible bundle context from an already validated
container-derived artifact directory:

```sh
export KRUN_OS_WORKDIR="$HOME/Library/Caches/libkrun/os-mode-work"
mkdir -p "$KRUN_OS_WORKDIR"

./os_mode_publish_container_bundle.py \
  "$KRUN_OS_WORKDIR/container-alpine/manifest.json" \
  --output-dir "$KRUN_OS_WORKDIR/bundle-context"
```

This writes `Containerfile` plus `libkrun-os-bundle/`. Pass
`--image-tag NAME:TAG` to also build the image with Docker or Podman:

```sh
./os_mode_publish_container_bundle.py \
  "$KRUN_OS_WORKDIR/container-alpine/manifest.json" \
  --output-dir "$KRUN_OS_WORKDIR/bundle-context" \
  --image-tag registry.example.com/libkrun-osmode-alpine:arm64
```

To produce a portable image artifact without pushing to a registry, save the
built image as a Docker-compatible archive and write its SHA-256 sidecar:

```sh
./os_mode_publish_container_bundle.py \
  "$KRUN_OS_WORKDIR/container-alpine/manifest.json" \
  --output-dir "$KRUN_OS_WORKDIR/bundle-context" \
  --image-tag libkrun-osmode-alpine:arm64 \
  --archive-output "$KRUN_OS_WORKDIR/libkrun-osmode-alpine-arm64.tar" \
  --archive-sha256-output "$KRUN_OS_WORKDIR/libkrun-osmode-alpine-arm64.tar.sha256" \
  --artifact-manifest-output "$KRUN_OS_WORKDIR/libkrun-osmode-alpine-arm64.artifact.json"
```

A clean macOS host can hand the artifact manifest directly to the release gate:

```sh
./os_mode_clean_host_baseline.py \
  --artifact-manifest "$KRUN_OS_WORKDIR/libkrun-osmode-alpine-arm64.artifact.json" \
  --output-dir "$KRUN_OS_BUNDLE_CACHE/alpine-release-evidence" \
  --preflight-json "$KRUN_OS_BUNDLE_CACHE/alpine-preflight.json" \
```

The baseline helper first verifies the archive checksum and the clean
host/cache/output conditions without loading or booting. It then runs the
release gate, which executes the recorded
`docker load -i ...` or `podman load -i ...` command, then runs the
digest-pinned image reference from the artifact manifest through smoke and perf
validation. The gate copies the preflight JSON into the release-evidence
archive so the verifier can prove the clean-host cache and output paths were
fresh before launch and that the preflight timestamp is not newer than the
release evidence timestamp. For archive-delivered samples, the gate also
copies the artifact manifest itself into `artifact-manifest.json` so the
verifier can check its digest reference and checksum after the evidence
directory is moved. The artifact manifest records the bundle manifest digest,
archive path, archive checksum, load command, run command, preflight command,
clean-cache release-gate command, and clean-host baseline command with
accepted JSON/table output placeholders so the sample is self-describing when
copied outside the build host.

Registry-published, digest-pinned images remain preferred for release gates
because `--strict-digest` can prove exactly which image was consumed.

For a local reproducible test image, use a local tag and then import that tag:

```sh
./os_mode_publish_container_bundle.py \
  "$KRUN_OS_WORKDIR/container-alpine/manifest.json" \
  --output-dir "$KRUN_OS_WORKDIR/bundle-context" \
  --image-tag libkrun-osmode-alpine:arm64

./os_mode_import_container_bundle.py \
  --image libkrun-osmode-alpine:arm64 \
  --output-dir "$KRUN_OS_BUNDLE_CACHE/local-alpine" \
  --runtime auto \
  --pull \
  --clone-dest vm-root.raw \
  --smoke-output smoke.json \
  --run
```

The equivalent wrapper command for a published or local prepared bundle image
is:

```sh
./krun_os_run.py --pull libkrun-osmode-alpine:arm64
```

The publisher packages the immutable base `root.raw`, not a per-VM APFS clone.
It validates the source manifest, copies `kernel`, optional `initramfs`, and
`root.raw`, writes a `libkrun.os-bundle.v1` manifest with final artifact
digests and root-disk allocated-size metadata when available, and rejects
source manifests that launch the immutable base disk directly.
Pass `--push --digest-output bundle-image.txt` with `--image-tag` to push the
image and write the digest-pinned reference, for example
`registry.example.com/libkrun-osmode-alpine@sha256:...`. Consumers should pass
that pinned reference to the importer with `--strict-digest`; strict image
imports reject mutable tags such as `:latest`.

Without `--run`, the importer prints the APFS clone command, host-side
`examples/os_mode` command, and guarded `examples/os_mode_smoke.py` command.
With `--run`, it runs the APFS clone helper and smoke wrapper from the macOS
host. If `--run` is used without `--smoke-output`, the importer writes
`smoke.json` in the extracted bundle directory. After the smoke helper exits,
the importer enriches that JSON with the bundle source image/digest, extracted
bundle path, immutable root disk digest and allocated-size observation, APFS
clone path, host-side `examples/os_mode` command, APFS clone command, and smoke
command. It also records importer-side timing for bundle extraction, APFS clone
creation, smoke validation, post-extraction runtime, and total importer runtime
where applicable. The smoke helper records its launcher PID and the child VMM
process PID, so bundle runtime evidence can show the VMM was spawned by the
host-side smoke helper. Before writing bundle metadata into the smoke JSON, the
importer verifies the smoke evidence recorded `ready=true` and that its parsed
observed root, console, and PID 1 match the bundle manifest.
Allocated size is recorded as host filesystem evidence; it is not required to
match across Docker/Podman extraction because sparse extent layout can change
while SHA-256 and apparent byte size remain stable.

For repeat launches from the same bundle image, keep the extracted output
directory and pass `--reuse-extracted-output-dir` with the same `--image`
reference. Reuse is opt-in: the importer only skips Docker/Podman extraction
when the output directory contains `libkrun-os-bundle/` plus matching import
metadata from the previous extraction. Use digest-pinned image references with
`--strict-digest` for cache entries that should be stable across hosts.

Cache and cleanup policy:

- Treat the extracted bundle directory as a cache of immutable image artifacts.
  It can be reused only with `--reuse-extracted-output-dir` and matching import
  metadata.
- Treat every APFS clone destination as mutable VM state. Delete disposable
  clones after the smoke run, or retain them deliberately as persistent VM
  disks.
- Do not publish or re-import a per-VM clone as a reusable bundle unless that
  guest state is intentionally part of the new image.
- Track `root_disk_allocated_bytes` and smoke evidence allocation fields as
  storage diagnostics, not as cross-runtime equality checks.
- Use a fresh `--clone-dest`, `--smoke-output`, and `--perf-output` for every
  recorded validation run.
- Use `./krun_os_run.py --clean-cache` to remove wrapper-generated disposable
  clone and smoke files from the default cache. Add `--cache-dir PATH` to
  target a non-default cache. Add `--delete-extracted-bundles` only when you
  also want to remove safe extracted bundle entries; entries containing unknown
  files are refused so persistent VM disks are not deleted by default.

The bundle manifest must use `kind: libkrun.os-bundle.v1`, schema version `1`,
a supported platform (`linux/arm64` for macOS/HVF), a supported kernel format,
`ext4` root filesystem metadata, single-token root/init/console values, an
expected PID 1 name, and digest entries for the kernel, optional initramfs, and
root disk. The importer rejects unsafe bundle paths, checksum mismatches, stale
clone/output paths, unsupported platforms, and manifests that allow full-copy
fallback for the default macOS product path. Printed bundle smoke commands pass
`--expect-pid1` to `os_mode_smoke.py` so a bundle can require `systemd`,
`init`, or another known guest PID 1 while still rejecting `init.krun`.
When the importer fails, stderr starts with `diagnostic_category=...` so callers
can distinguish image resolution, extraction, manifest validation, output path,
APFS clone, host launcher, cache reuse, and guest readiness failures before
showing the detailed error text.
Pass `--perf-output perf.json` to also print an `examples/os_mode_perf.py`
command with `--require-pid1-marker`, expected root, and expected console
checks. The perf command uses the production host launch command and does not
append the smoke-only `--poweroff-after-ready` launcher flag.

Release bundle images by digest, not by mutable tag. A releasable bundle should
publish the digest-pinned image reference, bundle manifest, source manifest,
kernel provenance, root disk provenance, and smoke/perf evidence. Digest
pinning is reproducibility, not trust; official or third-party bundle images
should also carry a signature or attestation that binds the image digest to the
manifest and validation evidence before users run them with `--strict-digest`.
The macOS clean-host baseline helper preflights the host, then runs a
digest-pinned bundle image through a clean-shutdown smoke launch, a fresh-clone
perf launch, release-evidence archival, baseline-table rendering, and
release-evidence verification:

```sh
./os_mode_clean_host_baseline.py \
  example.com/linux-os/libkrun-bundle@sha256:... \
  --output-dir "$KRUN_OS_BUNDLE_CACHE/example-bundle-release-evidence" \
  --preflight-json "$KRUN_OS_BUNDLE_CACHE/example-bundle-preflight.json" \
  --accept-json-output "$KRUN_OS_BUNDLE_CACHE/example-bundle-acceptance.json" \
  --accept-table-output "$KRUN_OS_BUNDLE_CACHE/example-bundle-baseline.md" \
  --design-doc-output "$KRUN_OS_BUNDLE_CACHE/example-bundle-design-doc.md" \
  --build-command 'LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib PATH=/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:$PATH make BLK=1 NET=1 CLANG=/opt/homebrew/opt/llvm/bin/clang'
```

From the repository root, the common case can be run through the Makefile:

```sh
make os-mode-clean-host-baseline \
  IMAGE=example.com/linux-os/libkrun-bundle@sha256:... \
  OUTPUT_DIR="$KRUN_OS_BUNDLE_CACHE/example-bundle-release-evidence" \
  PREFLIGHT_JSON="$KRUN_OS_BUNDLE_CACHE/example-bundle-preflight.json" \
  ACCEPT_JSON_OUTPUT="$KRUN_OS_BUNDLE_CACHE/example-bundle-acceptance.json" \
  ACCEPT_TABLE_OUTPUT="$KRUN_OS_BUNDLE_CACHE/example-bundle-baseline.md" \
  DESIGN_DOC_OUTPUT="$KRUN_OS_BUNDLE_CACHE/example-bundle-design-doc.md" \
  BUILD_COMMAND='LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib PATH=/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:$PATH make BLK=1 NET=1 CLANG=/opt/homebrew/opt/llvm/bin/clang'
```

The commands above produce rehearsal evidence unless
`FINAL_RELEASE_BASELINE=1` and an `EVIDENCE_LABEL` are supplied. Use those only
for the final fresh clean-host release-machine run; final mode requires the
accepted JSON, accepted Markdown table, and design-doc snippet outputs.

For an archive-delivered sample, pass `--artifact-manifest` instead of an
image argument. The baseline helper verifies the archive SHA-256 during
preflight, then the release gate loads it into Docker or Podman and uses the
manifest's digest reference for the VM run. The lower-level
`os_mode_clean_host_preflight.py` and `os_mode_release_gate.py
--clean-host-baseline --preflight-json ...` commands remain available when the
two steps need to be run manually.

The gate writes `release-evidence.json`, copied manifest/smoke/perf/preflight
artifacts, `baseline.md`, and `release-gate-summary.json`, then verifies the
archive with the same checker used by `make os-mode-verify-release-evidence`.
The acceptance JSON also has `schema_version=1`, `required_checklist` naming
every required checklist item for that run, `accepted_at_utc`, and an
`evidence_checklist` that ties the accepted row back to archived facts:
`clean cache`, `absent cache entry`, `APFS output`, `macOS arm64 host`,
host-side launcher process
metadata, host-side launch command binding to the APFS clone, build
provenance, bundle provenance, clean-host preflight, release-gate summary
strict-mode fields, guest PID 1, first boot log timing, perf marker timings,
clean poweroff, baseline row timings, and artifact load or registry pull
timing. Acceptance fails if any required checklist item is missing or not
satisfied. Archives
collected before the current release-gate summary contract, including archives
missing `image_was_explicit`, must be regenerated rather than reused as
clean-host release evidence. The baseline table's first timing column is
`Image load/pull/export ms`; archive-delivered samples render `load/-/export`,
and registry-delivered samples render `-/pull/export`. The verifier
regenerates the baseline table from the archive and rejects
stale or hand-edited `baseline.md` content. It also checks that the summary's
recorded release-evidence, baseline-table, and preflight JSON paths match the
archive contents.
When `--accept-json-output` or `--accept-table-output` is supplied, the
baseline helper runs the clean-host acceptance helper after the release gate.
For archive-delivered samples it passes `--artifact`; for registry-delivered
samples it passes `--pull`. The final JSON/table outputs are written only
after strict acceptance succeeds.
When `--design-doc-output` is supplied with `--accept-json-output`, the same
wrapper renders the design-doc snippet from the accepted JSON.
`--evidence-label` and `--final-release-baseline` are valid only with
`--design-doc-output`, and `--design-doc-output` requires
`--accept-json-output`. When `--final-release-baseline` is set, the wrapper
also passes that attestation into the acceptance JSON; the design-doc helper
will not render an `Implemented` audit row without
`final_release_baseline=true`.
Published sample artifact manifests include command templates with placeholders
for `ACCEPTANCE_JSON`, `ACCEPTED_BASELINE_MD`, `DESIGN_DOC_SNIPPET_MD`, and
`RELEASE_EVIDENCE_LABEL`.
For final release baselines, `FINAL_RELEASE_BASELINE=1` requires JSON and
Markdown acceptance outputs so the final attestation and standalone accepted
table are both preserved.

After strict acceptance, render the design-doc-ready table and audit row from
the accepted JSON:

```sh
make -C .. os-mode-design-doc-baseline \
  ACCEPTANCE_JSON="$KRUN_OS_BUNDLE_CACHE/example-bundle-acceptance.json" \
  EVIDENCE_LABEL=example-bundle-release-evidence \
  DESIGN_DOC_OUTPUT="$KRUN_OS_BUNDLE_CACHE/example-bundle-design-doc.md"
```

The audit row remains `Open` unless `FINAL_RELEASE_BASELINE=1` is supplied to
both acceptance and design-doc rendering. Use that flag only for the final
fresh clean-host release-machine archive. Omit `DESIGN_DOC_OUTPUT` when you
want the snippet printed to stdout instead of written as an artifact.

Audit the final artifact set before copying the final row into release notes or
the design doc:

```sh
make -C .. os-mode-audit-final-baseline \
  ACCEPTANCE_JSON="$KRUN_OS_BUNDLE_CACHE/example-bundle-acceptance.json" \
  TABLE_OUTPUT="$KRUN_OS_BUNDLE_CACHE/example-bundle-baseline.md" \
  DESIGN_DOC_OUTPUT="$KRUN_OS_BUNDLE_CACHE/example-bundle-design-doc.md" \
  EVIDENCE_LABEL=example-bundle-release-evidence
```

The audit helper reruns strict evidence verification using the delivery mode
recorded in the accepted JSON, then checks that the accepted Markdown table and
design-doc snippet match that final JSON exactly.

Verify a release-gate archive before copying its `baseline.md` into release
notes or the design-doc clean-host table. From `examples`, use:

```sh
make -C .. os-mode-verify-release-evidence \
  EVIDENCE_DIR="$KRUN_OS_BUNDLE_CACHE/example-bundle-release-evidence"
```

For archive-delivered sample evidence, add `ARTIFACT=1`. To require an
explicit image pull phase for registry evidence, add `PULL=1`.
The default clean-host verifier flags also require build provenance, including
a caller-supplied libkrun build command and generated artifact-load/smoke-import
commands that match `release-gate-summary.json`.

To make the final acceptance step explicit and print the baseline table that
can be copied into release notes or the design doc:

```sh
make -C .. os-mode-accept-clean-host \
  EVIDENCE_DIR="$KRUN_OS_BUNDLE_CACHE/example-bundle-release-evidence" \
  JSON_OUTPUT="$KRUN_OS_BUNDLE_CACHE/example-bundle-acceptance.json" \
  TABLE_OUTPUT="$KRUN_OS_BUNDLE_CACHE/example-bundle-baseline.md"
```

For archive-delivered sample evidence, add `ARTIFACT=1`; for registry evidence
that must prove a pull phase, add `PULL=1`. This helper uses the same strict
clean-cache, absent-cache, APFS, macOS/arm64, perf, clean-poweroff, and
clean-host-preflight checks as the release-evidence verifier before it prints
the table. It also rejects archives that contain artifact-manifest or
explicit-pull evidence when those matching acceptance requirements are not
enabled. `JSON_OUTPUT` and `TABLE_OUTPUT` are optional Make variables; when set,
they are written only after the corresponding acceptance checks pass.

For manual collection after separate smoke/perf runs, archive the evidence with:

```sh
./os_mode_collect_release_evidence.py \
  --bundle-dir "$KRUN_OS_BUNDLE_CACHE/example-bundle/libkrun-os-bundle" \
  --smoke-json "$KRUN_OS_BUNDLE_CACHE/example-bundle/libkrun-os-bundle/smoke.json" \
  --perf-json "$KRUN_OS_BUNDLE_CACHE/example-bundle/libkrun-os-bundle/perf.json" \
  --image-ref example.com/linux-os/libkrun-bundle@sha256:... \
  --output-dir "$KRUN_OS_BUNDLE_CACHE/example-bundle-release-evidence" \
  --build-command 'LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib PATH=/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:$PATH make BLK=1 NET=1 CLANG=/opt/homebrew/opt/llvm/bin/clang'
```

Then render the pull-to-ready baseline table from the archived evidence:

```sh
./os_mode_baseline_table.py \
  --release-evidence "$KRUN_OS_BUNDLE_CACHE/example-bundle-release-evidence"
```

Known-good macOS bundle profiles:

| Bundle profile | Platform | Guest PID 1 | Console | Network | Status |
| --- | --- | --- | --- | --- | --- |
| Alpine/BusyBox smoke rootfs | `linux/arm64` | `init` | `ttyAMA0` | gvproxy validated when matching guest modules are overlaid | validated from APFS clone on macOS/ARM64 HVF |
| Debian `bookworm` systemd rootfs | `linux/arm64` | `systemd` | `ttyAMA0` | gvproxy validated with `udhcpc`, `af_packet`, and `virtio_net` available | validated from APFS clone on macOS/ARM64 HVF |
| Linux/KVM x86_64 smoke artifacts | `linux/amd64` | image-specific | `ttyS0` | passt unixstream | deferred until a Linux host with `/dev/kvm` is available |

Bundle troubleshooting:

Image pull or runtime lookup failures: check Docker Desktop or Podman is
running and that `--runtime` selects the expected tool. For a pure local tag,
confirm the image exists with that runtime. For a remote image, prefer a
digest-pinned reference and `--strict-digest`.

`failed to copy /libkrun-os-bundle`: the image is not an OS bundle image, or
the bundle files were published under the wrong path. Rebuild it with
`os_mode_publish_container_bundle.py` and verify the resulting image contains
`/libkrun-os-bundle/manifest.json`.

The first macOS release path intentionally uses Docker or Podman for `--image`
bundle extraction. That dependency is artifact transport only; the extracted
files are validated on the host, the APFS clone is created on the host, and the
VM runs as a host-side libkrun/HVF process. A future native OCI extractor must
preserve the same digest, path-safety, APFS, launch, and smoke-evidence
invariants before it can replace Docker/Podman.

`--strict-digest with --image requires image@sha256:<digest>`: the importer was
given a mutable tag. Use the publisher's `--push --digest-output` path and pass
the resulting digest-pinned reference to the importer.

`source_digest must be null or a sha256 identity` or
`--strict-digest requires source_digest`: the bundle manifest does not identify
the source OS image immutably. Rebuild the root disk from a source image whose
runtime can report a SHA-256 image ID or repo digest.

`kernel_sha256`, `initramfs_sha256`, or `root_disk_sha256` mismatch: the bundle
files were modified after publishing or the manifest points at the wrong file.
Do not repair this by editing the manifest by hand; regenerate the bundle from
the source artifact manifest.

`bundle directory must be on APFS for clone-backed launch`: move the extracted
bundle to an APFS volume. The macOS product path relies on APFS CoW cloning for
fast per-VM writable roots.

APFS clone creation failures: confirm the source `root.raw` and clone
destination are on the same APFS volume, the destination does not already
exist, and the parent directory is writable by the user running the host-side
launcher.

HVF entitlement or launch failures: rebuild `examples/os_mode` from the
`examples/` directory so the example Makefile signs it with the same entitlement
file used by the other macOS examples.

Guest boot failures: inspect the smoke JSON merged output for the last kernel
line. Common causes are a kernel/initramfs that does not match the guest
modules in the root disk, a missing ext4 or virtio-mmio driver, the wrong
console for the platform, or an unsupported root token.

Readiness-marker failures: verify the guest image contains the injected
`krun-osmode-ready` path or equivalent service, PID 1 is not `init.krun`, and
the manifest's expected root, console, PID 1, and optional network marker match
what the guest actually emits.

`console must be ttyAMA0 for linux/arm64`: the bundle platform and console do
not match the macOS/HVF product contract. Rebuild the bundle for `linux/arm64`
or use the Linux/KVM path for `linux/amd64` artifacts.

`expected_pid1 must not be init.krun` or smoke `pid1-mismatch`: the bundle is
not booting the intended guest OS init. Check the source image init mode,
`/sbin/init`, and the bundle manifest's `expected_pid1`.

The converted image must include or receive:

- `/sbin/init` or an explicit `--guest-init` target.
- `/dev`, `/proc`, `/sys`, and `/run` mount setup.
- console output or getty for `ttyAMA0` on macOS/ARM64.
- optional DHCP/static network setup for `eth0`.
- `KRUN_OSMODE:*` readiness markers for smoke validation.

Plain application containers often fail this contract because they only contain
an app entrypoint, not a bootable OS init. The image builder should reject those
or inject a minimal init for smoke use.

For a distro/systemd rootfs, build a source image such as:

```sh
docker build \
  --platform linux/arm64 \
  -f ../ci/os_mode_debian_systemd.Containerfile \
  -t libkrun-osmode-debian-systemd:bookworm-arm64 \
  ..
```

Then use `--init-mode systemd` instead of the injected smoke init:

```sh
./os_mode_build_container_rootfs.py \
  --image libkrun-osmode-debian-systemd:bookworm-arm64 \
  --output-dir "$KRUN_OS_WORKDIR/debian-systemd" \
  --runtime auto \
  --platform linux/arm64 \
  --size-mb 1024 \
  --disk-sync relaxed \
  --require-apfs-output \
  --require-dhcp-client \
  --init-mode systemd \
  --kernel /path/to/vmlinuz-virt \
  --kernel-format 2 \
  --initramfs /path/to/initramfs-virt-with-ext4.gz
```

In systemd mode the builder validates systemd, ensures `/sbin/init` resolves
inside the guest rootfs, adds the `KRUN_OSMODE:*` readiness service to
`multi-user.target`, enables the platform serial getty when the template exists
(`ttyAMA0` for `linux/arm64`, `ttyS0` for `linux/amd64`), and writes a
modules-load drop-in for the network modules used by the current Alpine kernel
validation path. The generated manifest adds
`--kernel-cmdline 'rw systemd.unit=multi-user.target'` because systemd needs a
writable root filesystem for normal boot.

The systemd adaptation also masks services that are noisy or not useful in this
constrained virtio-mmio profile: `systemd-logind.service`, `apt-daily.timer`,
`apt-daily-upgrade.timer`, `dpkg-db-backup.timer`, and `e2scrub_all.timer`.
Add more masks with `--systemd-mask UNIT`, or pass
`--no-default-systemd-masks` to use only the explicitly requested masks.
Additional mask names must be simple systemd unit basenames such as
`custom.service` or `custom.timer`; names with slashes, whitespace, or missing
unit suffixes are rejected before the Docker/Podman build step. The readiness
service remounts `/` read-write before printing markers. For one-shot validation
runs, pass `--poweroff-after-ready` to `os_mode`; the launcher appends the
validation-only readiness marker so the service asks systemd to power off after
`ready`.

The injected readiness service can also validate normal persistent guest writes
from a container-derived OS image:

- `KRUN_OSMODE_WRITE_TEST=1` writes a boot-id keyed marker under
  `/var/lib/krun-osmode/write-test/` and emits `KRUN_OSMODE: write=ok`.
- `KRUN_OSMODE_WRITE_TEST=1` also probes journald when `logger` and
  `journalctl` are present, emitting `KRUN_OSMODE: journald=ok` after the
  message is readable from the journal.
- `KRUN_OSMODE_APT_UPDATE=1` runs `apt-get update` when `apt-get` is present
  and emits `KRUN_OSMODE: package-manager=apt-update-ok`.

Use these flags against an APFS clone, not the immutable base image. The
validated Debian systemd profile booted the same clone twice with gvproxy,
journald readback, and `apt-get update`; the base image checksum stayed
unchanged while the clone checksum and allocated size changed.

To boot the generated base image quickly, clone it first:

```sh
./os_mode_apfs_clone.sh \
  "$KRUN_OS_WORKDIR/container-alpine/root.raw" \
  "$KRUN_OS_WORKDIR/container-alpine/vm-root.raw"

./os_mode \
  --kernel /path/to/vmlinuz-virt \
  --initramfs /path/to/initramfs-virt-with-ext4.gz \
  --root-disk "$KRUN_OS_WORKDIR/container-alpine/vm-root.raw" \
  --disk-sync relaxed \
  --root-device /dev/vda \
  --root-fstype ext4 \
  --guest-init /sbin/init \
  --console ttyAMA0
```

For networking from a container-derived rootfs, the guest must have both DHCP
userspace and kernel support for `virtio_net` and `AF_PACKET`. The validated
Alpine path used `--overlay-tar` to add `/lib/modules` from the same Alpine
`modloop-virt` that matched the booted `vmlinuz-virt`. Add
`--network-smoke` when building images that are expected to pass the network
smoke test; this also requires a supported DHCP client in the rootfs. Then
launch with:

```sh
./os_mode \
  --kernel /path/to/vmlinuz-virt \
  --initramfs /path/to/initramfs-virt-with-ext4.gz \
  --root-disk /path/to/apfs-cloned-root.raw \
  --root-device /dev/vda \
  --root-fstype ext4 \
  --guest-init /sbin/init \
  --console ttyAMA0 \
  --kernel-cmdline KRUN_OSMODE_NET=1 \
  --gvproxy-socket /path/to/gvproxy.sock
```

If DHCP prints `Address family not supported by protocol`, the rootfs is
missing matching packet-socket or virtio-net kernel modules, or the kernel lacks
that support built in. The container-rootfs builder's injected readiness script
tries to load `failover`, `net_failover`, `af_packet`, and `virtio_net` before
DHCP when matching modules are present in the image. If it prints
`network=missing-dhcp-client`, the image does not contain a supported DHCP
client; for the Debian systemd profile, install `udhcpc`.

## Readiness Markers

Minimal validation images should print these lines during boot:

```text
KRUN_OSMODE: init-started
KRUN_OSMODE: root=<source from /proc/mounts>
KRUN_OSMODE: pid1=<comm and exe for PID 1>
KRUN_OSMODE: console=<active console>
KRUN_OSMODE: network=<optional network result>
KRUN_OSMODE: ready
```

Do not count an OS-mode boot as validated until `pid1` is not `init.krun`, the
root marker matches the configured virtio-blk root or stable root identifier,
and the ready marker appears before the timeout.

The `os_mode_smoke.py` helper runs an `os_mode` command and checks these
markers. Pass `--output` to write a JSON record with elapsed time, the VMM
process exit status after the helper finishes, merged stdout/stderr lines,
detected markers, missing markers, and parsed observed root/PID1/console/network
values. The helper rejects a `pid1` marker that contains `init.krun`; when
`--expect-root` is set, it compares the expected value with the root source
token from `KRUN_OSMODE: root=...`, not a substring of the full line. When
`--expect-console` is set, it requires the active console marker to contain
that console name as a whitespace-delimited token.
The `--output` path must be fresh and its parent directory must already exist,
so smoke evidence is not silently overwritten after the guest boots.

```sh
./os_mode_smoke.py --timeout 30 --expect-root /dev/vda1 --expect-console ttyAMA0 --output smoke.json -- \
  ./os_mode --kernel /path/to/kernel --root-disk /path/to/root.raw
```

## Linux Docker Validation

Run the host-independent checks directly on macOS or Linux:

```sh
make os-mode-checks
```

or run the underlying script:

```sh
ci/os_mode_host_checks.sh
```

These checks compile the launcher normally for syntax and also build a
host-runnable `OS_MODE_PARSE_SELFTEST` variant that exercises argument parsing
and root/init/console token validation without linking libkrun or starting a
guest.

The Linux compile gate can run in a normal Docker container:

```sh
docker build -f ci/os_mode_linux.Dockerfile -t libkrun-os-mode-linux .
docker run --rm -v "$PWD:/workspace/libkrun" libkrun-os-mode-linux
```

Linux/KVM boot validation can also run in Docker, but only on a Linux host that
passes `/dev/kvm` into the container. macOS Docker cannot validate KVM or HVF.
For networking smoke tests, start passt on the Linux host first; omit the
socket bind mount and `KRUN_OSMODE_PASST_SOCKET`/`KRUN_OSMODE_KERNEL_CMDLINE`
environment values for a no-network boot smoke test.

```sh
passt -f --socket /tmp/libkrun-passt.sock

docker run --rm --device /dev/kvm \
  -v "$PWD:/workspace/libkrun" \
  -v /path/to/artifacts:/artifacts:ro \
  -v /tmp/libkrun-passt.sock:/tmp/libkrun-passt.sock \
  -e RUN_KVM_SMOKE=1 \
  -e KRUN_OSMODE_KERNEL=/artifacts/kernel \
  -e KRUN_OSMODE_INITRAMFS=/artifacts/initramfs \
  -e KRUN_OSMODE_ROOT=/artifacts/root.raw \
  -e KRUN_OSMODE_ROOT_DEVICE=/dev/vda \
  -e KRUN_OSMODE_ROOT_FSTYPE=ext4 \
  -e KRUN_OSMODE_ROOT_OPTIONS=rw,noatime \
  -e KRUN_OSMODE_EXPECT_ROOT=/dev/vda \
  -e KRUN_OSMODE_CONSOLE=ttyS0 \
  -e KRUN_OSMODE_EXPECT_CONSOLE=ttyS0 \
  -e KRUN_OSMODE_PASST_SOCKET=/tmp/libkrun-passt.sock \
  -e KRUN_OSMODE_EXPECT_MARKER='KRUN_OSMODE: network=up' \
  -e KRUN_OSMODE_SMOKE_JSON=/artifacts/linux-kvm-smoke.json \
  -e KRUN_OSMODE_KERNEL_CMDLINE=KRUN_OSMODE_NET=1 \
  libkrun-os-mode-linux
```

The Linux validation entrypoint checks that the kernel, root disk, and optional
initramfs paths exist before boot. It also validates `KRUN_OSMODE_ROOT_DEVICE`,
`KRUN_OSMODE_ROOT_FSTYPE`, `KRUN_OSMODE_ROOT_OPTIONS`, and
`KRUN_OSMODE_CONSOLE` as single kernel command-line tokens. By default, the
smoke helper expects the guest's `KRUN_OSMODE: console=...` marker to match
`KRUN_OSMODE_CONSOLE`; set `KRUN_OSMODE_EXPECT_CONSOLE` only when the guest
reports an equivalent but different active console token. If the guest is
booted with a stable root token such as `PARTUUID=...` but `/proc/mounts`
reports the resolved block device, set `KRUN_OSMODE_EXPECT_ROOT` to the marker
value the smoke helper should require. Set `KRUN_OSMODE_PASST_SOCKET` to attach
Linux passt networking through the same Docker/KVM smoke entrypoint; for
container-derived images built by the helper, include `KRUN_OSMODE_NET=1` in
`KRUN_OSMODE_KERNEL_CMDLINE` so the guest readiness script runs DHCP. Set
`KRUN_OSMODE_EXPECT_MARKER` when the smoke test should require an additional
guest marker such as `KRUN_OSMODE: network=up`. Set
`KRUN_OSMODE_SMOKE_JSON` to write the smoke helper JSON result into a mounted
artifact directory for the validation log.

For timing runs, use `os_mode_perf.py` and store the JSON result with the
validation log. The result records timings, detected `KRUN_OSMODE:*` markers,
merged output lines, elapsed time, failure reason when applicable, parsed
observed root/PID1/console/network values, and the VMM process exit code. Pass
`--expect-root` and `--expect-console` when timing a boot that should also
assert the reported root source and active console; the helper always fails if
the PID 1 marker identifies `init.krun`. Pass
`--require-pid1-marker` when timing evidence must prove the guest emitted a
PID 1 marker at all; manifest-generated perf replay commands include this
guard. When `--wait-exit-after-ready` is set, the helper fails if
the VMM process does not exit within that post-ready window, or if it exits
with a nonzero status:
The `--output` path must be fresh and its parent directory must already exist,
so timing evidence is not silently overwritten.

```sh
./os_mode_perf.py --label macos-arm64-busybox --output perf.json -- \
  ./os_mode --kernel /path/to/Image --root-disk /path/to/root.raw
```

## Network Smoke Tests

Linux passt outbound smoke test:

```sh
passt -f --socket /tmp/libkrun-passt.sock

./os_mode_smoke.py --timeout 45 -- \
  ./os_mode \
    --kernel /path/to/kernel \
    --root-disk /path/to/root.raw \
    --kernel-cmdline KRUN_OSMODE_NET=1 \
    --passt-socket /tmp/libkrun-passt.sock
```

To make the helper fail unless networking comes up, add
`--expect-marker 'KRUN_OSMODE: network=up'`.

Inside the guest readiness script, bring up the virtio-net interface with DHCP
and emit `KRUN_OSMODE: network=dhcp-ok` only after an outbound probe succeeds,
for example:

```sh
ip link set eth0 up
udhcpc -i eth0 -q -t 3
wget -q -O /dev/null http://example.com && echo "KRUN_OSMODE: network=dhcp-ok"
```

Host-to-guest forwarding should be validated with a guest listener and the
chosen backend's forwarding mechanism. Record the host command, guest listener
command, and probe result in `design_docs/os_mode_validation_log.md`.

macOS gvproxy/vmnet-helper outbound smoke test:

```sh
# Start the chosen gvproxy/vmnet-helper command so it exposes a unixgram socket.
# Record the exact command in design_docs/os_mode_validation_log.md.

./os_mode_smoke.py --timeout 45 -- \
  ./os_mode \
    --kernel /path/to/arch/arm64/boot/Image \
    --kernel-format 0 \
    --root-disk /path/to/root.raw \
    --console ttyAMA0 \
    --gvproxy-socket /path/to/gvproxy.sock
```

The `--gvproxy-socket` option uses libkrun's unixgram backend with vfkit magic
disabled by default, matching gvproxy v0.8.8. Pass `--gvproxy-vfkit-magic` only
for older helpers that explicitly require the legacy `VFKT` datagram. The exact
gvproxy/vmnet-helper command and socket path must be recorded with the
smoke-test result.

## Manual Console Checks

For serial login validation, boot with `--console ttyS0` on x86_64 or
`--console ttyAMA0` on aarch64, wait for the readiness marker or login prompt,
then type a command such as:

```sh
cat /proc/1/comm
cat /sys/class/tty/console/active
```

For automated persistent-VM validation of a systemd image, build the root disk
with `--systemd-serial-control-shell`. This is validation-only: it masks the
normal platform `serial-getty@...service` instance and `console-getty.service`,
then starts a root shell on the selected platform serial console after
`krun-osmode-ready.service` has printed the readiness markers. Do not use it
for production images.

Then boot without `--poweroff-after-ready` and let the host prove control over
the still-running guest:

```sh
./os_mode_perf.py --timeout 120 --label debian-systemd-persistent-control \
  --control-command 'p=KRUN_OSMODE; echo "$p: control=ok"; poweroff -f' \
  --expect-control-marker 'KRUN_OSMODE: control=ok' \
  --wait-exit-after-ready 60 -- \
  ./os_mode \
    --kernel /path/to/vmlinuz-virt \
    --initramfs /path/to/initramfs-virt-with-ext4.gz \
    --root-disk /path/to/apfs-cloned-root.raw \
    --root-device /dev/vda \
    --root-fstype ext4 \
    --guest-init /sbin/init \
    --console ttyAMA0 \
    --kernel-cmdline 'rw systemd.unit=multi-user.target'
```

For boot-log capture, redirect stdout from the host process:

```sh
./os_mode --kernel /path/to/kernel --root-disk /path/to/root.raw > boot.log
```

On macOS/ARM64 HVF, use the same serial path with an aarch64 guest kernel and
verify that both early boot output and interactive input work through the host
terminal before treating the milestone as complete.

## Troubleshooting

`cannot mount root fs`: confirm the kernel has built-in virtio-mmio,
virtio-blk, and root filesystem support, or provide an initramfs that has those
drivers. Confirm the root device is actually `/dev/vda1`; prefer `PARTUUID=`
once the image recipe supports it.

`no console output`: confirm the example's `--console` value matches the guest
kernel. Use `ttyS0` for the initial x86_64 serial path and `ttyAMA0` for the
initial aarch64 PL011 path. Remove `quiet` from the extra kernel command line
while debugging.

`network interface appears but no DHCP lease`: confirm the host backend is
running, the example was launched with `--passt-socket`, and the guest rootfs
contains and starts a DHCP client. OS mode does not run libkrun's workload init.

`APFS clone is slow or consumes full size immediately`: confirm the base image
and clone are on the same APFS volume and that the copy command used clone
semantics, not a full byte copy.

`systemd boots but repeats service failures`: mask host-hardware, login, or
maintenance units that assume a broader VM device model. The provided Debian
systemd builder mode already masks `systemd-logind.service` and common package
maintenance timers for the validated smoke profile.
