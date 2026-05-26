<picture>
   <source media="(prefers-color-scheme: dark)" srcset="docs/images/libkrun_logo_horizontal_darkmode.png">
   <source media="(prefers-color-scheme: light)" srcset="docs/images/libkrun_logo_horizontal.png">
   <img alt="libkrun logo" src="docs/images/libkrun_logo_horizontal_200.png">
</picture>

# libkrun

```libkrun``` is a dynamic library that allows programs to easily acquire the ability to run processes in a partially isolated environment using [KVM](https://www.kernel.org/doc/Documentation/virtual/kvm/api.txt) Virtualization on Linux and [HVF](https://developer.apple.com/documentation/hypervisor) on macOS/ARM64.

It integrates a VMM (Virtual Machine Monitor, the userspace side of an Hypervisor) with the minimum amount of emulated devices required to its purpose, abstracting most of the complexity that comes from Virtual Machine management, offering users a simple C API.

## Use cases

* [crun](https://github.com/containers/crun/blob/main/krun.1.md): Adding Virtualization-based isolation to container and confidential workloads.
* [krunkit](https://github.com/containers/krunkit): Running GPU-enabled (via [venus](https://docs.mesa3d.org/drivers/venus.html)) lightweight VMs on macOS.
* [muvm](https://github.com/AsahiLinux/muvm): Launching a microVM with GPU acceleration (via [native context](https://www.youtube.com/watch?v=9sFP_yddLLQ)) for running games that require 4k pages.
* OS mode: booting a prepared Linux root disk with a direct-boot guest kernel
  through `krun_set_os_mode()`. This mode is intentionally constrained to
  virtio-mmio devices and prepared images; it does not boot firmware, GRUB, ISO
  installers, or arbitrary cloud images. See
  [examples/os_mode.md](examples/os_mode.md) and
  [design_docs/os_mode_guest_image.md](design_docs/os_mode_guest_image.md).

## Goals and non-goals

### Goals

* Enable other projects to easily gain KVM-based process isolation capabilities.
* Be self-sufficient (no need for calling to an external VMM) and very simple to use.
* Be as small as possible, implementing only the features required to achieve its goals.
* Have the smallest possible footprint in every aspect (RAM consumption, CPU usage and boot time).
* Be compatible with a reasonable amount of workloads.

### Non-goals

* Become a generic VMM.
* Be compatible with all kinds of workloads.

## Variants

This project provides the following variants of the library:

- **libkrun**: Generic variant compatible with all Virtualization-capable systems.
- **libkrun-sev**: Variant including support for AMD SEV (SEV, SEV-ES and SEV-SNP) memory encryption and remote attestation. Requires an SEV-capable CPU.
- **libkrun-tdx**: Variant including support for Intel TDX memory encryption. Requires a TDX-capable CPU.

Each variant generates a dynamic library with a different name (and ```soname```), so both can be installed at the same time in the same system.

## Virtio device support

### All variants

* virtio-console
* virtio-block
* virtio-fs
* virtio-gpu (venus and native-context)
* virtio-net
* virtio-vsock (for TSI and socket redirection)
* virtio-balloon (only free-page reporting)
* virtio-rng


## Networking

In ```libkrun```, networking is provided by two different, mutually exclusive techniques: **virtio-vsock + TSI** and **virtio-net + passt/gvproxy**.

### virtio-vsock + TSI

This is a novel technique called **Transparent Socket Impersonation** which allows the VM to have network connectivity without a virtual interface. This technique supports both outgoing and incoming connections. It's possible for userspace applications running in the VM to transparently connect to endpoints outside the VM and receive connections from the outside to ports listening inside the VM.

#### Enabling TSI

TSI for AF_INET and AF_INET6 is automatically enabled when no network interface is added to the VM. TSI for AF_UNIX is enabled when, in addition to the previous condition, `krun_set_root` has been used to set `/` as root filesystem.

#### Known limitations

- Requires a custom kernel (like the one bundled in **libkrunfw**).
- It's limited to SOCK_DGRAM and SOCK_STREAM sockets and AF_INET, AF_INET6 and AF_UNIX address families (for instance, raw sockets aren't supported).
- Listening on SOCK_DGRAM sockets from the guest is not supported.
- When TSI is enabled for AF_UNIX sockets, only absolute path are supported as addresses.

### **virtio-net + passt/gvproxy**

A conventional virtual interface that allows the guest to communicate with the outside through the VMM using a supporting application like [passt](https://passt.top/passt/about/) or [gvproxy](https://github.com/containers/gvisor-tap-vsock).

#### Enabling virtio-net

Use `krun_add_net_unixstream` and/or `krun_add_net_unixdgram` to add a virtio-net interface connected to the userspace network proxy.

## Security model

The libkrun security model is primarily defined by the consideration that both the guest and the VMM pertain to the same security context. For many operations, the VMM acts as a proxy for the guest within the host. Host resources that are accessible to the VMM can potentially be accessed by the guest through it.

While defining the security implementation of your environment, you should think about the guest and the VMM as a single entity. To prevent the guest from accessing host's resources, you need to use the host's OS security features to run the VMM inside an isolated context. On Linux, the primary mechanism to be used for this purpose is namespaces. Single-user systems may have a more relaxed security policy and just ensure the VMM runs with a particular UID/GID.

While most virtio devices allow the guest to access resources from the host, two of them require special consideration when used: virtio-fs and virtio-vsock+TSI.

### virtio-fs

When exposing a directory in a filesystem from the host to the guest through virtio-fs devices configured with `krun_set_root` and/or `krun_add_virtiofs`, libkrun **does not** provide any protection against the guest attempting to access other directories in the same filesystem, or even other filesystems in the host.

A mount point isolation mechanism from the host should be used in combination with virtio-fs.

In addition, when using virtio-fs, a guest may exhaust filesystem resources such as inode limits and disk capacity. Controls should be implemented on the host to mitigate this.

### OS mode block roots

OS mode boots a guest-owned root filesystem from a block image instead of
running libkrun's workload init from a virtio-fs root. This removes the
workload-mode environment handoff and makes the guest's `/sbin/init` PID 1, but
it also means ordinary Linux guest persistence rules apply to the disk image.
Treat writable root images as guest-controlled state, protect immutable base
images from direct write attachment, and use per-VM copies or APFS clones when
launching isolated guests from a shared template.

### virtio-vsock + TSI

When TSI is enabled, the VMM acts as a proxy for AF_INET, AF_INET6 and AF_UNIX sockets, for both incoming and outgoing connections. For all that matters, the VMM and the guest should be considered to be running in the network context. As such, you should apply on the VMM whatever restrictions you want to apply on the guest.

## Building and installing

### Linux

#### Requirements

* [libkrunfw](https://github.com/containers/libkrunfw)
* A working [Rust](https://www.rust-lang.org/) toolchain
* C Library static libraries, as the [init](init/init.c) binary is statically linked (package ```glibc-static``` in Fedora)
* patchelf

#### Optional features

* **GPU=1**: Enables virtio-gpu. Requires virglrenderer-devel.
* **VIRGL_RESOURCE_MAP2=1**: Uses virgl_resource_map2 function. Requires a virglrenderer-devel patched with [1374](https://gitlab.freedesktop.org/virgl/virglrenderer/-/merge_requests/1374)
* **BLK=1**: Enables virtio-block.
* **NET=1**: Enables virtio-net.


#### Compiling

```
make [FEATURE_OPTIONS]
```

#### Installing

```
sudo make [FEATURE_OPTIONS] install
```

### Linux (SEV variant)

#### Requirements

* The SEV variant of [libkrunfw](https://github.com/containers/libkrunfw), which provides a ```libkrunfw-sev.so``` library.
* A working [Rust](https://www.rust-lang.org/) toolchain
* C Library static libraries, as the [init](init/init.c) binary is statically linked (package ```glibc-static``` in Fedora)
* patchelf
* OpenSSL headers and libraries (package ```openssl-devel``` in Fedora).

#### Compiling

```
make SEV=1
```

#### Installing

```
sudo make SEV=1 install
```

### Linux (TDX variant)

#### Requirements

* The TDX variant of [libkrunfw](https://github.com/containers/libkrunfw), which provides a ```libkrunfw-tdx.so``` library.
* A working [Rust](https://www.rust-lang.org/) toolchain
* C Library static libraries, as the [init](init/init.c) binary is statically linked (package ```glibc-static``` in Fedora)
* patchelf
* OpenSSL headers and libraries (package ```openssl-devel``` in Fedora).

#### Compiling

```
make TDX=1
```

#### Installing

```
sudo make TDX=1 install
```

#### Limitations

The TDX flavor of libkrun only supports guests with 1 vCPU and memory less than or equal to 3072mib.

### macOS

#### Requirements

* A working [Rust](https://www.rust-lang.org/) toolchain
* A host running macOS 14 or newer
* Homebrew packages `llvm`, `lld`, and `xz`

#### Compiling

```
make [FEATURE_OPTIONS]
```

The [init](init/init.c) binary is cross-compiled using clang and lld.
A suitable sysroot is automatically generated by the Makefile from Debian repository.

#### Installing

```
sudo make [FEATURE_OPTIONS] install
```

## Using the library

Despite being written in Rust, this library provides a simple C API defined in [include/libkrun.h](include/libkrun.h)

## Examples

### os_mode

`os_mode` boots a prepared Linux root disk as a guest-owned OS. It uses direct
kernel boot, virtio-mmio devices, a raw virtio-blk root image, and the guest's
own `/sbin/init`; it does not boot firmware, GRUB, ISO installers, or arbitrary
cloud images.

On macOS/ARM64, the preferred container-sourced flow is an OCI-packaged OS
bundle. The container image is the transport format for a complete libkrun OS
artifact; the actual runtime is still a host-side libkrun/HVF VM:

```text
OCI image with /libkrun-os-bundle -> host extraction/validation
  -> APFS CoW per-VM clone -> libkrun/HVF OS-mode boot
```

For a prepared bundle image, use the wrapper with an image reference. It uses a
host cache, reuses matching extracted bundles, creates a fresh APFS clone and
smoke evidence file for each launch, and then delegates to the validating
bundle importer:

```
cd examples
./krun_os_run.py --pull registry.example.com/libkrun-os/debian-systemd@sha256:...
```

To remove wrapper-generated disposable APFS clones and smoke evidence from the
cache later:

```
./krun_os_run.py --clean-cache
```

The lower-level importer exposes every path and validation option directly:

```
cd examples
export KRUN_OS_BUNDLE_CACHE="$HOME/Library/Caches/libkrun/os-bundles"
mkdir -p "$KRUN_OS_BUNDLE_CACHE"

./os_mode_import_container_bundle.py \
  --image registry.example.com/libkrun-os/debian-systemd@sha256:... \
  --output-dir "$KRUN_OS_BUNDLE_CACHE/debian-systemd" \
  --runtime auto \
  --pull \
  --strict-digest \
  --clone-dest vm-root.raw \
  --smoke-output smoke.json \
  --run
```

That command extracts `/libkrun-os-bundle/`, validates the manifest and
artifact digests, creates an APFS clone of the immutable `root.raw`, and starts
`examples/os_mode` as a macOS host process. Docker or Podman is used only to
obtain files from the image; the VMM must not run inside Docker or Podman.

For a release or clean-host baseline run, use the baseline helper. It preflights
the host, then runs the gate helper with the generated preflight JSON. The gate
requires a digest-pinned image, runs smoke and perf launches from fresh APFS
clones, and archives and verifies `release-evidence.json`,
`release-gate-summary.json`, `clean-host-preflight.json`, and `baseline.md`:

```
./os_mode_clean_host_baseline.py \
  registry.example.com/libkrun-os/debian-systemd@sha256:... \
  --cache-dir "$KRUN_OS_BUNDLE_CACHE" \
  --output-dir "$KRUN_OS_BUNDLE_CACHE/debian-systemd-release-evidence" \
  --preflight-json "$KRUN_OS_BUNDLE_CACHE/debian-systemd-preflight.json" \
  --accept-json-output "$KRUN_OS_BUNDLE_CACHE/debian-systemd-acceptance.json" \
  --accept-table-output "$KRUN_OS_BUNDLE_CACHE/debian-systemd-baseline.md" \
  --design-doc-output "$KRUN_OS_BUNDLE_CACHE/debian-systemd-design-doc.md"
```

From the repository root, the same flow is also available as:

```
make os-mode-clean-host-baseline \
  IMAGE=registry.example.com/libkrun-os/debian-systemd@sha256:... \
  OUTPUT_DIR="$KRUN_OS_BUNDLE_CACHE/debian-systemd-release-evidence" \
  CACHE_DIR="$KRUN_OS_BUNDLE_CACHE" \
  PREFLIGHT_JSON="$KRUN_OS_BUNDLE_CACHE/debian-systemd-preflight.json" \
  ACCEPT_JSON_OUTPUT="$KRUN_OS_BUNDLE_CACHE/debian-systemd-acceptance.json" \
  ACCEPT_TABLE_OUTPUT="$KRUN_OS_BUNDLE_CACHE/debian-systemd-baseline.md" \
  DESIGN_DOC_OUTPUT="$KRUN_OS_BUNDLE_CACHE/debian-systemd-design-doc.md"
```

The commands above are suitable for rehearsal evidence. For the final clean
Apple Silicon baseline, add `EVIDENCE_LABEL=...` and
`FINAL_RELEASE_BASELINE=1`; the wrappers then require accepted JSON, accepted
Markdown, and design-doc output paths and will mark the accepted JSON with
`final_release_baseline=true`.

For an archive-delivered sample, use `--artifact-manifest`; the gate verifies
the archive checksum, loads the image, and then runs the digest-pinned reference
recorded in the artifact manifest. Use `--clean-host-baseline` for evidence
intended to satisfy the clean-host baseline; it records and verifies the
underlying clean-cache and absent-cache requirements, and archives the artifact
manifest itself as `artifact-manifest.json`.

The preflight command does not pull, load, or boot anything. It proves the host
is macOS/arm64, Docker or Podman is available, the cache entry is absent, the
evidence output path is fresh, and the relevant paths are on APFS before the
release gate does the expensive work. The release gate copies that preflight
JSON into the evidence archive and the verifier checks it, including that the
preflight timestamp is not newer than the release evidence timestamp.
When `--accept-json-output` or `--accept-table-output` is supplied, the
baseline helper also runs the clean-host acceptance helper after the release
gate and writes those final artifacts only after strict acceptance passes.
When `--design-doc-output` is supplied with `--accept-json-output`, it also
renders the design-doc snippet from the accepted JSON. `EVIDENCE_LABEL` and
`FINAL_RELEASE_BASELINE=1` are valid only with `DESIGN_DOC_OUTPUT`, and
`DESIGN_DOC_OUTPUT` requires `ACCEPT_JSON_OUTPUT`. When
`FINAL_RELEASE_BASELINE=1` is set, the wrapper also marks the acceptance JSON
with `final_release_baseline=true`; the design-doc renderer refuses to print an
`Implemented` row unless that attestation is present.
The wrapper's final JSON summary records the acceptance JSON, accepted table,
and design-doc snippet output paths when those outputs are requested.
Newly published sample artifact manifests include the same placeholders as
command templates: `ACCEPTANCE_JSON`, `ACCEPTED_BASELINE_MD`,
`DESIGN_DOC_SNIPPET_MD`, and `RELEASE_EVIDENCE_LABEL`.

After a release-gate run, audit the archive before treating it as clean-host
evidence. The verifier checks both the JSON evidence and that `baseline.md`
matches the archived evidence, plus the paths recorded in
`release-gate-summary.json`, and the build-provenance commands recorded in the
archive. If you are still in `examples`, run:

```
make -C .. os-mode-verify-release-evidence \
  EVIDENCE_DIR="$KRUN_OS_BUNDLE_CACHE/debian-systemd-release-evidence"
```

For archive-delivered sample evidence, add `ARTIFACT=1`.

To print the accepted clean-host baseline row from the same strict checks:

```
make -C .. os-mode-accept-clean-host \
  EVIDENCE_DIR="$KRUN_OS_BUNDLE_CACHE/debian-systemd-release-evidence" \
  JSON_OUTPUT="$KRUN_OS_BUNDLE_CACHE/debian-systemd-acceptance.json" \
  TABLE_OUTPUT="$KRUN_OS_BUNDLE_CACHE/debian-systemd-baseline.md"
```

For archive-delivered sample evidence, add `ARTIFACT=1`; for registry evidence
that must prove a pull phase, add `PULL=1`. The acceptance helper rejects
archives that contain artifact-manifest or explicit-pull evidence when those
matching requirements are not enabled.
`JSON_OUTPUT` and `TABLE_OUTPUT` are optional; when set, they are written only
after the corresponding acceptance checks pass. The acceptance JSON has
`schema_version=1`, `accepted_at_utc`, `required_checklist` naming every
required checklist item for that run, and an `evidence_checklist` that maps the
accepted baseline back to concrete archived facts such as `clean cache`,
`absent cache entry`, `APFS output`, `macOS arm64 host`, host-side launcher
process metadata, host-side
launch command binding to the APFS clone, build provenance, bundle
provenance, clean-host preflight, release-gate summary strict-mode fields,
guest PID 1, first boot log timing, perf marker timings, clean poweroff,
baseline row timings, and artifact load or registry pull timing. The
acceptance helper fails if any required checklist item is missing or not
satisfied. Archives collected before
the current release-gate summary contract, including archives missing
`image_was_explicit`, must be regenerated rather than reused as clean-host
release evidence.
The baseline table's first timing column is `Image load/pull/export ms`;
archive samples render this as `load/-/export`, while registry samples render
`-/pull/export`.
For final release baselines, `FINAL_RELEASE_BASELINE=1` requires both
`JSON_OUTPUT` and `TABLE_OUTPUT`; the final attestation must live in an
accepted JSON artifact before the design-doc renderer will print an
`Implemented` row, and the standalone accepted Markdown table must be archived
with it.

To render the accepted table plus the design-doc audit row from an accepted
JSON artifact:

```
make -C .. os-mode-design-doc-baseline \
  ACCEPTANCE_JSON="$KRUN_OS_BUNDLE_CACHE/debian-systemd-acceptance.json" \
  EVIDENCE_LABEL=debian-systemd-release-evidence \
  DESIGN_DOC_OUTPUT="$KRUN_OS_BUNDLE_CACHE/debian-systemd-design-doc.md"
```

The audit row stays `Open` by default so rehearsal evidence is not mistaken for
the final release baseline. Add `FINAL_RELEASE_BASELINE=1` to both the
acceptance step and the design-doc rendering step only for the real fresh
clean-host release-machine run. The renderer rejects an `Implemented` row if
the accepted JSON was not created with `final_release_baseline=true`. Omit
`DESIGN_DOC_OUTPUT` to print the snippet to stdout instead of writing an
artifact file.

Before copying a final row into release notes or the design doc, audit the
final artifact set as a group:

```
make -C .. os-mode-audit-final-baseline \
  ACCEPTANCE_JSON="$KRUN_OS_BUNDLE_CACHE/debian-systemd-acceptance.json" \
  TABLE_OUTPUT="$KRUN_OS_BUNDLE_CACHE/debian-systemd-baseline.md" \
  DESIGN_DOC_OUTPUT="$KRUN_OS_BUNDLE_CACHE/debian-systemd-design-doc.md" \
  EVIDENCE_LABEL=debian-systemd-release-evidence
```

That helper rejects non-final accepted JSON, stale accepted tables, stale
design-doc snippets, and acceptance JSON that no longer matches strict
re-verification of the archived evidence directory.

To author a new OS bundle from an ordinary rootfs image, use the lower-level
container-derived root-disk flow:

```text
OCI image -> Docker/Podman rootfs export/build -> raw ext4 base disk
  -> APFS CoW per-VM clone -> libkrun/HVF OS-mode boot
```

Build the example after building/installing libkrun with block support:

```
LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib \
  PATH=/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:$PATH \
  make BLK=1 NET=1 CLANG=/opt/homebrew/opt/llvm/bin/clang
sudo make BLK=1 NET=1 install
cd examples
make os_mode
```

Then build a container-derived root disk and generate a replayable APFS clone
plus smoke-validation runbook:

```
export KRUN_OS_WORKDIR="$HOME/Library/Caches/libkrun/os-mode-work"
mkdir -p "$KRUN_OS_WORKDIR"

./os_mode_build_container_rootfs.py \
  --image alpine:3.23 \
  --output-dir "$KRUN_OS_WORKDIR/container-alpine" \
  --runtime auto \
  --platform linux/arm64 \
  --size-mb 256 \
  --require-apfs-output \
  --kernel /path/to/vmlinuz-virt \
  --kernel-format 2 \
  --initramfs /path/to/initramfs-virt-with-ext4.gz

./os_mode_manifest_check.py \
  --require-apfs \
  --print-commands \
  --smoke-output smoke.json \
  --write-runbook replay-smoke.sh \
  "$KRUN_OS_WORKDIR/container-alpine/manifest.json"

"$KRUN_OS_WORKDIR/container-alpine/replay-smoke.sh"
```

See [examples/os_mode.md](examples/os_mode.md) for the full guest contract,
systemd image flow, APFS clone validation, and macOS networking notes.

### chroot_vm

This is a simple example providing ```chroot```-like functionality using ```libkrun```.

#### Building chroot_vm

To be able to ```chroot_vm```, you need need to build libkrun with the `virtio-block` and `virtio-net` optional features:

```
make BLK=1 NET=1
sudo make BLK=1 NET=1 install
cd examples
make
```

#### Running chroot_vm

To be able to ```chroot_vm```, you need first a directory to act as the root filesystem for your isolated program.

Use the ```rootfs``` target to get a rootfs prepared from the Fedora container image (note: you must have [podman](https://podman.io/) installed):

```
make rootfs
```

Now you can use ```chroot_vm``` to run a process within this new root filesystem:

```
./chroot_vm ./rootfs_fedora /bin/sh
```

If the ```libkrun``` and/or ```libkrunfw``` libraries were installed on a path that's not included in your ```/etc/ld.so.conf``` configuration, you may get an error like this one:

```
./chroot_vm: error while loading shared libraries: libkrun.so: cannot open shared object file: No such file or directory
```

To avoid this problem, use the ```LD_LIBRARY_PATH``` environment variable to point to the location where the libraries were installed. For example, if the libraries were installed in ```/usr/local/lib64```, use something like this:

```
LD_LIBRARY_PATH=/usr/local/lib64 ./chroot_vm rootfs_fedora/ /bin/sh
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on submitting changes.

## Status

```libkrun``` has achieved maturity and starting version ```1.0.0``` the public API is guaranteed to be stable, following [SemVer](https://semver.org/).

## Getting in contact

The main communication channel is the [libkrun Matrix channel](https://matrix.to/#/#libkrun:matrix.org).

## Acknowledgments

```libkrun``` incorporates code from [Firecracker](https://github.com/firecracker-microvm/firecracker), [rust-vmm](https://github.com/rust-vmm/) and [Cloud-Hypervisor](https://github.com/cloud-hypervisor/).
