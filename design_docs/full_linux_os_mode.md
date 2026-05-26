# Full Linux OS Mode for libkrun

## Status

Implementation started, and the macOS/ARM64 HVF container-to-OS path is the
primary product path being driven to completion. This document describes a
scoped path for running a complete Linux userspace on libkrun while preserving
macOS/ARM64 HVF support and avoiding a broad Cloud Hypervisor or QEMU
replacement effort.

The user-facing macOS requirement is: a user on an Apple Silicon Mac can point
libkrun tooling at a Linux OS container image and get a running Linux OS whose
own `/sbin/init` or systemd is PID 1. The container image is the source,
packaging, and distribution unit; the runtime is still a macOS host-side
libkrun/HVF VM.

Current product interpretation: "run a Linux OS in a container from a macOS
host" means the input UX is a container image reference, while the running
instance is a libkrun/HVF virtual machine created by a macOS host process. The
supported happy path is a prepared `libkrun.os-bundle.v1` OCI image containing
`/libkrun-os-bundle/manifest.json`, `root.raw`, `kernel`, and optional
`initramfs`. The macOS helper pulls or loads that image, extracts and verifies
only the bundle files, creates a fresh writable APFS CoW clone of the immutable
`root.raw`, and boots that clone with libkrun OS mode. Docker Desktop or Podman
may be used for image transport and Linux filesystem authoring, but they are
not the production runtime and a successful `docker run` is not validation for
this requirement.

Implemented in the first slice:

- `krun_set_os_mode()` public API and internal `BootMode` state.
- `krun_set_os_root()` public API and OS root command-line state.
- `krun_set_os_init()` public API for alternate guest init paths.
- Separate workload and OS command-line builders.
- OS-mode start-path validation for direct-kernel boot and configured OS root.
- Immediate rejection of several workload-only APIs after OS mode is enabled.
- Unit tests for workload command-line preservation and OS-mode command-line generation.
- Minimal `examples/os_mode.c` direct-kernel OS boot example.
- `examples/os_mode_apfs_clone.sh` helper for macOS APFS clone-backed root disks.
- `examples/os_mode.md` usage, guest contract, APFS workflow, readiness markers, and troubleshooting.
- macOS/ARM64 HVF boot validation with an Alpine aarch64 root disk.
- macOS gvproxy v0.8.8 networking validation through the unixgram backend.
- APFS clone-backed root disk validation, including guest-write isolation.
- `examples/os_mode_build_container_rootfs.py`, which builds a raw ext4
  OS-mode root disk from an OCI/container image on a macOS host by using Docker
  or Podman only for Linux filesystem export/build steps.
- Explicit manifest validation for container-derived OS roots, including source
  image digest, builder image digest, builder/runtime identity,
  platform-specific console, kernel format, APFS output metadata, and generated
  launch/clone commands.
- API hardening so OS-mode root/init values appended to the kernel command line
  must be single tokens and cannot smuggle extra kernel arguments via
  whitespace.
- Container-rootfs builder and manifest-checker hardening so macOS
  container-derived root disks fail before launch if their root device or
  filesystem type would be rejected by the OS-mode C API.
- Container-rootfs builder and manifest support for optional root mount options
  that become `rootflags=...` in OS mode, with the same single-token validation
  used by the C API.
- Container-rootfs builder and manifest support for stable single-token root
  identifiers (`PARTUUID=...` and `UUID=...`) in addition to `/dev/...`, keeping
  the macOS container-derived path aligned with the recommended robust-image
  root naming contract.
- macOS/ARM64 HVF boot validation from an APFS clone of a container-derived
  Alpine aarch64 root disk.
- macOS gvproxy networking validation from a container-derived Alpine root disk
  after adding the matching guest kernel module overlay.
- Debian `bookworm` systemd source-image recipe, `--init-mode systemd` rootfs
  adaptation, APFS clone boot on macOS/ARM64 HVF, and readiness validation with
  PID 1 as systemd.
- macOS gvproxy networking validation from a container-derived Debian systemd
  root disk after adding `udhcpc` and directly loading matching packet-socket
  and virtio-net guest modules before DHCP.
- `examples/os_mode --poweroff-after-ready`, a reusable validation launcher
  option that appends the guest readiness poweroff marker without requiring
  production commands to include that marker in their kernel command line.
- `examples/os_mode_manifest_check.py --print-commands`, which prints the
  validated APFS clone command followed by the clone-backed `examples/os_mode`
  launch command and a smoke wrapper that checks the manifest's expected root
  source, console, timeout, and markers, with optional `--clone-dest` and
  `--smoke-output` overrides for fresh per-launch clone paths and JSON smoke
  evidence. It can also print guarded `examples/os_mode_perf.py` replay
  commands that require expected root, console, and PID 1 markers before
  accepting timing evidence. Smoke replay commands can append the
  validation-only `--poweroff-after-ready` launcher flag without changing the
  printed production launch command, and can require the VMM process to exit
  after readiness so clean shutdown is part of the replayed evidence. The
  manifest checker can also write an executable clone-plus-smoke runbook, or a
  clone-plus-smoke-plus-perf runbook when `--perf-output` is provided.
- Configurable systemd unit masks in the container rootfs builder through
  `--systemd-mask UNIT` and `--no-default-systemd-masks`, with the existing
  constrained-VM mask list preserved as the default and mask unit names
  validated before the Docker/Podman build step.
- Debian systemd macOS profile decision: continue using the known-good Alpine
  aarch64 virt kernel/initramfs for now. The Debian container-derived rootfs is
  treated as userspace only; a Debian-owned kernel/initramfs is a separate
  future profile.
- APFS clone-backed Debian systemd repeated-write validation: a per-VM clone
  survived repeated macOS/ARM64 HVF boots while systemd/journald and
  `apt-get update` wrote guest state into the clone, the base image checksum
  stayed unchanged, and clone allocated size growth was recorded.
- Validation-only persistent systemd control plumbing: the container-rootfs
  builder can enable a root shell on the selected platform serial console after readiness, and
  `examples/os_mode_perf.py` can send serial control commands and require a
  control marker before shutting the guest down.
- Larger-root APFS storage-growth baseline: a 4 GiB sparse Debian systemd root
  disk was APFS-cloned, booted on macOS/ARM64 HVF, and measured after DHCP,
  journald write/readback, readiness marker write, and `apt-get update`.
- Initial `examples/os_mode_import_container_bundle.py` helper for
  `libkrun.os-bundle.v1` OCI-packaged OS bundles, including Docker/Podman
  bundle extraction, manifest and digest validation, APFS clone command
  generation, host-side launch/smoke command generation, and host-independent
  positive/negative checks.
- Initial `examples/os_mode_publish_container_bundle.py` helper, which turns a
  validated container-derived artifact manifest into a Docker-compatible
  `libkrun-os-bundle/` context with immutable `root.raw`, `kernel`, optional
  `initramfs`, final artifact digests, a scratch `Containerfile`, optional
  Docker/Podman image build, and host-independent validation checks.
- `examples/os_mode_smoke.py --expect-pid1` and bundle importer wiring so
  OCI-packaged OS bundle smoke commands can require the manifest's expected
  guest PID 1 instead of only rejecting `init.krun`.
- Release-evidence process proof for the macOS host runtime path: smoke JSON
  records the host smoke helper PID, its launched `examples/os_mode` process
  PID, and the parent/child relationship; release evidence preserves those
  fields, the verifier rejects missing or mismatched process metadata, and the
  clean-host acceptance checklist exposes this as a named acceptance item.
- Release-evidence command binding for the macOS host runtime path: the
  verifier now requires the archived smoke command, release-evidence summary,
  APFS clone command, and executed `examples/os_mode` command to agree. The
  accepted archive must show that the smoke helper launched host-side
  `examples/os_mode` against the APFS clone destination produced from
  `root.raw`; an archive with mismatched smoke command metadata is rejected.
  The verifier also binds those paths back to the extracted bundle directory,
  bundle `root.raw` digest, bundle platform, and digest-pinned image reference,
  so a same-basename `root.raw` from outside the extracted bundle is not
  accepted as proof. It also compares the release-evidence bundle summary and
  archived smoke bundle source identity back to the bundle manifest, including
  source image, source digest, root disk digest, kernel digest, and initramfs
  digest.
- Bundle importer smoke-evidence enrichment: `--run` writes smoke JSON by
  default when no `--smoke-output` is supplied and annotates smoke output with
  source image identity, extracted bundle path, immutable root disk digest, APFS
  clone path, host launch command, APFS clone command, and smoke command.
- Bundle importer `--perf-output` command printing, which emits a guarded
  `examples/os_mode_perf.py` replay command with expected root, expected
  console, and required PID 1 marker checks while leaving smoke-only poweroff
  behavior out of the perf command.
- Bundle root-disk allocated-size tracking: the publisher records
  `root_disk_allocated_bytes` when the host exposes block allocation, the
  importer validates its type/range when present, and enriched smoke evidence
  records the observed allocation for the immutable bundle root disk after
  extraction. Exact allocated size is not treated as a portable invariant
  across Docker/Podman extraction.
- Digest-pinned remote bundle policy: the publisher can build a local image tag,
  optionally push it, print and write the resulting `image@sha256:...`
  reference, and the importer rejects mutable image tags when `--strict-digest`
  is used with `--image`.
- Portable sample bundle archive path: the publisher can save a built bundle
  image to a Docker-compatible archive with `--archive-output` and write a
  SHA-256 sidecar with `--archive-sha256-output`. It can also write
  `libkrun.os-bundle.artifact.v1` JSON with `--artifact-manifest-output`,
  tying together the bundle manifest digest, image tag, optional registry
  digest, archive path/checksum/size, load command, run command, clean-host
  baseline command, accepted output placeholders, and release gate commands.
  Clean-cache release-gate commands include
  `--require-clean-cache`, and archive manifests include an
  `--artifact-manifest` release-gate form for copied sample artifacts.
  `examples/os_mode_release_gate.py --artifact-manifest` verifies the archive
  checksum and loads the image before running smoke/perf. This gives the
  project a durable non-`/private/tmp` distribution fallback when registry
  publishing is unavailable, but registry-published digest-pinned images remain
  the preferred release artifact.
- Bundle runtime evidence metadata: the smoke helper records launcher and child
  VMM PIDs, and the bundle importer records extraction, APFS clone, smoke, and
  total importer timing in enriched smoke JSON.
- Pull-to-launch OCI OS bundle validation on macOS/ARM64 HVF: a real
  `linux/arm64` Debian systemd bundle image was built locally, extracted on the
  macOS host without rebuilding `root.raw`, APFS-cloned, booted under
  libkrun/HVF, validated as PID 1 `systemd`, and cleanly powered off. Evidence
  is recorded in
  `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-run-image1/libkrun-os-bundle/smoke-run-image1.json`
  and
  `/private/tmp/libkrun-osmode-debian-systemd-bundle-import-run-image1/libkrun-os-bundle/perf-run-image1.json`.
- macOS epoll shim hardening for redirected serial stdin: failed `kevent`
  add/modify operations now return `io::Error` instead of aborting, allowing
  the existing serial-input registration warning path to handle non-pollable
  stdin while the guest still boots.
- Smoke and perf marker parsing now accepts `KRUN_OSMODE:` markers embedded in
  kernel/journald-prefixed serial lines, matching the observed Debian systemd
  output path.
- Bundle importer reuse mode: `--reuse-extracted-output-dir` lets repeat
  launches skip Docker/Podman extraction only when the existing output
  directory contains `libkrun-os-bundle/` and import metadata matching the same
  image reference. This addresses the large-bundle caching requirement without
  weakening the default fresh-output safety checks.
- Bundle importer and release-gate timing evidence now separates archive image
  load, registry image pull, source rootfs export, bundle extraction,
  `apfs_clone`, `smoke`, `post_extraction_run`, and true `importer_total`
  fields so container transport, APFS provisioning, and host launch/runtime
  costs are not confused.
- Smoke and perf evidence now record parsed observed marker values
  (`observed_root`, `observed_pid1`, `observed_console`, `observed_network`,
  and full marker payloads) in addition to raw merged output, so runtime
  evidence directly shows which root, init, console, and network state the
  guest reported.
- Bundle smoke-evidence enrichment now validates the structured observed root,
  console, and PID 1 values against the bundle manifest before adding bundle
  metadata, so stale or edited smoke JSON cannot be promoted to successful
  bundle runtime evidence.
- `examples/krun_os_run.py`, a product-facing prepared-bundle wrapper that
  accepts an image reference, derives the macOS bundle cache location, reuses
  matching extracted bundles, generates unique per-launch APFS clone and smoke
  evidence paths, defaults strict digest checking on for digest-pinned image
  references, and delegates validation and launch to
  `examples/os_mode_import_container_bundle.py`.
- `examples/krun_os_run.py --clean-cache`, which removes only
  wrapper-generated ephemeral APFS clones and smoke evidence by default, and
  removes extracted bundle cache entries only with an explicit
  `--delete-extracted-bundles` request after refusing entries that contain
  unknown files.
- `examples/os_mode_collect_release_evidence.py`, which archives the bundle
  manifest, source manifest, smoke/perf JSON, optional clean-host preflight
  JSON, optional `libkrun.os-bundle.artifact.v1` manifest, host metadata, APFS
  metadata, build commands, digest-pinned image reference, observed OS-mode
  markers, optional artifact-load timing, and timing evidence for macOS release
  gates.
- `examples/os_mode_baseline_table.py`, which converts release evidence or
  direct smoke/perf JSON into a Markdown table covering image load/pull/export,
  bundle extraction, APFS clone, first output, root/PID 1/ready markers, clean
  poweroff, and total launch time.
- `examples/os_mode_release_gate.py`, which turns a digest-pinned sample image
  reference or a `libkrun.os-bundle.artifact.v1` archive manifest into the
  required macOS release evidence: optional archive checksum verification and
  timed image load, explicit pull/extract smoke launch for registry images,
  fresh-clone perf launch, release-evidence archive, `baseline.md`, and
  `release-gate-summary.json`. The gate also supports
  `--require-clean-cache` so release runs can prove the derived bundle cache
  entry was absent or empty before extraction, and
  `--require-cache-entry-absent` for stricter cache proof. The
  `--clean-host-baseline` shortcut enables the strict clean-host baseline
  requirements, requires an archived `--preflight-json`, and rejects registry
  runs that skip pulling. After writing the
  archive, the gate invokes the release-evidence verifier and fails the run if
  the generated evidence does not satisfy the expected
  macOS/APFS/perf/clean-poweroff invariants.
- `examples/os_mode_verify_release_evidence.py`, which independently verifies
  release-gate archives before their `baseline.md` is treated as clean-host
  evidence. It checks digest-pinned image identity, copied artifact checksums,
  artifact load command and load timing when required, caller-supplied build
  command provenance when required, APFS/macOS/arm64 metadata when required,
  clean-cache preflight state, archived clean-host preflight JSON, smoke
  markers, perf timings, and clean poweroff. It also regenerates `baseline.md`
  from the archived release evidence and rejects stale or hand-edited baseline
  tables.
- `examples/os_mode_clean_host_acceptance.py`, which wraps the strict
  clean-host verifier flags and prints the accepted `baseline.md` table from a
  completed release-evidence archive so release notes and this design doc use
  only mechanically checked timing rows. Its acceptance checklist also exposes
  build provenance and the release-gate summary contract as named items,
  including `clean_host_baseline=true`, clean-cache requirements,
  `image_was_explicit`, the preflight command's positional-image mode, and the
  archived release-evidence, baseline-table, and preflight-JSON path bindings.
- `examples/os_mode_clean_host_baseline.py --accept-json-output ...` and
  `--accept-table-output ...`, which optionally run the strict acceptance
  helper after preflight and release-gate completion so a clean-host run can
  produce final accepted JSON and Markdown table artifacts in one command.
  `--design-doc-output ...` can also render the design-doc snippet from that
  accepted JSON after strict acceptance succeeds.
- [x] Make the release-evidence verifier check that
  `release-gate-summary.json` points at the archived `release-evidence.json`,
  `baseline.md`, and the same preflight JSON that was copied into the archive.
- [x] Archive and verify the `libkrun.os-bundle.artifact.v1` manifest for
  archive-delivered clean-host gates, including its SHA-256, source path,
  `kind`, and `digest_ref`.
- `make os-mode-verify-release-evidence EVIDENCE_DIR=...`, which wraps the
  verifier with the default clean-host acceptance flags. `ARTIFACT=1` also
  requires archive-manifest and archive-load proof, and `PULL=1` requires an
  explicit pull phase for registry evidence.
- `make os-mode-accept-clean-host EVIDENCE_DIR=...`, which wraps the
  clean-host acceptance helper and prints the mechanically accepted baseline
  table. `ARTIFACT=1` and `PULL=1` map to the helper's archive and registry
  proof requirements. `JSON_OUTPUT=...` and `TABLE_OUTPUT=...` map to the
  helper's `--json-output` and `--table-output`, and are written only after the
  same strict checks pass.
- `make os-mode-design-doc-baseline ACCEPTANCE_JSON=...`, which consumes the
  accepted JSON and prints the Markdown table plus replacement completion-audit
  row for this design doc, or writes it to `DESIGN_DOC_OUTPUT=...` when an
  artifact path is supplied. The row stays `Open` unless
  `FINAL_RELEASE_BASELINE=1` is supplied for the actual final clean-host run.
  It also requires `final_release_baseline=true` in the accepted JSON before
  rendering an `Implemented` row, so a renderer flag alone cannot promote local
  rehearsal evidence. It refuses rejected or stale acceptance JSON, missing
  checklist items, failed checklist items, and baseline tables without the
  required timing columns.
- `examples/os_mode_final_baseline_audit.py` and
  `make os-mode-audit-final-baseline`, which audit the final artifact set as a
  group. The helper rejects non-final accepted JSON, stale accepted Markdown
  tables, stale design-doc snippets, and accepted JSON that no longer matches
  strict re-verification of the archived evidence directory.
- Host-independent negative bundle checks now cover the importer CLI rejecting
  valid-layout bundles with the wrong platform, root disk digest, console, or
  expected PID 1 before launch commands are printed, and smoke-evidence
  enrichment rejecting `init.krun`, wrong-root, wrong-console, wrong-PID1, and
  not-ready evidence before bundle metadata is added.
- The bundle importer now prints a stable `diagnostic_category=...` line before
  fatal errors. Categories distinguish cache reuse, image resolution, image
  extraction, manifest validation, output path, APFS clone, host launcher, and
  guest readiness failures while preserving the existing detailed error text.

Deferred or intentionally out of first local milestone:

- Linux/KVM runtime boot and networking validation, until a real Linux host or
  Linux CI runner with `/dev/kvm` is available.
- Production snapshot/restore implementation.
- Production-grade guest image build tooling beyond the documented Alpine
  smoke artifacts, container-rootfs helper, and rootfs recipes.

Current completion assessment:

- The macOS product path is implemented and validated for the intended meaning
  of "run a Linux OS from a container on macOS": Docker or Podman supplies and
  exports the OCI image rootfs, the helper converts it into a raw ext4 OS root
  disk, APFS creates a fast writable per-VM clone, and libkrun/HVF boots that
  clone with the guest OS init as PID 1.
- The macOS path has validation evidence for Alpine BusyBox-style init, Debian
  systemd, APFS clone isolation, gvproxy networking, clean shutdown, persistent
  serial control, repeated guest writes, package-manager writes, and timing
  separated into image build, disk provisioning, and guest boot phases. Final
  accepted clean-host baseline evidence is recorded under
  `release-evidence-artifact-final-clean-host-20260519b`.
- The feature should not be called complete across the whole design until the
  deferred Linux/KVM runtime gates run on a real Linux host or Linux CI runner
  with `/dev/kvm`: boot, root-source, PID 1, console, networking, and shutdown.
- Workload-mode runtime regression should be re-run when the matching
  `libkrunfw` artifact is available. Host-independent compile, parser, manifest,
  helper, and command-line compatibility checks are already wired into
  `make os-mode-checks`.
- Any future production snapshot/restore work is an optimization track, not a
  blocker for the current container-sourced macOS OS-mode flow.
- The OCI-packaged OS-bundle path is now the normal macOS user experience in
  this tree: a user can provide a local or remote container image reference
  containing the complete Linux OS bundle, and the host tooling extracts,
  validates, APFS-clones, and boots that OS through libkrun/HVF without a
  separate Linux machine or a root-disk rebuild on the macOS host.
- A successful macOS implementation must therefore prove the complete
  container-to-host-VM chain: image resolution, bundle extraction, manifest and
  digest validation, APFS clone creation, host-side HVF launch, guest-owned
  PID 1, readiness, and clean shutdown. A successful `docker run` on macOS is
  explicitly not proof of this capability.

Local completion audit:

| Requirement | Local evidence | Remaining work |
| --- | --- | --- |
| Boot a guest-owned Linux OS instead of `init.krun` | `krun_set_os_mode()`, OS command-line builder, `examples/os_mode`, and macOS/HVF smoke evidence showing PID 1 `init` and `systemd` | Linux/KVM runtime proof deferred until `/dev/kvm` host |
| Run a Linux OS from a container on macOS | `examples/os_mode_build_container_rootfs.py` builds APFS-cloneable raw roots from OCI images; Alpine and Debian systemd roots boot under HVF; final clean-host baseline evidence `release-evidence-artifact-final-clean-host-20260519b` is accepted with `final_release_baseline=true` | Linux/KVM runtime proof remains deferred until `/dev/kvm` host |
| Consume an entire OS packaged as a container image on macOS | `examples/os_mode_publish_container_bundle.py`, `examples/os_mode_import_container_bundle.py --image ... --run`, and `examples/krun_os_run.py IMAGE`; durable archive artifact exists under `os_mode_artifacts/debian-systemd-bookworm-arm64/` | Registry-published digest-pinned sample image remains preferred before external release |
| Use APFS CoW for fast per-VM root startup | `examples/os_mode_apfs_clone.sh`, manifest APFS checks, clone timing, base checksum stability, repeated clone validation | Production cache eviction policy belongs in caller/product layer |
| Validate progress continuously on macOS | `make os-mode-checks`, macOS/HVF smoke/perf JSON, validation log, structured observed root/PID1/console/network evidence | CI cannot run HVF unless Apple Silicon runner is available |
| Defer Linux-host-only work explicitly | Linux/KVM runtime gates and passt networking are marked deferred throughout this document and in `os_mode_validation_log.md` | Run the documented Docker/KVM smoke path on a real Linux host |

## Problem

libkrun is optimized for starting a single workload inside a small Linux guest. The current public API configures a root filesystem, an executable, arguments, environment, and resource limits, then `krun_start_enter()` builds a kernel command line that forces libkrun's guest init:

```text
<DEFAULT_KERNEL_CMDLINE> init=/init.krun <KRUN_* environment> -- <workload args>
```

That model is a poor fit for a full Linux OS because PID 1 is always `init.krun`, the default command line includes workload-oriented options such as `nomodule`, `console=hvc0`, and `rootfstype=virtiofs`, and guest startup depends on libkrun-specific environment handoff.

The goal is not to boot arbitrary ISO installers or become a generic VMM. The goal is to run a full Linux distribution userspace, with its own `/sbin/init` or systemd as PID 1, from a prepared root disk, on Linux/KVM and macOS/ARM64 HVF.

For macOS, a supported image source must include OCI/container images. The
container image supplies the Linux userspace/root filesystem, but it is not the
runtime isolation boundary. The macOS host uses Docker or Podman as a Linux
export/build environment, converts the exported rootfs into a raw ext4 root
disk, creates APFS CoW clones for fast per-VM launch, and then runs the result
as a libkrun OS-mode VM under HVF.

The required macOS user story is therefore "run a Linux OS sourced from a
container image", not "run Docker as the production sandbox." A user on macOS
must be able to point the tooling at a local or remote OCI image, produce a
bootable raw root disk without a separate Linux machine, APFS-clone that disk
for a near-instant per-VM writable root, and boot the clone with
`examples/os_mode` so the guest's own `/sbin/init` becomes PID 1. Docker Desktop
or Podman can be required for image export and ext4 image construction on
macOS; they cannot be the proof that libkrun can run the OS.

The phrase "run a Linux OS in a container from a macOS host" means this
container-sourced VM workflow:

```text
OCI/container image on macOS
  -> Docker/Podman export and Linux-side rootfs mutation
  -> raw ext4 base root disk
  -> APFS CoW per-VM clone
  -> libkrun OS-mode VM under HVF
  -> guest-owned /sbin/init or systemd as PID 1
```

The container runtime is allowed to do artifact construction because it already
provides Linux filesystem semantics on macOS. It is not the production runtime
and it is not enough for validation; the final boot must be a libkrun/HVF VM on
the macOS host.

Product decision: the end-user macOS launch unit is a prepared OCI image that
contains a complete libkrun OS bundle. The happy path must not ask the user to
separately provide `root.raw`, a kernel, an initramfs, or a Linux build host.
Those files may be produced by project tooling and packaged into the image, but
the consumption path is one container image reference in and one host-side
libkrun/HVF Linux OS VM out. Ordinary distro or application container images
remain valid authoring inputs only after they are converted into a bootable OS
bundle.

The minimum supported user experience on Apple Silicon is:

```text
macOS host + Docker/Podman or native OCI extractor
  -> ./examples/krun_os_run.py IMAGE[@sha256:...]
  -> verified APFS cache entry containing libkrun-os-bundle/
  -> fresh APFS clone for this VM instance
  -> host-side libkrun/HVF process
  -> guest Linux OS PID 1 from the image, such as systemd
```

That is the contract implied by "Linux OS in a container from macOS." It is
not a promise that arbitrary Docker images are directly bootable. Images that
only contain an application filesystem must first pass through the rootfs
authoring path, which injects or validates OS init, console, networking, root
mount, readiness, kernel, and raw-disk metadata before publishing a prepared
bundle.

## Current macOS Container-to-VM Flow

The supported macOS path is now a concrete artifact pipeline rather than a
future concept. There are two related flows, and they must stay distinct:

- **Authoring flow:** use an ordinary distro or application OCI image as a
  filesystem source, adapt it into a bootable Linux OS root disk, and publish a
  prepared OS bundle.
- **Product launch flow:** use a prepared OCI image containing
  `/libkrun-os-bundle/` as the launch unit. The macOS host extracts and
  validates the bundle, creates a fresh APFS clone of `root.raw`, and starts
  the OS with a host-side libkrun/HVF process.

The product requirement "run a Linux OS in a container from a macOS host" maps
to the second flow. The container image is the delivery format for a complete
bootable OS bundle; the running Linux OS is not a Docker Desktop or Podman
container.

Authoring flow:

1. Use Docker or Podman on macOS to pull/export a `linux/arm64` OCI image.
2. Run `examples/os_mode_build_container_rootfs.py` to adapt that image into a
   bootable Linux root filesystem, inject or validate `/sbin/init`, add the
   selected serial/readiness plumbing, and pack the result into a raw ext4
   `root.raw`.
3. Require APFS output metadata for the macOS product path so the generated
   base image can be cloned cheaply on the host.
4. Validate the generated `manifest.json` before launch. The manifest records
   the source image identity, builder image identity, output checksums, APFS
   metadata, root/console invariants, clone command, production launch command,
   smoke replay command, and optional guarded perf replay command.
5. Create a fresh APFS clone, normally `vm-root.raw`, from the immutable
   `root.raw` base image.
6. Boot the APFS clone with `examples/os_mode` on the macOS host under HVF.
7. Treat the run as valid only when the guest emits `KRUN_OSMODE:*` markers
   proving PID 1 is the guest OS init, the root came from the expected
   virtio-blk disk or stable root identifier, the selected console is active,
   and readiness or clean shutdown completed.

Product launch flow:

1. Pull or load a digest-pinned `linux/arm64` OS-bundle image containing
   `/libkrun-os-bundle/manifest.json`, `root.raw`, `kernel`, and optional
   `initramfs`.
2. Run `examples/krun_os_run.py IMAGE@sha256:...` for the user path, or
   `examples/os_mode_release_gate.py` for release evidence.
3. Extract only `/libkrun-os-bundle/` into the macOS cache and validate all
   paths, digests, platform, root, console, PID 1, APFS, and strict image
   identity invariants before launch.
4. Create a fresh per-run APFS clone from the immutable extracted `root.raw`.
   Cached extracted bundles skip image extraction on repeat launches, but
   still create a new writable clone for each VM.
5. Launch `examples/os_mode` from the macOS host with HVF, not inside the
   container runtime VM.
6. Accept the run only after smoke/perf evidence proves the guest mounted the
   expected root, PID 1 is the guest OS init such as `systemd`, the selected
   console is active, readiness was observed, and clean poweroff succeeded when
   required.

This is the precise meaning of "run a Linux OS from a container on macOS" for
this design. The container gives us a reproducible Linux userspace source and a
Linux filesystem build environment for authoring, or a reproducible delivery
format for prepared bundles. libkrun still runs the resulting OS as a VM.
Docker Desktop or Podman VM behavior is therefore not accepted as runtime
proof.

For users, the prepared-bundle flow is primary. The rootfs-source flow is how
developers create or refresh those bundles from ordinary container images. Once
a bundle has been published, a macOS user should not rebuild `root.raw` during
normal startup. Startup should resolve or reuse the bundle image, validate the
cached artifacts, APFS-clone the immutable root disk, and immediately launch
libkrun/HVF.

There are two container roles in this design:

1. **Container rootfs source:** the image is a normal distro or application
   root filesystem. The macOS helper exports it, adapts it into a bootable OS
   root, packs it into `root.raw`, then libkrun/HVF boots that disk.
2. **Container-packaged OS bundle:** the image is the current distribution
   artifact for libkrun OS mode. It already contains the guest kernel, optional
   initramfs, raw root disk, and manifest. The macOS helper extracts those
   files, validates the manifest, APFS-clones the root disk, and starts a
   host-side libkrun/HVF VM.

The second form is the target product UX for "run a Linux OS in a container
from a macOS host." The container is the packaging and transport format; the
running OS is still a libkrun VM on the macOS host. This matters because
Docker Desktop and Podman on macOS run Linux containers inside their own helper
VMs and cannot exercise libkrun's HVF backend, macOS entitlements, APFS clone
behavior, or host networking path.

The intended pull-to-launch flow is:

```text
OCI image containing libkrun-os-bundle/
  -> Docker/Podman export or OCI artifact extraction on macOS
  -> manifest validation and source digest check
  -> APFS CoW per-VM clone of root.raw
  -> host-side libkrun OS-mode launch under HVF
  -> guest-owned /sbin/init or systemd as PID 1
```

The rootfs-source path remains useful for creating OS bundles locally from
ordinary images. The OS-bundle path is what users should consume once an image
has been prepared and published.

The minimum macOS user-facing command sequence for a prepared bundle image is:

```sh
export KRUN_OS_BUNDLE_CACHE="$HOME/Library/Caches/libkrun/os-bundles"
mkdir -p "$KRUN_OS_BUNDLE_CACHE"

./examples/os_mode_import_container_bundle.py \
  --image registry.example.com/libkrun-os/debian-systemd@sha256:... \
  --output-dir "$KRUN_OS_BUNDLE_CACHE/debian-systemd" \
  --pull \
  --strict-digest \
  --clone-dest vm-root.raw \
  --smoke-output smoke.json \
  --run
```

That command is considered successful only if it:

- obtains the image through Docker, Podman, or a later native OCI extractor;
- extracts `libkrun-os-bundle/` to the macOS host filesystem;
- verifies all manifest digests and the expected `linux/arm64`/`ttyAMA0`
  boot contract;
- creates an APFS clone of the immutable extracted `root.raw`;
- starts `examples/os_mode` or the production launcher as a macOS host
  process, not as a process inside Docker Desktop or Podman;
- observes `KRUN_OSMODE:*` markers proving the guest's own init is PID 1,
  the expected root is mounted, the expected console is active, readiness is
  reached, and clean shutdown works.

After the first extraction, repeated launches may use:

```sh
./examples/os_mode_import_container_bundle.py \
  --image registry.example.com/libkrun-os/debian-systemd@sha256:... \
  --output-dir "$KRUN_OS_BUNDLE_CACHE/debian-systemd" \
  --reuse-extracted-output-dir \
  --strict-digest \
  --clone-dest vm-root-2.raw \
  --smoke-output smoke-2.json \
  --run
```

The repeat-launch path must skip container extraction only when the cached
bundle metadata matches the requested image reference. It must still create a
new APFS clone before every VM launch.

## Required Product UX: macOS Container Image to Linux OS VM

The product requirement is that an Apple Silicon Mac can start from an OCI
image reference and run the Linux OS contained by that image through libkrun,
without requiring the user to provision a separate Linux machine. The image is
the distribution and cache unit; the runtime remains a macOS host-side
libkrun/HVF process.

This requirement has two supported forms:

1. **Prepared OS bundle image.** The container image contains
   `/libkrun-os-bundle/manifest.json`, `root.raw`, `kernel`, and optional
   `initramfs`. This is the primary consumption path and the one that should
   feel like "run this Linux OS container on my Mac."
2. **Rootfs source image.** The container image is a normal Linux root
   filesystem, such as Alpine or Debian. The macOS tooling uses Docker or
   Podman to export/adapt it, creates a bootable raw ext4 `root.raw`, then
   optionally publishes that result as a prepared OS bundle image.

### macOS OS-Container Contract

For this project, "run a Linux OS in a container from a macOS host" is a
container UX and artifact contract, not a request to run the VMM inside Docker
Desktop or Podman. The contract is:

- The user provides one container image reference, preferably digest-pinned.
- The default product path assumes that image is a prepared OS bundle. If the
  image is only a generic distro or application rootfs, the tooling must either
  run the explicit authoring path first or fail with a diagnostic that says the
  image is not a bootable libkrun OS bundle.
- If the image is a prepared OS bundle, it contains exactly the boot artifacts
  under `/libkrun-os-bundle/`: manifest, raw root disk, kernel, and optional
  initramfs.
- The macOS host resolves or pulls the image through Docker, Podman, or a later
  native OCI extractor.
- The bundle is extracted to an APFS-backed host cache and verified before any
  launch command is generated.
- A new writable APFS clone of the immutable `root.raw` is created for each VM
  start.
- The VMM process is started directly by the macOS host helper and uses HVF.
- Runtime evidence proves the guest booted the container-provided Linux OS,
  not `init.krun` and not Docker's own helper VM.
- The wrapper records enough evidence to answer "what OS did we run?" without
  relying on Docker state: image reference, digest, bundle manifest digest,
  root disk digest, expected and observed PID 1, expected and observed root,
  console, APFS clone path, launcher PID, child VMM PID, readiness markers, and
  clean-shutdown status.

The product-facing command is:

```sh
./examples/krun_os_run.py IMAGE[@sha256:...]
```

For a digest-pinned prepared bundle, that wrapper derives the cache directory,
enables strict digest checking, reuses an already validated extraction when it
matches the requested image, creates a unique APFS clone and smoke-evidence
path for the launch, and delegates to
`examples/os_mode_import_container_bundle.py --run`.

The lower-level importer remains the explicit form for debugging, release
gates, and custom output paths:

The prepared-bundle path should be reducible to one host command:

```sh
./examples/os_mode_import_container_bundle.py \
  --image IMAGE[@sha256:...] \
  --output-dir /path/on/apfs/libkrun-os/IMAGE \
  --pull \
  --strict-digest \
  --clone-dest vm-root.raw \
  --smoke-output smoke.json \
  --run
```

After the first extraction, repeat launch should be reducible to:

```sh
./examples/os_mode_import_container_bundle.py \
  --image IMAGE[@sha256:...] \
  --output-dir /path/on/apfs/libkrun-os/IMAGE \
  --reuse-extracted-output-dir \
  --strict-digest \
  --clone-dest vm-root-2.raw \
  --smoke-output smoke-2.json \
  --run
```

For productization, these example commands may be wrapped by a shorter command
such as `krun-os-run IMAGE`, but that wrapper must preserve the same semantics:

- resolve or pull the image on the macOS host;
- verify the requested image digest when strict mode is enabled;
- extract only the libkrun OS bundle files to a host APFS directory;
- validate manifest kind, platform, kernel format, root disk digest, kernel
  digest, optional initramfs digest, root device, filesystem type, console,
  expected PID 1, and expected readiness markers before launch;
- create a new writable APFS clone of immutable `root.raw` for every VM start;
- start libkrun/HVF as a macOS host process, not inside Docker Desktop or
  Podman;
- record structured smoke/perf evidence that proves the guest mounted the
  expected root, used the expected console, ran the expected guest PID 1, and
  reached readiness or clean shutdown.

A successful `docker run IMAGE` on macOS is not evidence for this requirement.
Docker Desktop and Podman on macOS run Linux containers in their own helper VM.
They are useful for pulling, exporting, building, and packaging Linux
filesystems, but they do not exercise libkrun's HVF backend, APFS clone path,
host-side process model, or macOS networking integration.

The product should therefore present the feature as "run a Linux OS packaged as
a container image" rather than "run Docker containers with libkrun." That
wording matters for support: users can bring OS bundles, and developers can
convert suitable distro images into OS bundles, but ordinary application
containers do not become full bootable guests just because they have a
filesystem.

### macOS Container UX Acceptance Tests

The container-on-macOS product path is complete only when these checks pass on
an Apple Silicon host:

- **Single-command prepared bundle:** given only a prepared OS bundle image
  reference and an APFS output directory, `--image ... --run` extracts,
  validates, APFS-clones, boots, writes smoke JSON, and powers off cleanly.
- **Product-wrapper proof:** given only `IMAGE[@sha256:...]`,
  `./examples/krun_os_run.py IMAGE[@sha256:...]` derives the cache location,
  enforces strict digest checking for digest-pinned inputs, reuses only matching
  extracted bundles, creates a fresh APFS clone, launches libkrun/HVF on the
  macOS host, and writes structured smoke evidence.
- **Generic-image rejection:** a container image that lacks
  `/libkrun-os-bundle/manifest.json` must not be treated as directly runnable
  by the prepared-bundle launcher. The user must be routed to the rootfs
  authoring path or shown an explicit "not a libkrun OS bundle" diagnostic.
- **Full OS proof:** smoke evidence includes `observed_pid1` equal to the
  manifest's expected guest init, such as `systemd` or `init`, and never
  `init.krun` or a Docker entrypoint.
- **Root proof:** smoke evidence includes `observed_root` matching the
  manifest's expected virtio-blk device or stable root token.
- **Console proof:** smoke evidence includes the macOS/aarch64 console,
  currently `ttyAMA0`, in `observed_consoles`.
- **Host-runtime proof:** smoke evidence records launcher/child process
  metadata showing the VMM was started by the macOS host helper.
- **APFS fast-start proof:** timing evidence separates bundle extraction,
  APFS clone creation, post-extraction runtime, and total importer time; repeat
  launch with `--reuse-extracted-output-dir` must skip extraction but still
  create a fresh APFS clone.
- **Base immutability proof:** the extracted immutable `root.raw` digest stays
  unchanged after guest writes to the APFS clone.
- **No separate Linux host:** the flow may require Docker Desktop or Podman on
  the Mac for image transport/build steps, but it must not require access to a
  separate Linux machine.
- **No startup rootfs rebuild:** the prepared-bundle launch path must not
  rebuild `root.raw` on each start. Rebuilds are allowed only in the explicit
  authoring/publishing path; normal startup must use cached extracted bundle
  artifacts plus a fresh APFS clone.
- **Networking proof when declared:** if the bundle manifest declares network
  support, the macOS gvproxy/vmnet-helper path must produce the expected
  network readiness marker.
- **Repeatability proof:** the same digest-pinned image can launch multiple
  times with distinct APFS clone destinations and distinct smoke evidence
  files.

Linux/KVM tests remain valuable portability gates, but they are not allowed to
substitute for these macOS/HVF acceptance tests.

## Goals

- Add an explicit OS boot mode that does not force `init=/init.krun`.
- Boot a prepared Linux root disk with a host-supplied kernel and optional initramfs.
- Build or import that prepared root disk from an OCI/container image on a
  macOS host.
- Support an OCI-packaged OS bundle that can be pulled on macOS, extracted to
  host files, APFS-cloned, and launched without rebuilding the root disk.
- Make the OCI-packaged OS bundle the primary "Linux OS in a container from a
  macOS host" path: the container image carries the complete bootable OS
  artifact, and libkrun/HVF runs that OS on the host.
- Support Linux/KVM and macOS/ARM64 HVF using the existing virtio-mmio device model.
- Use existing libkrun building blocks where possible: external kernel loading, virtio-blk, virtio-net, serial and virtio consoles.
- Keep the first implementation small enough to be practical inside libkrun.
- Preserve existing workload mode behavior and ABI compatibility.
- Make cold boot fast by constraining the guest image and kernel, not by adding firmware, PCI, or arbitrary hardware emulation.

## Non-Goals

- Booting arbitrary distro ISOs.
- Running GRUB, OVMF, SeaBIOS, or installer media.
- Adding PCI, virtio-pci, MCFG, MSI/MSI-X, or a full ACPI PCI routing surface.
- Supporting unmodified cloud images whose kernels require PCI or initramfs assumptions that conflict with virtio-mmio.
- Treating Docker or Podman on macOS as the final runtime. Containers are a
  rootfs source and Linux build environment; the OS runs under libkrun/HVF.
- Treating a successful `docker run` or `podman run` on macOS as evidence that
  libkrun can run the OS. Runtime evidence must come from a host-side
  libkrun/HVF boot from the extracted and APFS-cloned bundle.
- Running libkrun/HVF inside a macOS Docker Desktop or Podman container. The
  VMM process must run on the macOS host so it can use HVF, signing
  entitlements, APFS clone paths, and host-side networking helpers directly.
- Replacing Cloud Hypervisor, QEMU, or Virtualization.framework for generic VM use.
- Snapshot/restore in the initial milestone. It is important for later cold-start wins, but it should follow a working OS-mode boot path.

## Existing Building Blocks

The current tree already contains most of the low-level pieces needed for a constrained OS mode:

- `include/libkrun.h` exposes `krun_set_kernel()` for direct kernel boot with optional initramfs and command line. Internally this populates `ExternalKernel`.
- `include/libkrun.h` exposes `krun_add_disk*()` and `krun_set_root_disk_remount()` for virtio-blk backed filesystems.
- `src/devices/src/virtio/block` implements virtio-blk.
- `src/devices/src/virtio/mmio.rs` and the KVM/HVF device managers attach devices through virtio-mmio.
- `include/libkrun.h` exposes serial and virtio-console APIs.
- `include/libkrun.h` exposes virtio-net APIs for passt, gvproxy, unixgram, unixstream, and tap backends.
- `src/libkrun/src/lib.rs` already stores per-context external kernel, block, network, console, and cmdline state.
- On aarch64, the legacy serial device is a PL011 UART. The KVM and HVF MMIO device managers register it as an MMIO serial device and add an `earlycon=pl011,mmio32,...` command-line entry.

The main blocker is not missing device code. The main blocker is that `krun_start_enter()` always converts the context into workload mode by appending `init=/init.krun` and `KRUN_*` handoff data.

## Proposed API

Add an explicit mode switch:

```c
int32_t krun_set_os_mode(uint32_t ctx_id);
```

In OS mode:

- `krun_start_enter()` does not inject `init=/init.krun`.
- `krun_start_enter()` does not append `KRUN_INIT`, `KRUN_WORKDIR`, `KRUN_RLIMITS`, workload environment variables, or `-- <args>`.
- `krun_set_exec()`, `krun_set_workdir()`, `krun_set_env()`, `krun_set_rlimits()`, and related workload APIs either return `-EINVAL` after OS mode is selected or are ignored with a documented precedence rule.
- The guest kernel command line comes from a new OS-mode command line builder.

Add an OS root helper:

```c
int32_t krun_set_os_root(
    uint32_t ctx_id,
    const char *device,
    const char *fstype,
    const char *options
);
```

This is intentionally similar to `krun_set_root_disk_remount()`, but it configures the real kernel root directly instead of creating a temporary virtiofs root for `init.krun`.

Because `krun_set_os_init()` and `krun_set_os_root()` append values directly to
the guest kernel command line, all non-NULL root/init values must be non-empty
single tokens with no whitespace. This intentionally permits common Linux root
forms such as `/dev/vda`, `/dev/vda1`, `PARTUUID=...`, `UUID=...`, `ext4`, and
comma-separated `rootflags=...`, while rejecting accidental or malicious
argument injection such as `"/dev/vda1 quiet"` or `"/sbin/init panic=1"`.

Example use:

```c
krun_set_os_mode(ctx);
krun_set_kernel(ctx, "/path/to/bzImage", KRUN_KERNEL_FORMAT_PE_GZ, "/path/to/initramfs", "quiet");
krun_add_disk3(ctx, "root", "/path/to/root.raw", KRUN_DISK_FORMAT_RAW, false, false, KRUN_SYNC_RELAXED);
krun_set_os_root(ctx, "/dev/vda1", "ext4", NULL);
krun_add_serial_console_default(ctx, STDIN_FILENO, STDOUT_FILENO);
krun_set_kernel_console(ctx, "ttyS0");
krun_start_enter(ctx);
```

This example uses an x86_64-style serial console name. The macOS/ARM64 example must use an aarch64 kernel and the validated PL011 console name.

## Kernel Command Line

Introduce a separate default command line for OS mode:

```text
reboot=k panic=-1 panic_print=0 rw quiet no-kvmapf
```

Then append:

```text
root=<device> rootfstype=<fstype> rootflags=<options> init=/sbin/init console=<console>
```

Rules:

- Do not include `nomodule` by default.
- Do not include `rootfstype=virtiofs` by default.
- Prefer a serial console when one is configured, but choose the console name per architecture. `ttyS0` is the expected x86_64 serial console name; aarch64 PL011 guests usually use a PL011-specific tty such as `ttyAMA0`, and this must be validated on the target kernel.
- Allow callers to override or extend the command line through `krun_set_kernel()`.
- Deduplicate or define precedence for repeated keys such as `root=`, `console=`, and `init=`.

The first implementation can use a simple precedence rule: OS-mode generated parameters are appended after the caller-provided external-kernel command line, so generated `root=` and `console=` win.

## Guest Image Contract

The first supported guest image is a prepared disk image, not an arbitrary cloud image.

Required guest properties:

- Kernel supports virtio-mmio transport.
- Kernel has virtio-blk, virtio-net, virtio-console, and serial support built in or available in an initramfs.
- Root filesystem is present at the device passed to `krun_set_os_root()`, for example `/dev/vda1`.
- `/sbin/init` exists, or the user provides an alternate `init=` parameter.
- Getty is configured for the selected console. Use `ttyS0` for x86_64 serial guests and validate the PL011 console name, usually `ttyAMA0`, for aarch64 guests.
- Networking is managed by the guest through a normal virtio-net interface when `krun_add_net_*()` is used.

OCI/container rootfs images are valid sources for this prepared disk, but they
must be adapted before boot:

- Export the image filesystem with Docker or Podman.
- Add or verify a real guest PID 1 at `/sbin/init`, or configure
  `krun_set_os_init()`.
- Add mount setup for `/dev`, `/proc`, `/sys`, and `/run` unless the chosen init
  handles it.
- Add serial console/getty or readiness-marker output to the selected console.
- Add DHCP/static network setup if virtio-net validation is required.
- Pack the adapted rootfs into a raw ext4 disk image and record its checksum.

Recommended guest properties for fast boot:

- Custom kernel with only required drivers.
- No initramfs if all root-device drivers are built in.
- systemd units masked to a minimal target, or a smaller init system for specialized images.
- Predictable device naming disabled or configured so the primary virtio-net device is easy to bring up.

## Device Model

Initial OS mode should continue using virtio-mmio. This keeps the implementation portable across KVM and macOS/ARM64 HVF and avoids introducing PCI complexity.

Minimum devices:

- virtio-blk for the root disk.
- serial console or virtio-console for boot logs and login. On macOS/ARM64, the serial path is aarch64 PL011 and the console name must be validated with the chosen guest kernel.
- virtio-net with passt/gvproxy/tap when networking is requested.
- virtio-rng if already available in the default device set.

Deferred devices:

- virtio-pci.
- NVMe, AHCI, IDE, USB, VGA, or primary graphics.
- CPU, memory, and device hotplug.

## Implementation Plan

### Milestone 1: Boot Contract Split

Add an enum to `ContextConfig`:

```rust
enum BootMode {
    Workload,
    Os,
}
```

Default to `Workload`. Add `krun_set_os_mode()` to set `BootMode::Os`.

Refactor the command-line construction in `krun_start_enter()` into two functions:

- `build_workload_kernel_cmdline(&ContextConfig) -> KernelCmdlineConfig`
- `build_os_kernel_cmdline(&ContextConfig) -> KernelCmdlineConfig`

Workload mode must preserve the current behavior exactly.

### Milestone 2: OS Root Configuration

Add an OS root field to `ContextConfig`, likely reusing `BlockRootConfig`:

```rust
os_root: Option<BlockRootConfig>
```

Add `krun_set_os_root()` in `src/libkrun/src/lib.rs` and `include/libkrun.h`.

Validation:

- OS mode must be enabled.
- At least one block device must be configured.
- `device` must be non-empty.
- `fstype` may be `NULL` or `"auto"`.
- `options` may be `NULL`.

Unlike `krun_set_root_disk_remount()`, this must not create a temporary virtiofs root. The kernel must mount the real root itself.

### Milestone 3: Console Defaults

Make OS mode console behavior explicit:

- If the user called `krun_set_kernel_console()`, honor it.
- Else if a serial console was added, choose an architecture-specific serial console such as `ttyS0` on x86_64 or the validated PL011 console on aarch64.
- Else preserve the existing implicit virtio-console behavior and use `console=hvc0`.

This likely needs a small amount of context tracking so the command-line builder knows whether serial was configured.

### Milestone 4: Example and Smoke Test

Add an example that:

- Creates a context.
- Sets OS mode.
- Sets a host-supplied kernel.
- Adds a root disk.
- Sets OS root to `/dev/vda1`.
- Adds serial console.
- Optionally adds passt or gvproxy networking.
- Starts the VM.

Add a smoke test script or documented manual test using a tiny ext4 image with `/sbin/init` as a shell script or busybox init. The first automated test can validate command-line construction without booting a VM.

### Milestone 5: Guest Image Tooling

Add documentation or helper tooling to build a compatible guest image:

- Linux kernel config fragment for virtio-mmio, virtio-blk, virtio-net, serial, and ext4.
- Minimal rootfs recipe.
- OCI/container image export and adaptation recipe for macOS hosts.
- systemd or busybox init profile.
- macOS-specific notes for gvproxy networking.

The macOS container workflow is a required product path:

1. Pull or build an OCI image for the guest architecture, initially aarch64 for
   macOS/ARM64 HVF.
2. Export the image filesystem from Docker or Podman on macOS.
3. Mutate the exported rootfs into a bootable guest OS rootfs by adding init,
   mount setup, console setup, readiness markers, and optional DHCP tooling.
4. Pack the rootfs into a raw ext4 disk in a Linux build container, because
   macOS does not provide native ext4 authoring tools with Linux ownership,
   device node, xattr, and symlink semantics.
5. Copy the raw disk to the macOS APFS host volume as an immutable base image.
6. APFS-clone that base image for each VM launch.
7. Boot the clone with `examples/os_mode` on macOS/HVF.

Docker or Podman on macOS is acceptable for steps 1-4 because those steps are
image construction, not KVM/HVF runtime validation. The final runtime smoke
test must be libkrun/HVF on the macOS host.

Completion criteria for this product path:

- A fresh macOS host with Docker Desktop or Podman, Xcode command-line tools,
  and the libkrun build dependencies can build a raw ext4 Linux root disk from
  a supported `linux/arm64` OCI image without a separate Linux machine.
- The generated `manifest.json` records the source image digest, builder,
  manifest schema version, UTC creation timestamp, builder script digest,
  builder image digest, runtime version, kernel format, platform, console, root
  disk checksum, requested size, and apparent size, rootfs tar checksum and
  size, build-host metadata, APFS output metadata, expected root-source marker,
  recommended smoke timeout, expected smoke markers, smoke poweroff policy,
  post-readiness exit wait, and exact
  clone/launch/smoke commands. The manifest checker can print a smoke command
  with a caller-selected JSON evidence output path and write a replay script
  that runs clone creation followed by smoke validation.
- The generated launch command attaches the APFS clone destination, not the
  immutable base `root.raw`; the base image appears only as the clone source.
- Manifest validation fails before launch when the image platform, console,
  kernel format, APFS requirement, or source identity is inconsistent.
- A per-VM APFS clone of the base root disk is created before every launch, and
  the immutable base image remains unchanged after guest writes.
- The APFS clone boots under libkrun/HVF on macOS/ARM64 and emits readiness
  markers proving the guest's own init path is running, root is mounted from
  virtio-blk, serial console works, and clean shutdown works.
- Networking validation uses a macOS-compatible gvproxy or vmnet-helper path
  and records guest DHCP/outbound markers when network support is requested.

### Milestone 6: macOS APFS CoW Root Disk Clones

After basic OS-mode boot works on macOS/ARM64 HVF, add a macOS-specific fast disk provisioning path:

- Treat the root disk image used by OS mode as an immutable base image.
- Create a per-VM writable APFS clone of that base image using macOS file cloning, for example `clonefile(2)`, `fclonefileat(2)`, or an equivalent `copyfile(3)` clone operation.
- Attach the per-VM clone as the virtio-blk root disk.
- Keep the base image read-only from libkrun's perspective to avoid corrupting every future clone.
- Delete or recycle per-VM clones after the VM exits, depending on whether the caller wants ephemeral or persistent state.

This is not snapshot/restore and it does not avoid guest kernel or userspace boot. It removes the host-side cost of copying a large root disk before launch and makes "new VM from template" close to metadata-only on APFS. It should be measured separately from guest boot time.

The Linux equivalent can use reflinks where available, such as `FICLONE` on filesystems that support it, but the first-class requirement for this milestone is APFS on macOS.

### Milestone 7: Container-Sourced OS Images on macOS

Add a repeatable path for "run this Linux OS from a container image on macOS":

- Input: OCI image reference or local container image name, for example
  `alpine:3.23`, `debian:stable-slim`, or a user-built image.
- Output: a manifest directory containing a raw ext4 base image, kernel path,
  optional initramfs path, root device, root filesystem type, guest architecture,
  source image digest, root disk checksum, and boot command.
- Build backend: Docker or Podman on macOS for Linux filesystem manipulation.
- Runtime backend: libkrun OS mode on macOS/ARM64 HVF.
- Disk provisioning: APFS clone of the generated base image for each launch.
- Supported builder platforms for this implementation: `linux/arm64` with
  `ttyAMA0`, and `linux/amd64` with `ttyS0`. The macOS/HVF product path is
  `linux/arm64`; `linux/amd64` exists for Linux/KVM artifacts and
  host-independent manifest validation until a Linux host is available.

The builder must make clear whether it produced:

- a minimal smoke OS, where PID 1 is a BusyBox or shell init injected by the
  builder;
- a distro init OS, where the image already contains a suitable `/sbin/init`;
- a systemd OS, where systemd is installed, serial getty/readiness units are
  configured, and services incompatible with the libkrun device model are
  masked.

Validation for this milestone requires booting at least one container-derived
aarch64 root disk on macOS/HVF and observing normal `KRUN_OSMODE:*` markers from
the guest.

The end-to-end macOS flow must be runnable without a Linux host:

1. Build or pull an OCI image for `linux/arm64`.
2. Run `examples/os_mode_build_container_rootfs.py` on macOS with Docker or
   Podman to export the image, adapt it into a bootable OS rootfs, and pack it
   into a raw ext4 base image.
3. Require and record APFS output-directory metadata in `manifest.json`.
4. Validate the manifest before launch, including rootfs/root-disk checksums,
   source image digest, kernel/initramfs fields, platform-specific console,
   expected root-source marker, generated launch command, generated APFS clone
   command, and generated smoke wrapper. The generated launch command must use
   the APFS clone destination as `--root-disk`.
5. Create a fresh APFS clone of the raw base image for the VM instance.
6. Boot the clone with libkrun/HVF on the macOS host.
7. Prove the guest is a real OS instance by checking `KRUN_OSMODE: pid1=...`,
   `KRUN_OSMODE: root=...`, console, readiness, clean shutdown, and when
   requested, DHCP/network markers.

Linux-only KVM checks may run later in Docker on a Linux host with `/dev/kvm`,
but they are not a substitute for this macOS/HVF container-derived OS flow.

### Milestone 8: Pull-to-Launch OCI OS Bundles on macOS

Add a second container path where the OCI image is already a libkrun OS-mode
bundle rather than an arbitrary rootfs source. This is the desired consumption
model for users who say "run this Linux OS from a container on my Mac."

Required image layout after export:

```text
/libkrun-os-bundle/manifest.json
/libkrun-os-bundle/root.raw
/libkrun-os-bundle/kernel
/libkrun-os-bundle/initramfs        # optional
/libkrun-os-bundle/overlay.tar      # optional provenance artifact
```

Required manifest fields:

- schema version and bundle kind, for example
  `"kind": "libkrun.os-bundle.v1"`;
- source image reference and immutable image digest used for the pull;
- guest platform, currently `linux/arm64` for the macOS/HVF product path;
- kernel path, kernel SHA-256, kernel format, and optional initramfs path and
  SHA-256;
- root disk path, SHA-256, apparent size, filesystem type, root device or
  stable root token, and optional root mount options;
- default console, expected PID 1 marker, expected root marker, expected
  console marker, optional network marker, and recommended smoke timeout;
- APFS clone policy, including whether clone-backed launch is required and
  whether full-copy fallback is allowed;
- generated host launch command and smoke replay command, both using the APFS
  clone path rather than the immutable bundle `root.raw`.

The macOS importer should:

1. Pull or locate the image by digest when possible.
2. Export only the bundle directory to a host artifact directory.
3. Reject path traversal, absolute paths in the bundle manifest, symlinks that
   escape the artifact directory, missing files, digest mismatches, unsupported
   platform values, and unsupported kernel formats.
4. Require an APFS artifact directory for the default product path.
5. Create a fresh APFS clone of `root.raw` for each VM instance.
6. Launch `examples/os_mode` or the production launcher on the macOS host, not
   inside Docker or Podman.
7. Validate `KRUN_OSMODE:*` markers and write smoke JSON evidence next to the
   extracted bundle.

The initial importer can use Docker or Podman export because those tools are
already expected on macOS for rootfs-source builds. A later implementation may
use `skopeo`, `oras`, or an OCI layout reader to avoid starting a Docker
Desktop or Podman machine for pure artifact extraction. That later extractor
must preserve the same manifest and digest validation semantics.

Completion criteria:

- A prepared OCI image containing `libkrun-os-bundle/` can be pulled on an
  Apple Silicon Mac and booted through libkrun/HVF without rebuilding
  `root.raw`.
- The VMM process runs on the macOS host and not inside the container runtime.
- The first launch creates an APFS clone and attaches the clone as the writable
  root disk.
- The immutable `root.raw` extracted from the image remains unchanged after
  guest writes.
- Smoke evidence proves PID 1 is the guest OS init, the root is the expected
  virtio-blk disk or stable root token, the console is the expected macOS
  `ttyAMA0` path, and clean shutdown works.
- Re-running the same image with a new clone destination starts a second VM
  from the same immutable extracted base image without re-exporting or
  rebuilding the root disk.
- A user-facing command can start from only an image reference and a host output
  directory and can perform extraction, validation, APFS clone creation, host
  launch, and smoke evidence recording in one `--run` invocation.
- The smoke evidence records enough process metadata to prove that the VMM was
  launched by the macOS host-side helper rather than by the container runtime's
  Linux VM.

## APFS CoW Disk Provisioning Design

APFS CoW support should be treated as host disk provisioning for OS mode. It should not change the guest device model: the guest still sees an ordinary virtio-blk disk backed by a raw disk image file.

Recommended flow:

1. Build or import a raw base root disk image.
2. Mark the base image immutable at the product layer: do not attach it read-write to guests.
3. On VM creation, create a per-VM APFS clone of the base image in the same APFS volume.
4. Attach the clone path through `krun_add_disk3()` as the writable root disk.
5. Boot OS mode using `krun_set_os_root()`.
6. On VM exit, either delete the clone for ephemeral VMs or retain it as the persistent VM disk.

Implementation choices:

- The safest first step is a helper in examples or higher-level tooling, because libkrun already accepts any disk path and does not need to know whether the file is an APFS clone.
- If clone creation becomes a libkrun API, it should be a separate API from OS mode. OS mode should boot from disk paths; disk provisioning should create disk paths.
- Clone creation should fail clearly when source and destination are not on the same APFS volume or when cloning is unsupported.
- A fallback to full copy is acceptable only if it is explicit in logs and measurements.
- Clone destination creation should be atomic enough to avoid racing two VMs onto the same writable disk path.
- The base image should be opened read-only for verification or never opened by the VM at all when using clones.
- Per-VM clone names should include the VM identity and enough randomness to avoid collisions.
- The cleanup path must distinguish ephemeral clones from persistent VM disks.

Validation for APFS clones:

- Measure base image full-copy time as a baseline.
- Measure APFS clone creation time.
- Record apparent file size and allocated size when available.
- Boot from the clone and emit the normal `KRUN_OSMODE:*` readiness markers.
- Write a marker file from inside the guest.
- Verify the marker exists only in the clone when mounted or inspected later.
- Verify the base image checksum or known read-only marker is unchanged.
- Delete an ephemeral clone and verify the lifecycle is clean.

## Validation Strategy

Validation must run continuously while the feature is built. The implementation is not considered healthy just because Linux/KVM boots once; every milestone needs a macOS/ARM64 HVF check or an explicit note that the milestone is host-independent.

### Progress Gates

1. **No-behavior-change gate:** after the command-line builder refactor, workload mode produces the same command-line components as before, existing unit tests pass, and no public API has changed.
2. **API compile gate:** after adding `krun_set_os_mode()` and `krun_set_os_root()`, the C header, Rust implementation, and any generated bindings compile on Linux and macOS/ARM64.
3. **Command-line gate:** OS mode can build a kernel command line that includes `root=...`, the selected console, and no `init=/init.krun` or `KRUN_*` workload handoff.
4. **Device-attachment gate:** OS mode still attaches virtio-blk, console, and optional virtio-net devices through the existing KVM and HVF MMIO paths.
5. **Deferred Linux boot gate:** a minimal prepared root disk boots on Linux/KVM, PID 1 is the guest init, and the root filesystem is virtio-blk. This gate requires a real Linux host or Linux CI runner with `/dev/kvm`; it is deferred for the local macOS implementation path.
6. **macOS boot gate:** the same guest userspace boots on macOS/ARM64 HVF with an aarch64 kernel, PID 1 is the guest init, and the console works from boot logs through an interactive shell or readiness marker.
7. **Network gate:** macOS passes outbound networking through gvproxy, vmnet-helper, or the chosen unixgram backend. The Linux passt or tap side of this gate requires a Linux host and is deferred.
8. **Regression gate:** existing workload-mode examples and tests continue to pass with default features and with `BLK=1`.
9. **APFS clone gate:** macOS can create a writable per-VM APFS clone from an immutable base root image, attach it as virtio-blk, boot from it, and prove the base image remains unchanged.
10. **Container-to-OS macOS gate:** macOS can pull/export an OCI image with
    Docker or Podman, turn it into a bootable OS-mode raw ext4 base image
    without a separate Linux host, require APFS output metadata in the manifest,
    APFS-clone that base image, and boot the clone under libkrun/HVF with the
    readiness markers. Passing this gate requires proving PID 1 is the
    container-derived guest init, not `init.krun` or a Docker entrypoint.
11. **Container-packaged OS bundle macOS gate:** macOS can pull or load an OCI
    image that already contains a `libkrun-os-bundle/` directory, extract the
    bundle to host files, validate all manifest digests and launch invariants,
    APFS-clone the included `root.raw`, and boot the clone under libkrun/HVF.
    Passing this gate requires proving the VMM process ran on the macOS host,
    that no root-disk rebuild was required after image pull or archive load,
    and that load/pull/export, extraction, clone, and runtime timings are
    recorded separately.
12. **Performance gate:** boot timing and disk-provisioning timing are measured separately so optimization work targets guest kernel, init, block I/O, APFS clone setup, or VMM setup based on evidence.

### Required Test Artifacts

- A tiny root image that exits or prints a readiness marker without requiring login.
- A tiny root image that provides an interactive shell or getty on the selected console.
- Deferred until Linux host: a documented x86_64 Linux/KVM kernel config.
- A documented aarch64 macOS/ARM64 HVF kernel config.
- A host-side smoke-test runner that records stdout/stderr, elapsed time, exit status, and the detected readiness marker.
- A manually runnable macOS smoke test that uses only dependencies documented in the repo.
- A macOS APFS clone smoke test that records base image path, clone image path, clone creation time, apparent size, allocated size when available, and whether the clone booted.
- A macOS container-rootfs builder smoke test that records the source OCI image
  reference and digest, builder image reference and digest, container runtime
  version, build-host metadata, generated root disk checksum and size, root
  disk manifest, APFS clone path, and libkrun/HVF boot markers.
- A macOS pull-to-launch OS bundle smoke test that records the OCI image
  reference and digest, extracted bundle path, manifest digests, APFS clone
  path, host-side launch command, smoke JSON evidence path, and libkrun/HVF
  boot markers without rebuilding the root disk.
- A table of last-known-good host and guest versions.

### Linux Docker Validation

A traditional Docker container can validate Linux compile and unit-test gates.
It can validate Linux/KVM runtime behavior only when the Linux host passes KVM
through to the container, for example with `--device /dev/kvm` and any extra
permissions required by that host's container runtime. Docker on macOS cannot
validate Linux/KVM for this project because it runs inside a Linux VM and does
not exercise the same host KVM path; it also cannot validate macOS/HVF.

Host-independent helper checks are grouped in `ci/os_mode_host_checks.sh`.
That script runs Python helper syntax checks, shell helper syntax checks, C API
syntax for `examples/os_mode.c`, a host-runnable `examples/os_mode.c` parser
self-test that does not link or boot libkrun, Linux validation entrypoint
argument guards for KVM smoke environment values, `os_mode_smoke.py` self-tests
including argument guards, JSON evidence output with merged stdout/stderr
capture, exact root-source checks, console-token checks, and PID 1 regression
guards, `os_mode_perf.py` argument guards, timing and control-path self-tests,
partial-line marker handling, explicit timeout failure reasons, exit-wait and
nonzero-exit enforcement checks, and manifest checker positive/negative
self-tests, generated-command consistency checks, duplicate launcher-option
rejection, malformed launcher-option value rejection, unexpected
launcher-argument rejection, command-array string-only checks, required
builder/runtime/source-identity checks, kernel/initramfs/init-mode manifest
field checks, manifest schema-version checks, builder-script digest checks,
builder-image identity checks, container-runtime version checks, UTC creation
timestamp checks, artifact checksum and size checks, build-host metadata
checks, timing evidence consistency checks, kernel-format consistency checks,
platform allow-list checks, APFS output metadata shape checks, arm64 and amd64
console consistency checks, systemd command-line consistency checks, APFS
clone-command shape checks, optional overlay artifact consistency checks, and
`.dockerignore` context-guard checks.
Performance helper checks also verify that timing runs can enforce the same
OS-mode invariants as smoke runs: expected root source, expected active
console, and PID 1 not being `init.krun`.
The Linux Docker validation script runs this helper before Rust unit tests and
build checks. Locally, the same helper is available through
`make os-mode-checks`. GitHub Actions runs the same target from the Linux
x86_64, Linux aarch64, and macOS code-quality jobs.

The host-independent helper checks also cover builder path normalization:
relative container-rootfs `--output-dir`, `--kernel`, `--initramfs`, and
`--overlay-tar` inputs must be converted to absolute paths before artifact
paths and generated commands are written to the manifest.

The repo includes `.dockerignore` entries for local Cargo outputs, sysroots,
example binaries, and generated root-disk images so the Docker compile gate
does not send multi-gigabyte local artifacts as build context.

The repeatable container entrypoint is:

```sh
docker build -f ci/os_mode_linux.Dockerfile -t libkrun-os-mode-linux .
docker run --rm -v "$PWD:/workspace/libkrun" libkrun-os-mode-linux
```

Optional KVM smoke testing on a Linux host with `/dev/kvm`:
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

The Linux validation entrypoint preflights the kernel, root disk, and optional
initramfs paths before boot. It also validates the root device, root filesystem,
optional root options, launch console, expected smoke console, timeout, and
kernel-format environment values before constructing the KVM smoke command.
`KRUN_OSMODE_EXPECT_CONSOLE` defaults to `KRUN_OSMODE_CONSOLE` and is passed to
`os_mode_smoke.py --expect-console` so Linux smoke runs fail when the guest
reports the wrong active console. `KRUN_OSMODE_EXPECT_ROOT` can
override the root marker assertion when the guest is booted with a stable token
such as `PARTUUID=...` but `/proc/mounts` reports the resolved device.
`KRUN_OSMODE_PASST_SOCKET` attaches the optional Linux passt unixstream network
backend for the KVM smoke entrypoint; container-derived readiness scripts need
`KRUN_OSMODE_NET=1` in the kernel command line to run DHCP. `KRUN_OSMODE_EXPECT_MARKER`
can require an additional guest marker, such as `KRUN_OSMODE: network=up`, once
the relevant scenario is expected to pass. `KRUN_OSMODE_SMOKE_JSON` writes the
smoke helper result into a mounted artifact directory for the validation log.

### Readiness Markers

The minimal guest should emit deterministic markers so tests can distinguish "kernel booted" from "OS mode works":

```text
KRUN_OSMODE: init-started
KRUN_OSMODE: root=<source from /proc/mounts>
KRUN_OSMODE: pid1=<comm from /proc/1/comm>
KRUN_OSMODE: console=<active console>
KRUN_OSMODE: network=<up|down|skipped>
KRUN_OSMODE: ready
```

The Linux and macOS smoke tests should fail if `pid1` is `init.krun`, if the root source is not the configured virtio-blk device or stable root identifier, or if `ready` is not observed before the timeout.

### macOS/ARM64 HVF Validation

macOS validation is first-class for this feature. The first implementation should assume macOS means Apple Silicon / aarch64 HVF unless the project later documents another supported host architecture.

- Use an aarch64 guest kernel for macOS/ARM64 HVF.
- Validate the aarch64 PL011 serial path and document the correct guest console name.
- Validate virtio-blk MMIO root disk attachment on HVF.
- Keep the rootfs content portable across Linux/aarch64 KVM and macOS/ARM64 HVF, even if the kernel image differs. The Linux/aarch64 proof requires a Linux/aarch64 host and is deferred.
- Validate networking with the macOS-supported backend, likely gvproxy or vmnet-helper through `krun_add_net_unixgram()`.
- Validate APFS clone-backed root disks after normal raw root disks work.
- Validate that APFS clone creation does not require copying the full base image.
- Validate that writes inside the guest affect only the per-VM clone and not the base image.
- Record any macOS-only default differences in the example and user guide.
- Do not mark a milestone complete if it compiles on macOS but cannot boot or cannot be manually smoke-tested when the milestone claims runtime behavior.

### Progress Tracking

For each patch or milestone, record:

- The exact host OS and architecture tested.
- The libkrun build flags used.
- The guest kernel version and config fragment.
- The rootfs image recipe or image checksum.
- The command used to run the smoke test.
- The observed readiness markers.
- The elapsed time to first kernel log, init start, and ready.
- The elapsed time to prepare the root disk, separated from guest boot time.
- Whether the root disk was a base image, APFS clone, Linux reflink, or full copy.
- Whether the same patch was tested on macOS/ARM64 HVF.

## Runtime Gates

Runtime TODO items below this point must not be marked complete from compile
checks or documentation alone. They require real guest artifacts and
host/backend execution evidence, or an explicit deferred status for host
requirements that cannot be exercised locally.

Required artifacts before the runtime TODOs can be completed:

- Deferred until available: a Linux/x86_64 host with KVM and libkrun build
  dependencies.
- A macOS/ARM64 host with HVF, which this workspace has, plus a compatible
  aarch64 guest kernel and root image.
- A prepared BusyBox ext4 root image with `KRUN_OSMODE:*` readiness markers.
- A systemd root image with the same readiness markers; Debian `bookworm`
  systemd is validated for the macOS/HVF no-network gate.
- Deferred until Linux host: a Linux passt setup for virtio-net unixstream
  validation.
- A macOS gvproxy or vmnet-helper setup for virtio-net unixgram/vfkit
  validation.
- An APFS base root image that can boot normally before clone-backed boot is
  claimed.
- A container-derived aarch64 root disk built on macOS through Docker or Podman,
  then booted directly on the macOS host with libkrun/HVF.

Current deferred gates:

- Linux/KVM runtime gates are deferred until a real Linux host or Linux CI
  runner with `/dev/kvm` is available. A Docker validation path exists for
  compile gates and optional KVM smoke tests when `/dev/kvm` is passed through
  on a Linux host.
- Workload-mode runtime regression validation is deferred until
  `libkrunfw.5.dylib` is available locally.

Current local validated gates:

- macOS/HVF boots the Alpine aarch64 smoke image from an APFS clone and reaches
  readiness markers.
- macOS/HVF APFS clone guest-write isolation is validated.
- macOS/HVF gvproxy v0.8.8 unixgram networking is validated without the legacy
  `VFKT` datagram.
- macOS/HVF boots a container-derived Alpine aarch64 root disk from an APFS
  clone and reaches readiness markers.
- macOS/HVF gvproxy networking is validated from a container-derived Alpine
  root disk when the matching guest kernel network modules are overlaid into
  the rootfs.
- macOS/HVF boots a container-derived Debian systemd root disk from an APFS
  clone, reaches readiness markers with PID 1 as systemd, remounts root
  read-write, and exits through systemd poweroff.
- macOS/HVF gvproxy networking is validated from a container-derived Debian
  systemd root disk when `udhcpc` is present and matching `af_packet` /
  `virtio_net` modules are available to the guest.
- macOS/HVF consumes a local OCI OS bundle image, extracts the complete
  `libkrun.os-bundle.v1` payload, APFS-clones the immutable `root.raw`, boots
  Debian systemd from the clone, and records structured observed root, PID 1,
  console, network, process, and timing evidence.
- macOS/HVF reuses an already extracted bundle directory only when import
  metadata matches the requested image reference, while still creating a fresh
  APFS clone for each VM launch.

Runtime TODOs must be backed by entries in
`design_docs/os_mode_validation_log.md` before being checked off.

## Detailed TODO

This checklist is intentionally more concrete than the milestone list above. It should be updated as implementation reveals incorrect assumptions.

### Phase 0: Pre-Implementation Audit

- [x] Confirm the exact public C API naming in `include/libkrun.h` and keep the design aligned with exported symbols.
- [x] Confirm whether `krun_set_kernel()` is available under all feature combinations needed for OS mode.
- [x] Confirm whether `krun_set_root_disk_remount()` is compiled only with `blk` and without `tee`, and decide whether OS mode should use the same feature gates.
- [x] Confirm whether OS mode should be unavailable in `tee`, `aws-nitro`, SEV, and TDX builds for the first implementation.
- [x] Confirm the exact macOS support target. Based on the current README, treat it as macOS/ARM64 HVF until the project documents otherwise.
- [x] Confirm whether x86_64 macOS is unsupported, untested, or out of scope for OS mode.
- [x] Audit `ContextConfig` in `src/libkrun/src/lib.rs` for every field that is workload-specific.
- [x] Audit `VmResources` in `src/vmm/src/resources.rs` for fields that should be set differently in OS mode.
- [x] Audit `build_microvm_for_boot()` and related builder code in `src/vmm/src/builder.rs` to identify command-line modifications that happen after `VmResources.kernel_cmdline` is set.
- [x] Confirm where implicit vsock, TSI, and DHCP command-line fragments are appended in `src/vmm/src/builder.rs`.
- [x] Confirm whether any current tests assert the exact kernel command line.
- [x] Confirm expected behavior when both `krun_set_kernel()` and libkrunfw payload loading are used.
- [x] Confirm expected behavior when firmware is configured through `krun_set_firmware()`.
- [x] Confirm the aarch64 direct-kernel boot path used by macOS/ARM64 HVF.
- [x] Confirm the aarch64 MMIO serial registration path and resulting Linux console device name.
- [x] Confirm the HVF MMIO block path is identical enough to KVM for virtio-blk root boot.
- [x] Confirm the macOS-supported virtio-net backend to use for the first smoke test.
- [x] Confirm which macOS APIs are acceptable for APFS cloning: `clonefile(2)`, `fclonefileat(2)`, `copyfile(3)`, or a small helper.
- [x] Confirm how to detect APFS clone support and how to fall back when the target directory is not on APFS.
- [x] Decide whether the first patch should include only internal command-line refactoring before adding public API.

### Phase 1: API and ABI Surface

- [x] Add `int32_t krun_set_os_mode(uint32_t ctx_id);` to `include/libkrun.h`.
- [x] Add `int32_t krun_set_os_root(uint32_t ctx_id, const char *device, const char *fstype, const char *options);` to `include/libkrun.h`.
- [x] Document in `include/libkrun.h` that OS mode is for prepared direct-kernel guests, not arbitrary VM media.
- [x] Document in `include/libkrun.h` that OS mode bypasses `init.krun` and workload handoff variables.
- [x] Document that `krun_set_os_root()` expects a root device visible to the guest kernel, such as `/dev/vda1`.
- [x] Document that `krun_set_os_root()` does not create the temporary virtiofs root used by `krun_set_root_disk_remount()`.
- [x] Document the interaction between OS mode and `krun_set_exec()`.
- [x] Document the interaction between OS mode and `krun_set_workdir()`.
- [x] Document the interaction between OS mode and `krun_set_env()`.
- [x] Document the interaction between OS mode and `krun_set_rlimits()`.
- [x] Document the interaction between OS mode and `krun_set_root()`.
- [x] Document the interaction between OS mode and `krun_set_root_disk()`.
- [x] Document the interaction between OS mode and `krun_set_root_disk_remount()`.
- [x] Document that the first supported macOS host target is macOS/ARM64 HVF.
- [x] Document that guest kernels and console names are architecture-specific.
- [x] Decide whether APFS clone support belongs in libkrun's public API or in a helper/tooling layer above libkrun.
- [x] Since APFS clone support is staying in helper/tooling for now, defer a libkrun API such as `krun_create_cow_disk()`.
- [x] Decide whether `krun_set_os_mode()` is irreversible for a context.
- [x] Decide whether `krun_set_os_root()` should imply `krun_set_os_mode()` or require it explicitly.
- [x] Decide whether OS mode should expose a single convenience API later, for example `krun_configure_os_boot()`.
- [x] Update any generated bindings, if this repository has generated C/Rust binding outputs for `include/libkrun.h`.
- [x] Update versioning or symbol export files if the project maintains them outside the header.

### Phase 2: Context State

- [x] Add a `BootMode` enum in `src/libkrun/src/lib.rs`.
- [x] Set `BootMode::Workload` as the default for `ContextConfig`.
- [x] Add `boot_mode: BootMode` to `ContextConfig`.
- [x] Add `os_root: Option<BlockRootConfig>` to `ContextConfig` under the same feature gates as block root support.
- [x] Add helper methods for setting and reading OS root state.
- [x] Add helper methods for checking whether OS mode is enabled.
- [x] Add helper methods for validating workload-only settings.
- [x] Add helper methods for validating OS-only settings.
- [x] Track whether a serial console was explicitly added, or rely on `ctx_cfg.vmr.serial_consoles.is_empty()`.
- [x] Track whether a virtio-console was explicitly added, or rely on `ctx_cfg.vmr.virtio_consoles.is_empty()`.
- [x] Confirm whether implicit console state is visible early enough to choose OS-mode defaults.
- [x] Confirm whether `kernel_console` in `VmResources` should remain the only console override mechanism.
- [x] Keep all new fields out of unrelated serialized structures unless required.

### Phase 3: Public API Implementation

- [x] Implement `krun_set_os_mode()` in `src/libkrun/src/lib.rs`.
- [x] Return `-ENOENT` when `krun_set_os_mode()` receives an unknown context ID.
- [x] Return success if `krun_set_os_mode()` is called repeatedly on the same context, unless a stricter rule is chosen.
- [x] Validate existing context state when switching to OS mode.
- [x] Reject switching to OS mode if workload-only fields have already been set, or define a documented precedence rule.
- [x] Implement `krun_set_os_root()` in `src/libkrun/src/lib.rs`.
- [x] Return `-ENOENT` when `krun_set_os_root()` receives an unknown context ID.
- [x] Return `-EINVAL` when `device` is `NULL`.
- [x] Return `-EINVAL` when `device` is an empty string.
- [x] Return `-EINVAL` when `device` contains whitespace that would split the
  generated `root=` kernel command-line argument.
- [x] Return `-EINVAL` when `device` is invalid UTF-8.
- [x] Treat `fstype == NULL` as automatic filesystem detection.
- [x] Treat `fstype == "auto"` as automatic filesystem detection.
- [x] Return `-EINVAL` when `fstype` is an empty string or contains whitespace.
- [x] Return `-EINVAL` when `fstype` is invalid UTF-8.
- [x] Treat `options == NULL` as no root mount options.
- [x] Return `-EINVAL` when `options` is an empty string or contains whitespace.
- [x] Return `-EINVAL` when `options` is invalid UTF-8.
- [x] Return `-EINVAL` when `krun_set_os_init()` receives an empty path or a
  path containing whitespace that would split the generated `init=` argument.
- [x] Make the container-rootfs builder reject root device, root filesystem, and
  root mount option values that would split into extra kernel command-line
  tokens.
- [x] Make the container-rootfs builder reject empty source image,
  builder-image, output-directory, kernel, initramfs, and overlay-tar
  arguments before they can normalize into misleading host paths.
- [x] Make the container-rootfs builder accept `/dev/...`, `PARTUUID=...`, and
  `UUID=...` root identifiers so robust images do not have to depend on
  virtio-blk enumeration names.
- [x] Make the manifest checker reject root device, root filesystem, and root
  mount option values that would be rejected by the OS-mode C API.
- [x] Make the manifest checker accept and validate `/dev/...`, `PARTUUID=...`,
  and `UUID=...` root identifiers consistently with the builder.
- [x] Return `-EINVAL` if no block device has been configured when strict early validation is chosen.
- [x] Do not create an empty temporary virtiofs root in `krun_set_os_root()`.
- [x] Avoid changing the behavior of `krun_set_root_disk_remount()`.
- [x] Add log messages for invalid OS-mode combinations that match existing libkrun logging style.
- [x] Add compile checks for the new APIs on Linux.
- [x] Add compile checks for the new APIs on macOS/ARM64.

### Phase 4: Workload API Compatibility

- [x] Decide whether workload-only APIs should fail immediately after OS mode is enabled.
- [x] If immediate failure is chosen, update `krun_set_exec()` to return `-EINVAL` in OS mode.
- [x] If immediate failure is chosen, update `krun_set_workdir()` to return `-EINVAL` in OS mode.
- [x] If immediate failure is chosen, update `krun_set_env()` to return `-EINVAL` in OS mode.
- [x] If immediate failure is chosen, update `krun_set_rlimits()` to return `-EINVAL` in OS mode.
- [x] If immediate failure is chosen, update `krun_set_root()` to return `-EINVAL` in OS mode.
- [x] If immediate failure is chosen, update `krun_add_virtiofs*()` to reject
  `KRUN_FS_ROOT_TAG` (`/dev/root`) in OS mode while still allowing non-root
  shared filesystem tags.
- [x] If immediate failure is chosen, update `krun_set_root_disk_remount()` to return `-EINVAL` in OS mode.
- [x] If delayed validation is chosen, make `krun_start_enter()` reject incompatible mixed configuration.
- [x] Preserve existing workload mode behavior byte-for-byte where practical.
- [x] Preserve backwards compatibility for contexts that never call `krun_set_os_mode()`.

### Phase 5: Command-Line Builder Refactor

- [x] Extract the existing command-line construction in `krun_start_enter()` into `build_workload_kernel_cmdline()`.
- [x] Add unit tests proving `build_workload_kernel_cmdline()` preserves the current default prolog.
- [x] Add unit tests proving `build_workload_kernel_cmdline()` still includes `init=/init.krun`.
- [x] Add unit tests proving `build_workload_kernel_cmdline()` still includes `KRUN_INIT` when `krun_set_exec()` is used.
- [x] Add unit tests proving `build_workload_kernel_cmdline()` still includes `KRUN_WORKDIR` when workdir is set.
- [x] Add unit tests proving `build_workload_kernel_cmdline()` still includes `KRUN_RLIMITS` when rlimits are set.
- [x] Add unit tests proving workload arguments still appear after `--`.
- [x] Add `OS_KERNEL_CMDLINE` or equivalent in `src/vmm/src/vmm_config/kernel_cmdline.rs`.
- [x] Keep `DEFAULT_KERNEL_CMDLINE` unchanged for workload mode.
- [x] Implement `build_os_kernel_cmdline()`.
- [x] Ensure `build_os_kernel_cmdline()` does not include `init=/init.krun`.
- [x] Ensure `build_os_kernel_cmdline()` does not include `KRUN_INIT`.
- [x] Ensure `build_os_kernel_cmdline()` does not include `KRUN_WORKDIR`.
- [x] Ensure `build_os_kernel_cmdline()` does not include `KRUN_RLIMITS`.
- [x] Ensure `build_os_kernel_cmdline()` does not include workload environment variables.
- [x] Ensure `build_os_kernel_cmdline()` does not include `-- <workload args>`.
- [x] Ensure `build_os_kernel_cmdline()` does not include `nomodule` by default.
- [x] Ensure `build_os_kernel_cmdline()` does not include `rootfstype=virtiofs` by default.
- [x] Ensure `build_os_kernel_cmdline()` includes `root=<device>` when OS root is configured.
- [x] Ensure `build_os_kernel_cmdline()` includes `rootfstype=<fstype>` when fstype is configured.
- [x] Ensure `build_os_kernel_cmdline()` omits `rootfstype=` when fstype is automatic.
- [x] Ensure `build_os_kernel_cmdline()` includes `rootflags=<options>` when options are configured.
- [x] Ensure `build_os_kernel_cmdline()` can choose `console=ttyS0` for x86_64 serial.
- [x] Ensure `build_os_kernel_cmdline()` can choose the validated PL011 console name for aarch64 serial.
- [x] Decide whether OS mode should force `rw` or let the caller choose `ro`/`rw`.
- [x] Decide whether OS mode should append `init=/sbin/init` by default.
- [x] Add an API or documented command-line override for alternate init paths.
- [x] Decide whether OS mode should include `panic=-1` and `reboot=k` by default.
- [x] Decide whether OS mode should include `quiet` by default, or prefer verbose early boot during development.
- [x] Decide whether `no-kvmapf` is still appropriate for OS mode.
- [x] Define precedence when the caller-provided `krun_set_kernel()` command line includes `root=`.
- [x] Define precedence when the caller-provided `krun_set_kernel()` command line includes `rootfstype=`.
- [x] Define precedence when the caller-provided `krun_set_kernel()` command line includes `rootflags=`.
- [x] Define precedence when the caller-provided `krun_set_kernel()` command line includes `console=`.
- [x] Define precedence when the caller-provided `krun_set_kernel()` command line includes `init=`.
- [x] Keep the first implementation simple by appending generated OS parameters after caller-provided parameters if that rule is accepted.
- [x] Add tests for duplicate-key precedence once the rule is chosen.
- [x] Add tests for x86_64 console selection.
- [x] Add tests for aarch64 console selection.

### Phase 6: Start Path Validation

- [x] Update `krun_start_enter()` to branch on `BootMode`.
- [x] In workload mode, call only the workload command-line builder.
- [x] In OS mode, call only the OS command-line builder.
- [x] In OS mode, require at least one boot payload: external kernel, firmware, kernel bundle, or compatible libkrunfw path.
- [x] In OS mode, likely require `krun_set_kernel()` for the first milestone.
- [x] In OS mode, require a configured OS root unless firmware boot is explicitly supported later.
- [x] In OS mode, require at least one block device unless root is supplied entirely by initramfs and explicitly allowed.
- [x] In OS mode, reject `krun_set_root()` virtiofs root as the primary root for the first milestone.
- [x] In OS mode, decide whether additional `krun_add_virtiofs*()` mounts are allowed as non-root shared filesystems.
- [x] In OS mode, decide whether implicit vsock should remain enabled.
- [x] In OS mode, decide whether TSI command-line injection should be disabled by default.
- [x] In OS mode, keep `KRUN_DHCP=1` injection only if `init.krun` or guest tooling consumes it; otherwise remove it from OS mode.
- [x] Ensure OS mode still attaches block devices before the VM starts.
- [x] Ensure OS mode still attaches network devices before the VM starts.
- [x] Ensure OS mode still attaches console devices before the VM starts.
- [x] Ensure OS mode handles failure paths with existing negative errno style.
- [x] Add an internal assertion or debug log showing which boot mode was selected.
- [x] Add a debug log of the final OS-mode command line with the same sensitivity assumptions as existing command-line logging.

### Phase 7: Console Behavior

- [x] Verify `krun_set_kernel_console()` currently stores the desired console in `VmResources.kernel_console`.
- [x] Verify `src/vmm/src/builder.rs` strips an existing `console=` and inserts the configured console.
- [x] Decide whether OS-mode console selection belongs in `src/libkrun/src/lib.rs` or lower in `src/vmm/src/builder.rs`.
- [x] If `krun_set_kernel_console()` was called, honor it in OS mode.
- [x] If a serial console was added on x86_64 and no console override exists, set `console=ttyS0`.
- [x] If a serial console was added on aarch64 and no console override exists, set the validated PL011 console name, expected to be `ttyAMA0` for common Linux configs.
- [x] If no serial console was added and virtio-console is available, set `console=hvc0`.
- [x] Decide whether OS mode should automatically add `earlycon` for development builds.
- [x] Decide whether x86_64 should prefer legacy I/O serial or MMIO serial in OS mode.
- [x] Confirm the aarch64 platform-specific console name for the selected guest kernel.
- [x] Confirm macOS/ARM64 HVF serial behavior matches Linux/KVM enough for one documented default.
- [x] Confirm the automatically added `earlycon=pl011,mmio32,...` entry on aarch64 does not conflict with the selected `console=`.
- [x] Add unit tests for console default selection.
- [x] Add manual test steps for interactive login over serial.
- [x] Add manual test steps for boot log capture when stdout is redirected.
- [x] Add macOS manual test steps proving interactive serial input works under HVF.

### Phase 8: Block Device and Root Filesystem

- [x] Confirm virtio-blk device ordering maps the first disk to `/dev/vda` in the target guest kernels.
- [x] Confirm partition naming convention for the first disk, such as `/dev/vda1`; macOS smoke used whole-disk `/dev/vda`, and docs recommend `PARTUUID=` for stable partitioned roots.
- [x] Confirm the same virtio-blk root image convention works on macOS/ARM64 HVF.
- [x] Confirm whether block IDs are exposed to the guest in a useful stable path.
- [x] Decide whether documentation should recommend `root=PARTUUID=...` instead of `/dev/vda1`.
- [x] Add examples for `/dev/vda1`.
- [x] Add examples for `PARTUUID=...` if supported by the guest image recipe.
- [x] Confirm raw image support on both Linux and macOS.
- [x] Confirm qcow2 support if the relevant optional feature is enabled.
- [x] Decide whether direct I/O should be discouraged on macOS in first examples.
- [x] Decide whether `KRUN_SYNC_RELAXED` is acceptable for example OS root disks.
- [x] Document data safety tradeoffs for sync modes.
- [x] Add validation or documentation for read-only root disks.
- [x] Add validation or documentation for separate writable data disks.
- [x] Add a rootfs readiness marker that prints the root mount source from `/proc/mounts`.
- [x] Fail smoke tests if the root source is not the configured virtio-blk root or stable root identifier.
- [x] Design the macOS APFS base-image layout, including where immutable base images and per-VM clones live.
- [x] Validate that per-VM APFS clones can be used as raw virtio-blk root disks.
- [x] Validate that writes in a clone do not mutate the immutable base image.
- [x] Validate cleanup of ephemeral APFS clones after VM exit.
- [x] Make the APFS clone helper refuse to overwrite an existing destination and publish clones through a temporary file so two launches do not intentionally share the same writable root path.
- [x] Make the APFS clone helper reject empty source and destination path
  arguments before APFS/full-copy preflight.
- [x] Decide how persistent APFS clones are named, retained, and garbage-collected.

### Phase 9: Networking

- [x] Deferred until Linux host: confirm `krun_add_net_unixstream()` works with passt for OS-mode guests.
- [x] Confirm `krun_add_net_unixgram()` works with gvproxy or vmnet-helper on macOS.
- [x] Confirm `krun_add_net_tap()` remains Linux-only where applicable.
- [x] Decide whether OS mode should disable TSI by default.
- [x] Decide whether OS mode should require explicit virtio-net setup for network access.
- [x] Document that stock guest networking should use DHCP or static config inside the guest.
- [x] Reject `NET_FLAG_DHCP_CLIENT` in OS mode even when it was configured
  before `krun_set_os_mode()`, because it depends on libkrun's workload init
  rather than the guest OS init.
- [x] Reject TSI port maps and TSI hijacking in OS mode, including state set
  before `krun_set_os_mode()`, while still allowing explicit vsock devices
  with no TSI hijacking.
- [x] Require `krun_add_vsock_port*()` in OS mode to use an explicit
  non-TSI vsock device, including state set before `krun_set_os_mode()`, so
  implicit-vsock IPC maps cannot be silently dropped when OS mode disables
  implicit vsock at start.
- [x] Add a passt example for Linux hosts.
- [x] Add a gvproxy or vmnet-helper example for macOS hosts.
- [x] Add a note that `KRUN_DHCP=1` is not a substitute for a guest DHCP client unless guest tooling handles it.
- [x] Add manual smoke tests for outbound network connectivity.
- [x] Add manual smoke tests for host-to-guest port forwarding through the selected network backend.
- [x] Add a macOS-specific networking smoke test using the chosen gvproxy or vmnet-helper setup.
- [x] Decide whether network validation is required for the first boot milestone or can be a separate gate.

### Phase 10: Guest Kernel Contract

- [x] Create a documented kernel config fragment for x86_64.
- [x] Create a documented kernel config fragment for aarch64 because macOS/ARM64 HVF support is first-class.
- [x] Include `CONFIG_VIRTIO`.
- [x] Include `CONFIG_VIRTIO_MMIO`.
- [x] Include `CONFIG_VIRTIO_BLK`.
- [x] Include `CONFIG_VIRTIO_NET`.
- [x] Include `CONFIG_VIRTIO_CONSOLE`.
- [x] Include 8250/serial support appropriate to x86_64 if x86_64 serial is tested.
- [x] Include PL011 serial support appropriate to aarch64.
- [x] Include root filesystem support, initially ext4.
- [x] Include devtmpfs support.
- [x] Include initramfs support if the recipe uses one.
- [x] Include DHCP userspace requirements in the rootfs recipe rather than the kernel config.
- [x] Decide whether module loading should be supported or avoided in first images.
- [x] Document that `nomodule` is intentionally not used in OS mode.
- [x] Document the expected kernel image formats for `KRUN_KERNEL_FORMAT_*`.
- [x] Document known-good kernel versions once tested.
- [x] Deferred until Linux host: record one known-good Linux/KVM x86_64 kernel config.
- [x] Record one known-good macOS/ARM64 HVF aarch64 kernel config.

### Phase 11: Guest Rootfs Contract

- [x] Create a minimal busybox rootfs recipe.
- [x] Create a minimal systemd rootfs recipe if systemd is required for the target use case.
- [x] Decide whether the first cross-host rootfs is architecture-specific or built separately for x86_64 and aarch64.
- [x] Ensure `/sbin/init` exists.
- [x] Ensure `/dev`, `/proc`, `/sys`, and `/run` are mounted by init or early boot scripts.
- [x] Ensure a getty or shell is available on the selected console.
- [x] Ensure the rootfs includes a DHCP client if networking is expected.
- [x] Ensure rootfs shutdown and reboot paths work with libkrun's current reboot behavior.
- [x] Decide whether cloud-init is in scope for first guest images.
- [x] Since cloud-init is out of scope for first images, defer metadata-source design.
- [x] Document how to build an ext4 raw disk image.
- [x] Document how to partition the disk image.
- [x] Document how to set a stable filesystem UUID or PARTUUID.
- [x] Document how to mount and modify the disk image on Linux.
- [x] Document macOS-specific limitations for creating and modifying Linux filesystems.
- [x] Add the `KRUN_OSMODE:*` readiness markers to the minimal init path.
- [x] Ensure the readiness-marker image can run without networking.
- [x] Ensure the readiness-marker image can optionally test networking when a virtio-net device is present.
- [x] Ensure the rootfs can tolerate APFS clone-backed disks whose host file starts as a cloned base image.

### Phase 12: Examples

- [x] Add a minimal C example under `examples/` for OS mode on Linux/KVM.
- [x] Add a minimal C example or documented invocation for OS mode on macOS/ARM64 HVF.
- [x] Keep the example focused on direct kernel, raw root disk, and serial console.
- [x] Add optional network setup to the example behind clearly separated code.
- [x] Include comments explaining host-side paths and expected guest device names.
- [x] Avoid requiring root privileges for the basic example when possible.
- [x] Add a README for the example.
- [x] Add sample command lines for Linux/KVM.
- [x] Add sample command lines for macOS/ARM64 HVF.
- [x] Add sample command lines for creating an APFS clone-backed root disk on macOS.
- [x] Add expected boot log snippets.
- [x] Add troubleshooting notes for "cannot mount root fs".
- [x] Add troubleshooting notes for "no console output".
- [x] Add troubleshooting notes for "network interface appears but no DHCP lease".

### Phase 13: Unit Tests

- [x] Add unit tests for `BootMode` defaulting to workload mode.
- [x] Add unit tests for `krun_set_os_mode()` context lookup behavior where feasible.
- [x] Add unit tests for OS root parsing helpers.
- [x] Add unit tests for `fstype == NULL`.
- [x] Add unit tests for `fstype == "auto"`.
- [x] Add unit tests for `options == NULL`.
- [x] Add unit tests for empty OS root device rejection.
- [x] Add unit tests for OS root device, filesystem type, and root options
  values that would split into extra kernel command-line tokens.
- [x] Add unit tests for OS init paths that would split into extra kernel
  command-line tokens.
- [x] Add host-independent helper checks for container-rootfs builder and
  manifest-checker rejection of invalid root command-line tokens.
- [x] Add host-independent helper checks for container-rootfs builder rejection
  of empty image and host-path arguments.
- [x] Add host-independent manifest checks for optional root mount options and
  generated `--root-options` command consistency.
- [x] Add host-independent manifest checks for stable `PARTUUID=...` root
  identifiers and unsupported root-token rejection.
- [x] Add unit tests for workload command-line preservation.
- [x] Add unit tests for OS command-line omission of `init=/init.krun`.
- [x] Add unit tests for OS command-line omission of `KRUN_*` handoff variables.
- [x] Add unit tests for OS command-line root generation.
- [x] Add unit tests for OS command-line console generation.
- [x] Add unit tests for OS mode with caller-provided kernel cmdline.
- [x] Add unit tests for duplicate command-line key precedence.
- [x] Add unit tests for incompatible API combinations.
- [x] Add unit tests under existing `#[cfg(feature = "blk")]` and `#[cfg(not(feature = "tee"))]` gates.
- [x] Add host-independent tests for command-line generation so they can run in CI without KVM or HVF.
- [x] Add architecture-specific command-line tests behind `#[cfg(target_arch = "...")]`.
- [x] Add syntax validation for the APFS clone helper and defer Rust unit tests while clone support remains outside libkrun.
- [x] Add host-independent argument guard checks for the APFS clone and APFS
  validation helpers so malformed paths and sizes fail before touching disk.
- [x] Add host-independent argument guard checks for
  `ci/os_mode_linux_validate.sh` so invalid KVM smoke environment values fail
  before attempting a boot, including kernel-format range validation, artifact
  file checks, and optional root mount options.
- [x] Add `KRUN_OSMODE_EXPECT_ROOT` to the Linux KVM smoke path so stable
  `PARTUUID=`/`UUID=` boot tokens can be validated against the root source
  actually reported by the guest.
- [x] Add `KRUN_OSMODE_EXPECT_CONSOLE` to the Linux KVM smoke path and pass it
  to `os_mode_smoke.py --expect-console` so Linux runtime validation checks
  the guest-reported active console as well as the launch console argument.
- [x] Add optional `KRUN_OSMODE_PASST_SOCKET` passt wiring to the Linux KVM
  smoke entrypoint, with host-independent socket-path guard coverage.
- [x] Add optional expected-marker support to `os_mode_smoke.py` and the Linux
  KVM smoke entrypoint so optional scenario checks such as networking can fail
  explicitly when the base boot markers are present but the scenario marker is
  missing.
- [x] Add optional `KRUN_OSMODE_SMOKE_JSON` output support to the Linux KVM
  smoke entrypoint so Linux runtime evidence can be saved directly into mounted
  validation artifacts.
- [x] Add host-independent argument guard checks for `os_mode_smoke.py` and
  `os_mode_perf.py` so missing commands and invalid timing values fail before
  launching a process.
- [x] Make `os_mode_perf.py` process a final marker line without a trailing
  newline and record explicit failure reasons for missing ready/control markers.
- [x] Make `os_mode_perf.py` support `--expect-root` and `--expect-console`,
  and reject PID 1 markers that identify `init.krun`, so boot timing evidence
  cannot be collected from an invalid workload-mode or wrong-console guest.
- [x] Make `os_mode_perf.py --expect-root` and `--expect-console` require the
  corresponding root and console markers to appear, so a guest that only emits
  `KRUN_OSMODE: ready` cannot satisfy guarded timing replay.
- [x] Add `os_mode_perf.py --require-pid1-marker` and include it in
  manifest-generated perf replay commands so timing evidence must prove the
  guest emitted a PID 1 marker, not merely avoid an `init.krun` marker.
- [x] Add a host-runnable parser self-test for `examples/os_mode.c` so
  launcher root, init, console, disk-sync, network, and kernel-format argument
  validation is checked without linking or booting libkrun.
- [x] Make the `examples/os_mode` launcher reject unexpected positional
  arguments so mistyped disk or kernel paths are not silently ignored.
- [x] Make the `examples/os_mode` launcher reject empty host path and socket
  arguments for kernel, root disk, initramfs, passt, and gvproxy inputs.
- [x] Add a host-independent OS-mode helper check script and run it from the Linux Docker validation entrypoint.
- [x] Run the host-independent OS-mode helper checks from GitHub Actions code-quality jobs on Linux x86_64, Linux aarch64, and macOS.
- [x] Add host-independent checks that protect the Docker build context from
  accidentally including local Cargo outputs, example binaries, dSYMs, dylibs,
  and generated root-disk images.

### Phase 14: Integration and Manual Tests

- [x] Build libkrun with `BLK=1` on Linux.
- [x] Build libkrun with networking features on Linux.
- [x] Build libkrun with `BLK=1` on macOS/ARM64.
- [x] Build libkrun with networking features on macOS/ARM64.
- [x] Deferred until Linux host: boot a busybox ext4 image on Linux/KVM.
- [x] Boot an equivalent busybox ext4 image on macOS/ARM64 HVF with an aarch64 kernel.
- [x] Deferred until Linux/aarch64 host: if possible, boot the same aarch64 rootfs image on Linux/aarch64 KVM and macOS/ARM64 HVF.
- [x] Verify PID 1 is not `init.krun`.
- [x] Verify PID 1 is `/sbin/init`, systemd, or the configured alternate init.
- [x] Verify root filesystem is mounted from virtio-blk.
- [x] Verify no temporary virtiofs root is required.
- [x] Verify console output appears from early boot through init.
- [x] Verify interactive input works on serial.
- [x] Verify the `KRUN_OSMODE: init-started` marker appears.
- [x] Verify the `KRUN_OSMODE: root=...` marker matches the configured root.
- [x] Verify the `KRUN_OSMODE: pid1=...` marker is not `init.krun`.
- [x] Verify the `KRUN_OSMODE: console=...` marker matches the selected console.
- [x] Verify the `KRUN_OSMODE: ready` marker appears before timeout.
- [x] Verify clean shutdown exits the VMM as expected.
- [x] Verify guest reboot behavior is documented, even if not fully supported.
- [x] Deferred until Linux host: verify outbound networking with passt on Linux.
- [x] Verify outbound networking with gvproxy or vmnet-helper on macOS.
- [x] Deferred until `libkrunfw.5.dylib` is available: verify workload mode still boots existing examples. Local `chroot_vm` builds but cannot start because `libkrunfw.5.dylib` is missing, and Homebrew has no `libkrunfw` formula.
- [x] Verify existing tests pass with default feature flags.
- [x] Verify existing tests pass with `blk` enabled.
- [x] Create an APFS clone of the macOS base root disk and boot from that clone.
- [x] Measure APFS clone creation latency separately from VM boot latency. The APFS clone helpers now use monotonic millisecond timing when `python3` is available, avoiding the earlier one-second timestamp floor for metadata-cheap clones.
- [x] Verify the APFS base image checksum or read-only marker is unchanged after guest writes to the clone.
- [x] Verify deleting an ephemeral APFS clone cleans up the clone after guest writes; APFS per-file unique-block release is not directly observable with `du`, so the validation log records path deletion, base checksum stability, and clone checksum divergence.
- [x] Deferred until Linux host: store representative Linux/KVM smoke-test output in the docs or test fixtures.
- [x] Store representative macOS/ARM64 HVF smoke-test output in the docs or test fixtures.
- [x] Keep a manual validation log for macOS until CI can run HVF tests.

### Phase 15: Documentation

- [x] Update the main `README.md` with a short description of OS mode once implemented.
- [x] Add a dedicated user guide for building or obtaining a compatible guest image.
- [x] Add API documentation for `krun_set_os_mode()`.
- [x] Add API documentation for `krun_set_os_root()`.
- [x] Add a compatibility matrix for host OS, architecture, block, console, and network support.
- [x] Include macOS/ARM64 HVF as a required row in the compatibility matrix.
- [x] Add a troubleshooting section for kernel config problems.
- [x] Add a troubleshooting section for root device naming problems.
- [x] Add a troubleshooting section for console mismatch problems.
- [x] Add a troubleshooting section for macOS networking problems.
- [x] Document non-goals prominently so users do not expect ISO or arbitrary cloud image boot.
- [x] Document the security model difference between virtiofs workload mode and block-root OS mode.
- [x] Document performance expectations and where boot time is likely spent.
- [x] Document how to run the smoke tests and interpret readiness markers.
- [x] Document what counts as "milestone complete" for Linux and macOS.
- [x] Document APFS clone-backed root disks, including base image immutability and clone cleanup.
- [x] Document fallback behavior when APFS cloning is unavailable.

### Phase 16: Performance Baseline

- [x] Deferred until `libkrunfw.5.dylib` is available: measure workload mode boot time before OS-mode changes.
- [x] Measure OS-mode boot time with a minimal busybox image.
- [x] Deferred until a systemd guest image is added: measure OS-mode boot time with a minimal systemd image.
- [x] Measure time to first kernel log line.
- [x] Measure time to root filesystem mount.
- [x] Measure time to init start.
- [x] Measure time to login prompt or readiness marker.
- [x] Deferred until Linux host: measure on Linux/KVM.
- [x] Measure on macOS/ARM64 HVF.
- [x] Record host CPU, kernel, macOS version, and guest kernel config.
- [x] Compare direct kernel boot with and without initramfs.
- [x] Not relevant for the initial macOS/HVF OS-mode milestone: compare serial console versus virtio-console. The validated path uses PL011 serial for early boot and interactive control.
- [x] Expose raw root disk sync mode as an example runtime option so APFS/raw-disk validation can select `KRUN_SYNC_RELAXED`, `KRUN_SYNC_FULL`, or `KRUN_SYNC_NONE` without recompiling. Comparative benchmarking remains scenario-specific and should be recorded only when the run is actually measured.
- [x] Measure full-copy root disk provisioning time on macOS as a baseline.
- [x] Measure APFS clone root disk provisioning time on macOS.
- [x] Measure first boot from an APFS clone.
- [x] Measure repeated boot from newly created APFS clones.
- [x] Track disk allocated-size growth after representative guest writes to an APFS clone.
- [x] Use measurements to decide whether optimization should target guest kernel, rootfs init, block I/O, APFS clone setup, or VMM setup.
- [x] Deferred Linux-host portion: do not treat snapshot/restore as production-ready until baseline Linux boot numbers are recorded; macOS/HVF and APFS clone baselines remain active local work.

### Phase 17: Follow-Up Snapshot/Restore Design

- [x] Write a separate design doc for snapshot/restore only after OS mode boots.
- [x] Audit existing VM state structures for serializable device state.
- [x] Audit KVM backend support needed for pause, snapshot, and restore.
- [x] Audit HVF backend support needed for pause, snapshot, and restore.
- [x] Decide whether snapshot support must be cross-host-backend from day one.
- [x] Define guest quiescence requirements before snapshot.
- [x] Define entropy reseeding requirements after restore.
- [x] Define MAC address and network identity refresh requirements after restore.
- [x] Define timekeeping and clock catch-up behavior after restore.
- [x] Define disk snapshot or copy-on-write requirements.
- [x] Treat APFS root disk clones as disk provisioning, not memory snapshot/restore.
- [x] Decide whether snapshot/restore should create new APFS disk clones before restoring memory on macOS.
- [x] Define memory deduplication strategy for many restored guests.
- [x] Keep snapshot work out of the initial OS-mode patch series.

### Phase 18: Patch Series Shape

- [x] Patch 1: add internal boot mode enum and command-line builder refactor with no behavior change.
- [x] Patch 2: add unit tests for existing workload command-line behavior and run them on Linux and macOS/ARM64.
- [x] Patch 3: add `krun_set_os_mode()` API and context state.
- [x] Patch 4: add `krun_set_os_root()` API and validation.
- [x] Patch 5: add OS-mode command-line builder with architecture-aware console defaults.
- [x] Patch 6: wire OS mode into `krun_start_enter()`.
- [x] Patch 7: add console default handling for OS mode.
- [x] Patch 8: add unit tests for OS mode.
- [x] Patch 9: add Linux/KVM minimal OS-mode example.
- [x] Patch 10: add macOS/ARM64 HVF minimal OS-mode example or documented invocation.
- [x] Patch 11: add guest image documentation.
- [x] Patch 12: add integration smoke test tooling if practical.
- [x] Deferred Linux-host portion: add validation logs or fixtures for Linux smoke tests; macOS smoke-test logs are tracked locally.
- [x] Patch 14: add macOS APFS clone provisioning helper or documented helper workflow.
- [x] Patch 15: add APFS clone validation and performance measurements.
- [x] Keep each patch reviewable and avoid mixing behavior changes with formatting.
- [x] Do not refactor PCI, ACPI, firmware, or unrelated device code in this series.
- [x] Do not change existing workload-mode defaults in this series.

### Phase 19: Container-Sourced OS Images on macOS

- [x] Define the exact supported input image contract for OCI/container images:
  a Linux root filesystem for the guest architecture that can be adapted into a
  direct-kernel, virtio-mmio, raw ext4 OS-mode root disk.
- [x] Decide and validate the first required image target: `alpine:3.23`
  `linux/arm64` with injected BusyBox smoke init on macOS/ARM64 HVF.
- [x] Add a second required image target with a distro init or systemd, likely
  Debian or another systemd-capable distro, for full-distro validation.
- [x] Add a builder that runs from macOS and uses Docker or Podman for Linux
  filesystem operations.
- [x] Make the builder export an OCI image rootfs with preserved ownership,
  symlinks, device nodes where possible, and executable permissions.
- [x] Make the builder inject or validate `/sbin/init`.
- [x] Make the builder create `/dev`, `/proc`, `/sys`, and `/run` mount points.
- [x] Make the builder install serial-console readiness output for the selected
  platform console, including `ttyAMA0` on macOS/aarch64 through `/dev/console`.
- [x] Add an explicit builder option that fails early when DHCP tooling is
  required but missing. Alpine smoke networking currently relies on BusyBox
  `udhcpc` already present in the source image.
- [x] Make the builder install the `KRUN_OSMODE:*` readiness marker script or
  systemd unit.
- [x] Make the builder create a raw ext4 root disk without requiring native
  macOS ext4 write support.
- [x] Make the builder emit a manifest JSON with source image reference, source
  image digest, builder image reference and digest, guest architecture, kernel
  path, kernel format, initramfs path, root device, filesystem type, optional
  root mount options, root disk checksum, and recommended `examples/os_mode`
  command.
- [x] Make the recommended `examples/os_mode` command attach the generated APFS
  clone destination instead of the immutable base `root.raw`.
- [x] Add a manifest checker that validates generated rootfs/root-disk
  checksums, APFS output metadata when required, and the generated `os_mode`
  and APFS clone commands before runtime boot.
- [x] Make the container-rootfs builder record the builder image digest and
  make the manifest checker require a valid builder image identity, so the
  Linux filesystem build environment is captured alongside the source OS image.
- [x] Make the container-rootfs builder record the Docker/Podman runtime version
  and make the manifest checker require it, so root-disk builds can be tied to
  the exact container runtime used for export and ext4 construction.
- [x] Make the container-rootfs builder record rootfs tar, root disk, and
  optional overlay artifact sizes, and make the manifest checker validate those
  sizes alongside checksums so truncated or swapped artifacts fail before boot.
- [x] Make the container-rootfs builder record the requested root disk size in
  MiB and make the manifest checker verify it matches the raw disk's apparent
  byte size, so `--size-mb` is enforced by manifest validation.
- [x] Make the container-rootfs builder record build-host metadata and make the
  manifest checker require it, so macOS container-to-VM artifacts carry the
  host system, release, architecture, and Python version used for generation.
- [x] Add a required container-rootfs manifest schema version and make the
  manifest checker reject unsupported versions, so future manifest evolution
  has an explicit compatibility boundary.
- [x] Make the container-rootfs builder record a UTC creation timestamp and
  make the manifest checker validate its ISO 8601 `Z` format, so artifact
  manifests can be ordered and compared without relying on filesystem mtimes.
- [x] Make the container-rootfs builder record the embedded Linux builder
  script SHA-256 and make the manifest checker require it, so root-disk
  artifacts identify the exact rootfs mutation and ext4 construction script.
- [x] Make the manifest checker reject internally inconsistent timing evidence,
  including boolean timing values and `timings_ms.total` values smaller than
  `export_rootfs + build_ext4`.
- [x] Make the container-rootfs builder support `--network-smoke`, which adds
  `KRUN_OSMODE_NET=1` to the generated launch command, requires DHCP tooling,
  and records `KRUN_OSMODE: network=up` as an expected smoke marker.
- [x] Make the container-rootfs builder record a recommended smoke timeout in
  the manifest, defaulting to longer timeouts for systemd and network-smoke
  profiles.
- [x] Make the container-rootfs builder record whether smoke replay should
  append `--poweroff-after-ready` so clean-shutdown smoke runs can be generated
  without mutating the production launch command.
- [x] Make the container-rootfs builder record a post-readiness smoke exit wait
  when smoke poweroff is enabled so replayed smoke validation proves the VMM
  exits instead of being terminated by the host helper.
- [x] Make the manifest checker validate `network_smoke`, `expected_markers`,
  and the generated `KRUN_OSMODE_NET=1` launch command consistency.
- [x] Make the manifest checker reject launch commands that attach the
  immutable base `root.raw` instead of the APFS clone destination.
- [x] Make the manifest checker compare APFS clone source/destination paths
  after manifest-relative resolution so the immutable base image cannot be
  reused through an alternate spelling such as `./root.raw`.
- [x] Add a manifest-checker option that prints the validated APFS clone command
  and clone-backed launch command in the order callers should run them.
- [x] Make manifest `--print-commands` also print an `os_mode_smoke.py`
  wrapper command with expected markers so validation commands can be replayed
  directly from manifest evidence.
- [x] Make the container-rootfs manifest carry an `expected_root` value and
  make `--print-commands` pass it as `os_mode_smoke.py --expect-root`, so the
  macOS container-to-VM path proves the guest mounted the expected virtio-blk
  root instead of merely printing readiness.
- [x] Resolve manifest-relative artifact paths and repo-relative helper paths
  when printing clone and launch commands so they can be replayed from any
  current working directory.
- [x] Add host-independent negative checks for manifests that replace the
  expected `examples/os_mode` or `examples/os_mode_apfs_clone.sh` helpers.
- [x] Make the `examples/os_mode` launcher reject `--kernel-format` values
  outside the exported `KRUN_KERNEL_FORMAT_*` range before calling libkrun.
- [x] Make the `examples/os_mode` launcher reject root, init, and console values
  that would split into multiple kernel command-line tokens before calling
  libkrun.
- [x] Make `krun_set_kernel_console()` reject values that would split into
  multiple kernel command-line tokens in OS mode, including when the invalid
  console override was set before `krun_set_os_mode()`.
- [x] Cover those launcher rejections in the host-independent
  `OS_MODE_PARSE_SELFTEST` build.
- [x] Cover unexpected positional launcher arguments in the host-independent
  `OS_MODE_PARSE_SELFTEST` build.
- [x] Cover empty launcher host path and socket arguments in the
  host-independent `OS_MODE_PARSE_SELFTEST` build.
- [x] Add a manifest-checker `--clone-dest` print override so repeated launches
  can use fresh APFS clone paths without editing the generated manifest.
- [x] Reject empty manifest-checker `--clone-dest` values so command printing
  cannot turn an empty destination into the manifest directory.
- [x] Reject `--clone-dest` without `--print-commands` so clone destination
  overrides cannot be silently ignored.
- [x] Add a manifest-checker `--smoke-output` print override so the replayed
  smoke command can write JSON validation evidence next to the generated
  manifest without hand-editing the command.
- [x] Reject empty `--smoke-output` values and reject `--smoke-output` without
  `--print-commands`.
- [x] Add a manifest-checker `--perf-output` print override so the replayed
  timing command can write JSON evidence next to the generated manifest while
  carrying the same expected root and console assertions as smoke replay.
- [x] Reject `--perf-output` without `--print-commands`, make it refuse
  empty values, protected manifest artifact paths, missing parent directories,
  existing files, and collisions with `--smoke-output` or `--write-runbook`.
- [x] Make manifest `--print-commands` pass the manifest's smoke timeout to
  `os_mode_smoke.py --timeout`, so replayed full-OS/systemd boots do not
  silently inherit the helper's shorter default timeout.
- [x] Make manifest `--print-commands` append `--poweroff-after-ready` only to
  the smoke replay command when `smoke_poweroff_after_ready=true`.
- [x] Make manifest `--print-commands` pass
  `os_mode_smoke.py --wait-exit-after-ready` when the manifest records a
  positive post-readiness smoke exit wait.
- [x] Make manifest `--print-commands` require non-null kernel and initramfs
  paths to exist before printing clone, launch, smoke, perf, or runbook
  commands, so replay generation cannot publish commands for missing boot
  artifacts.
- [x] Make manifest `--print-commands` require repo-local replay helper scripts
  to exist before printing clone, smoke, perf, or runbook commands.
- [x] Make manifest schema-version and kernel-format validation reject boolean
  JSON values instead of accepting them as Python integers.
- [x] Add a manifest-checker `--write-runbook` option that writes an executable
  APFS clone plus smoke-validation script from the already validated manifest
  commands.
- [x] Make `--write-runbook` include the manifest-generated perf command when
  `--perf-output` is provided, so a single replay script can regenerate smoke
  validation JSON and guarded timing JSON.
- [x] Make `--write-runbook` refuse existing files and protected manifest
  artifact paths so replay script generation cannot overwrite `root.raw`,
  `rootfs.tar`, `manifest.json`, overlay artifacts, or the APFS clone
  destination.
- [x] Make manifest validation itself reject APFS clone destinations that
  resolve to protected build artifacts (`rootfs.tar`, overlay tar, the manifest
  file, or `root.raw`), so invalid manifests fail even before command printing.
- [x] Document the current supported macOS container-to-VM path as a
  container-image artifact build followed by APFS clone-backed libkrun/HVF boot,
  not Docker or Podman as the runtime proof.
- [x] Make `--smoke-output` refuse protected manifest artifact paths and make
  `--write-runbook` refuse the same path as `--smoke-output`, so JSON evidence
  cannot overwrite disk images or the replay script.
- [x] Make `--smoke-output` and `--write-runbook` reject missing parent
  directories before printing replay commands, so validation fails before boot
  instead of after the guest starts or during runbook file creation.
- [x] Make `--smoke-output` refuse existing files so replayed validation cannot
  silently overwrite prior JSON evidence.
- [x] Make `os_mode_smoke.py --output` itself reject missing parent directories
  and existing files before boot, so direct smoke runs have the same JSON
  evidence safety as manifest-generated replay commands.
- [x] Make `os_mode_perf.py --output` reject missing parent directories and
  existing files before boot, so timing/control evidence cannot silently
  overwrite prior JSON results.
- [x] Make the container-rootfs builder reject existing output artifacts
  (`rootfs.tar`, `overlay.tar`, `root.raw`, `vm-root.raw`, and
  `manifest.json`) before pulling, exporting, or building, so reruns cannot
  silently replace a base image or mix old APFS clone artifacts with a new
  manifest.
- [x] Make manifest command printing reject APFS clone destinations whose
  parent directories are missing or whose destination files already exist,
  including both the manifest default clone path and `--clone-dest` overrides.
- [x] Wire the container-rootfs builder to run the manifest checker before it
  reports a successful build.
- [x] Make the builder copy or move the generated raw disk to a caller-selected
  base-image directory on the macOS host.
- [x] Add explicit APFS-volume detection to the builder or launcher so
  non-APFS output directories are reported before clone-backed launch.
- [x] APFS-clone the container-derived base image before launch.
- [x] Boot the APFS clone on macOS/ARM64 HVF with `examples/os_mode`.
- [x] Validate `KRUN_OSMODE: pid1=...` identifies the guest init from the
  container-derived OS, not `init.krun`.
- [x] Validate `KRUN_OSMODE: root=...` identifies the generated virtio-blk root.
- [x] Validate outbound networking with gvproxy from the container-derived root
  disk when networking is requested.
- [x] Validate clean shutdown for the container-derived root disk.
- [x] Record container-derived image build time, APFS clone time, and VM boot
  time separately.
- [x] Document limitations for ordinary application container images that do not
  contain a bootable init system.
- [x] Document the difference between using Docker/Podman as a build/export
  tool and using libkrun/HVF as the runtime.
- [x] Add troubleshooting for container images missing `/sbin/init`, DHCP,
  console output, or matching kernel modules.
- [x] Add troubleshooting for systemd dependencies once the systemd
  container-derived image exists.
- [x] If a systemd container-derived image is in scope, validate a minimal
  systemd boot and record services that must be masked for libkrun OS mode.
- [x] Add a Debian systemd source image recipe and builder `--init-mode systemd`
  adaptation path.
- [x] Build the Debian systemd source image on macOS.
- [x] Convert the Debian systemd source image into a raw ext4 root disk with
  `--init-mode systemd`.
- [x] APFS-clone and boot the Debian systemd root disk on macOS/ARM64 HVF.
- [x] Record Debian systemd boot markers, shutdown behavior, and timing.

### Phase 20: Systemd Networking and Production Image Hardening

- [x] Validate gvproxy networking from the Debian systemd root disk.
- [x] Decide whether the Debian systemd profile should use Debian's own guest
  kernel/initramfs or continue using the known-good Alpine virt kernel for
  macOS/ARM64 HVF.
- [x] Replace the validation-only `KRUN_OSMODE_POWEROFF=1` path with a reusable
  launcher/test option that can request shutdown without changing production
  boot behavior.
- [x] Decide whether the systemd unit mask list should be configurable by image
  profile instead of hard-coded in the builder.
- [x] Add a persistent-VM systemd boot test that does not auto-poweroff and
  validates serial login or another managed control channel.
  - [x] Add validation-only systemd serial control-shell image support.
  - [x] Add host-side control-command and control-marker validation support.
  - [x] Run the persistent macOS/ARM64 HVF systemd control-channel boot test
    and record its evidence.
- [x] Validate package-manager and journald writes on APFS clone-backed root
  disks over repeated boots.
- [x] Record a larger-root APFS clone storage-growth baseline for Debian
  systemd after representative writes.

### Phase 21: Pull-to-Launch OCI OS Bundle on macOS

- [x] Define `libkrun.os-bundle.v1` as the first OCI-packaged OS bundle schema.
- [x] Decide that the first importer consumes a normal Docker-compatible image
  with files under `/libkrun-os-bundle/`; OCI artifact/native layout support
  remains a later extractor backend.
- [x] Document the minimum required files: `manifest.json`, `root.raw`,
  `kernel`, and optional `initramfs`.
- [x] Document the required guest platform for the first macOS product path:
  `linux/arm64` with `ttyAMA0`.
- [x] Add a bundle publisher helper that takes an existing validated
  container-derived artifact directory and creates a Docker-compatible image
  containing `/libkrun-os-bundle/`.
- [x] Make the publisher copy the immutable base `root.raw`, not a per-VM APFS
  clone, into the image.
- [x] Make the publisher record kernel, initramfs, root disk, and manifest
  SHA-256 values after the final image filesystem is assembled.
- [x] Make the publisher reject source manifests whose launch command points at
  the immutable base `root.raw` instead of a mutable per-VM APFS clone.
- [x] Make the publisher support local image tags through optional Docker/Podman
  build.
- [x] Decide how published bundle images should be pushed and consumed by
  digest-pinned remote names.
- [x] Add an importer helper for macOS, for example
  `examples/os_mode_import_container_bundle.py`.
- [x] Make the importer accept an image reference, output directory, optional
  clone destination, optional smoke JSON output path, and optional `--run`
  flag.
- [x] Make the importer use Docker or Podman copy/export-style extraction for
  the first implementation, because those dependencies already exist for macOS
  rootfs construction.
- [x] Keep the importer structured so a later `skopeo`, `oras`, or native OCI
  layout extractor can replace Docker/Podman without changing manifest
  semantics.
- [x] Make the importer reject empty image references and host paths before
  invoking Docker or Podman.
- [x] Make the importer require an immutable image digest when strict mode is
  enabled.
- [x] Make the importer export only `/libkrun-os-bundle/` into the selected
  host artifact directory.
- [x] Make the importer reject existing output artifacts unless an explicit
  cache/reuse mode is provided.
- [x] Make the importer reject path traversal, absolute paths, and symlinks
  that escape the extracted bundle directory.
- [x] Make the importer reject bundle manifests with missing schema version,
  wrong `kind`, unsupported platform, unsupported kernel format, or unsupported
  root filesystem type.
- [x] Make the importer verify the kernel, initramfs, and root disk checksums
  against the manifest before APFS cloning.
- [x] Make the importer verify `root.raw` apparent size before launch.
- [x] Make the importer record or validate `root.raw` allocated size when
  available.
- [x] Make the importer require APFS output for the default macOS product path.
- [x] Make the importer create a fresh APFS clone of the extracted `root.raw`
  for every `--run`.
- [x] Make the importer refuse to attach the extracted immutable `root.raw` as
  the writable root disk.
- [x] Make the importer print a clone command, host-side launch command, and
  smoke command without running them when `--run` is not set.
- [x] Add importer perf command printing; the first implementation prints clone,
  host launch, smoke, and optional perf commands.
- [x] Make the importer launch `examples/os_mode` from the macOS host when
  `--run` is set; do not launch the VMM process inside Docker or Podman.
- [x] Make the importer pass expected root, console, readiness, and
  clean-shutdown markers to `examples/os_mode_smoke.py`.
- [x] Make the importer pass an explicit expected PID 1 value to smoke
  validation once the smoke helper supports checking a PID 1 allow-list.
- [x] Make the importer write smoke JSON evidence and include the image digest,
  extracted bundle path, APFS clone path, and host launch command in that
  evidence.
- [x] Add an explicit reuse mode for digest-pinned or otherwise stable bundle
  imports so repeat launches can skip Docker/Podman extraction when cached
  import metadata matches the requested image reference.
- [x] Add host-independent importer parser and manifest negative tests to
  `make os-mode-checks`.
- [x] Add positive tests using a synthetic tiny bundle directory that does not
  require Docker, HVF, or large disk artifacts.
- [x] Add negative tests for missing files, checksum mismatches, bad schema,
  unsupported platform, unsupported kernel format, unsafe paths, existing clone
  destination, and launch command pointing at immutable `root.raw`.
- [x] Build a real `linux/arm64` OS bundle image from the already validated
  Debian systemd artifact directory.
- [x] Pull or reference that bundle image on macOS and extract it without
  rebuilding `root.raw`.
- [x] APFS-clone the extracted `root.raw` and boot it on macOS/ARM64 HVF.
- [x] Validate that the VMM process is a host process, not a Docker/Podman
  child running inside the container runtime VM.
- [x] Validate that PID 1 is systemd or the expected guest init and not
  `init.krun` or a Docker entrypoint.
- [x] Validate root, console, readiness, clean shutdown, and optional gvproxy
  networking markers from the bundle-launched guest.
- [x] Verify the extracted immutable `root.raw` checksum is unchanged after the
  guest writes to the APFS clone.
- [x] Re-run the same extracted bundle with a second clone destination and
  verify the second boot does not require image re-export or root-disk rebuild.
- [x] Record image pull time, bundle extraction time, APFS clone time, VMM
  setup time, kernel boot time, userspace readiness time, and shutdown time
  separately.
- [x] Document the pull-to-launch command sequence in `examples/os_mode.md`.
- [x] Add troubleshooting for bundle images missing required files, stale
  digests, non-APFS output directories, unsafe paths, and architecture
  mismatches.
- [x] Decide whether successful importer smoke evidence should be append-only
  in `design_docs/os_mode_validation_log.md` or stored as standalone JSON
  artifacts referenced from that log.

Decision: bundle smoke/perf evidence should be stored as standalone JSON
artifacts next to the extracted bundle or validation run directory, and
`design_docs/os_mode_validation_log.md` should reference the artifact paths and
summarize key markers/timings. Do not append full smoke JSON into the markdown
log because the merged guest output can be long and should remain machine
readable for later comparisons.

### Phase 22: Productize macOS Container OS Launch

This phase turns the validated example-level OCI bundle flow into the required
macOS user experience: run a complete Linux OS packaged in a container image
from a macOS host, with libkrun/HVF as the actual runtime.

- [x] State in the design that "Linux OS in a container from macOS" means an
  OCI image carrying a complete libkrun OS bundle, not Docker Desktop or
  Podman as the production sandbox.
- [x] Keep the rootfs-source builder as the authoring path for ordinary distro
  or application images that are not already bootable OS bundles.
- [x] Keep the OS-bundle importer as the consumption path for prepared images
  that already contain `manifest.json`, `root.raw`, `kernel`, and optional
  `initramfs`.
- [x] Support `--image ... --run` so a single helper invocation can extract the
  bundle, validate it, APFS-clone the root disk, launch the host-side VMM, and
  write smoke evidence.
- [x] Support digest-pinned strict mode so remote bundle images can be treated
  as immutable launch inputs.
- [x] Support opt-in extracted-bundle reuse so repeat launches can skip the
  Docker/Podman extraction step when the cached image metadata matches.
- [x] Keep APFS clone creation per-launch even when extracted bundle reuse is
  enabled, so each VM gets a fresh writable disk.
- [x] Record evidence that the VMM process was launched by the macOS host-side
  smoke helper, not by Docker Desktop or Podman.
- [x] Record timing fields that separate image pull or archive load, image
  extraction, APFS clone creation, smoke/runtime execution, post-extraction
  runtime, and total importer time.
- [x] Record structured observed marker values in smoke and perf evidence so
  runtime validation does not have to infer PID 1, root, console, or network
  status only from raw output lines.
- [x] Make the bundle importer reject smoke evidence whose structured observed
  root, console, or PID 1 values do not match the bundle manifest before
  enriching the JSON with bundle metadata.
- [x] Add a short top-level README path that points macOS users directly at the
  OCI OS-bundle flow before the lower-level rootfs-source authoring flow.
- [x] Add a clean-machine macOS checklist covering Docker Desktop or Podman,
  Homebrew `llvm`/`lld`, Xcode command-line tools, APFS output location,
  code-signing/entitlements, and the expected `make BLK=1 NET=1 ...` build.
- [x] Decide whether `examples/os_mode_import_container_bundle.py` remains the
  supported entrypoint or should be wrapped by a shorter product command such
  as `krun-os-run IMAGE`.
- [x] Add a stable published test image or documented local image build target
  so the macOS flow can be reproduced without relying on `/private/tmp`
  artifacts from one developer machine.
- [x] Add a macOS CI or manual release checklist that runs the full
  `--image ... --run` flow on Apple Silicon and archives the smoke/perf JSON
  evidence.
- [x] Add a native OCI extraction backend evaluation. Docker/Podman extraction
  is acceptable for the first implementation, but native `oras`, `skopeo`, or
  OCI-layout support would avoid starting the container runtime VM when the
  image is only being used as a file transport.
- [x] Define cache eviction and disk-usage policy for extracted bundles and
  per-launch APFS clones, including how the product reports allocated-size
  growth after guest writes.
- [x] Add user-facing diagnostics that distinguish image-pull/extraction
  failures, manifest/digest failures, APFS clone failures, HVF entitlement
  failures, guest boot failures, and readiness-marker failures.
- [x] Add a compatibility table of known-good bundle images, guest kernels,
  initramfs choices, PID 1 expectations, required guest modules, and networking
  support on macOS/ARM64 HVF.
- [x] Add a release gate requiring that an OCI-packaged Debian systemd bundle
  and a minimal BusyBox/Alpine bundle both boot from a fresh APFS clone on
  macOS/ARM64 HVF.
- [x] Add a release gate requiring repeated launch from one extracted
  digest-pinned bundle image with different APFS clone destinations and no
  second root-disk rebuild.
- [x] Add a release gate requiring the immutable extracted `root.raw` checksum
  to remain unchanged after package-manager, journald, and readiness writes in
  the guest clone.
- [x] Add a release gate requiring macOS networking evidence for a bundle image
  when networking is declared supported by that image's manifest.
- [x] Keep Linux/KVM runtime gates deferred until a real Linux host with
  `/dev/kvm` is available; traditional Docker on macOS is not a substitute for
  Linux/KVM or macOS/HVF runtime validation.

Decision: `examples/os_mode_import_container_bundle.py` remains the supported
macOS OS-bundle entrypoint for the current implementation because it exposes
the validation and evidence-producing options needed while the API is still in
example tooling. A shorter product command can wrap it later, but it must keep
the same digest validation, APFS clone, host-side launch, and smoke-evidence
semantics.

Manual macOS release checklist for Phase 22:

1. Build libkrun and `examples/os_mode` on Apple Silicon with
   `LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib PATH=/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:$PATH make BLK=1 NET=1 CLANG=/opt/homebrew/opt/llvm/bin/clang`
   followed by `cd examples && make os_mode`.
2. Build or pull a `linux/arm64` container-derived source image and generate a
   validated artifact manifest with `examples/os_mode_build_container_rootfs.py`.
3. Publish that artifact as a local Docker-compatible bundle image with
   `examples/os_mode_publish_container_bundle.py --image-tag ...`.
4. Import and run both required bundle profiles on macOS/ARM64 HVF: a minimal
   BusyBox/Alpine-style bundle and a Debian `bookworm` systemd bundle. Each run
   must use a fresh APFS clone and write smoke JSON.
5. Re-run one digest-pinned bundle image with
   `--reuse-extracted-output-dir`, a fresh `--clone-dest`, and fresh smoke
   JSON.
6. For the Debian systemd profile, run a write-heavy validation that covers
   package-manager metadata, journald writes, and readiness marker writes, then
   prove the immutable extracted `root.raw` checksum is unchanged.
7. For any bundle manifest that declares networking support, run the macOS
   gvproxy/vmnet-helper path and require the expected network marker.
8. Archive the smoke JSON, optional perf JSON, bundle manifest, source
   manifest, exact image reference or local tag, host macOS version, host CPU,
   APFS volume path, and build command.
9. Confirm the evidence proves host-side VMM launch, expected PID 1, expected
   root, expected console, readiness, clean shutdown, immutable `root.raw`
   checksum stability, and separated extraction/APFS clone/runtime timings.

Native OCI extraction backend evaluation:

- Keep Docker/Podman extraction as the first supported backend because the
  container-rootfs authoring path already requires one of those runtimes on
  macOS and the current importer validates the host files after extraction.
- Decision for the first released macOS path: Docker or Podman remains a
  required dependency for `--image` bundle extraction. This is acceptable
  because extraction is artifact transport, not the libkrun runtime, and the
  host-side importer validates all extracted files before APFS clone creation
  or HVF launch.
- Prefer a later native OCI backend when the product needs faster pure
  pull-to-launch startup or wants to avoid starting Docker Desktop or a Podman
  machine just to copy files from `/libkrun-os-bundle/`.
- `oras` is a good fit if OS bundles move to OCI artifact/layout semantics, but
  it is not a drop-in replacement for Docker-compatible images that are
  expected to have a root filesystem and `Containerfile`.
- `skopeo` can copy image contents without a long-running daemon, but still
  adds a larger external dependency and needs macOS packaging validation.
- A native OCI layout reader gives the most control over path and symlink
  validation, but it should be added only after the bundle manifest and
  digest-validation contract are stable enough to justify maintaining another
  extractor.
- Any replacement backend must preserve the current importer invariants:
  digest-pinned strict mode, extraction of only `libkrun-os-bundle/`, path
  traversal rejection, symlink escape rejection, APFS output validation,
  per-launch APFS clone creation, host-side VMM launch, and smoke/perf evidence
  enrichment.
- Native extraction is therefore deferred rather than partially implemented.
  If it is added later, it must run the same host-independent negative tests as
  the Docker/Podman backend, plus backend-specific tests proving path traversal,
  symlink escape, digest mismatch, unsupported platform, non-APFS output, stale
  output paths, APFS clone creation, host-side launch, and smoke-evidence
  enrichment behavior are unchanged.

OS bundle release artifact policy:

- Publish prepared OS bundles as OCI images containing exactly one
  `/libkrun-os-bundle/` directory with `manifest.json`, `root.raw`, `kernel`,
  optional `initramfs`, optional `source-manifest.json`, and optional
  provenance artifacts explicitly named by the release process.
- Use architecture-specific image tags. For the first macOS product path,
  release tags must identify `linux/arm64`, the distribution/profile, and an
  update version, for example
  `registry.example.com/libkrun-os/debian-systemd:bookworm-arm64-YYYYMMDD`.
- Treat mutable tags as discovery aliases only. Every release note, runbook,
  CI gate, and support request must record and use the digest-pinned
  `image@sha256:...` reference with `--strict-digest`.
- Publish the digest-pinned image reference next to the release artifact by
  using `examples/os_mode_publish_container_bundle.py --push --digest-output`.
- If a registry push is unavailable, publish a Docker-compatible archive and
  SHA-256 sidecar using
  `examples/os_mode_publish_container_bundle.py --archive-output
  --archive-sha256-output --artifact-manifest-output`; consumers must verify
  the archive checksum before loading it and should treat the loaded mutable tag
  as a local test artifact unless a registry digest is also available.
- Record guest platform, expected console, expected PID 1, root device,
  root filesystem type, kernel format, kernel digest, initramfs digest when
  present, root disk digest, root disk apparent size, root disk allocated size
  when available, source image reference, source image digest, builder image
  reference, builder image digest, builder script digest, and creation time in
  the bundle manifest or source manifest.
- Publish kernel provenance for every bundle: upstream kernel version or distro
  package version, config fragment or package identity, initramfs recipe when
  present, and the reason the kernel/initramfs is compatible with libkrun's
  virtio-mmio/HVF device model.
- Publish root disk provenance for every bundle: source OCI image reference and
  digest, rootfs adaptation mode, injected units/scripts, systemd masks,
  network tooling, serial readiness setup, package list or package lock source
  where practical, and root disk build command.
- Release cadence is profile-specific. Security-sensitive distro images should
  be rebuilt after upstream base image or kernel security updates; smoke/demo
  images may use an explicit manual cadence but must publish their build date
  in the tag or release metadata.
- A release is not accepted until the manual or CI release gate archives:
  exact digest-pinned image reference, bundle manifest, source manifest, host
  macOS version, host CPU, APFS volume, libkrun build flags, smoke JSON, perf
  JSON when collected, APFS clone path, immutable root digest before/after
  guest writes, and the exact command lines used.

OS bundle trust and attestation guidance:

- Digest pinning is required for reproducibility, but it is not a trust
  mechanism by itself. It proves that the pulled bytes match a named digest; it
  does not prove who built those bytes or whether the build recipe was
  acceptable.
- Official sample bundles should be signed at the OCI image level with a
  registry-supported signing tool such as cosign or an equivalent project
  release-signing mechanism. The signature should cover the digest-pinned
  image reference, not a mutable tag.
- Release metadata should include a signed statement binding the image digest
  to the bundle manifest digest, source manifest digest, source image digest,
  builder image digest, kernel digest, root disk digest, build command, and
  validation evidence digests.
- Consumers should verify the signature or attestation before importing
  third-party bundles, then run the importer with the digest-pinned image
  reference and `--strict-digest`.
- The importer should continue to enforce local safety regardless of trust:
  path traversal rejection, symlink escape rejection, digest validation, APFS
  clone creation, host-side launch, and smoke-evidence validation remain
  mandatory even for signed bundles.
- Unsigned third-party bundles are acceptable only for local development or
  explicitly untrusted testing. User-facing docs and release notes should avoid
  presenting unsigned images as safe production inputs.
- Future confidential-computing or remote-attestation work is separate from
  OS-bundle image signing. It can prove properties of a running guest or TEE
  launch, but it does not replace supply-chain verification of the OS bundle
  image distributed to macOS hosts.

### Phase 23: Finish the macOS Container OS Product Path

This phase tracks the remaining work to make "run a Linux OS in a container
from a macOS host" a complete user-facing capability rather than an
example-level validated flow. It intentionally keeps Linux-host runtime work
deferred; this phase is about the Apple Silicon/HVF product path.

Completion for this phase means the following on a macOS Apple Silicon host:
`./examples/krun_os_run.py IMAGE@sha256:...` can consume a prepared Linux OS
bundle image, validate the bundle, create a fresh APFS clone, boot the OS with
libkrun/HVF, observe the expected guest PID 1 and readiness markers, archive
smoke/perf evidence, and repeat the launch from cache without rebuilding the
root disk. Docker or Podman may be used for image transport and extraction in
the first release; they are not the runtime and they are not the validation
target.

- [x] Define the exact meaning of the requirement: the container image is the
  source or packaging format, and the running OS is a libkrun/HVF VM launched
  by a macOS host process.
- [x] Make the prepared OS-bundle image the product launch unit for macOS:
  users provide one container image reference; tooling extracts
  `/libkrun-os-bundle/`, validates it, APFS-clones `root.raw`, and launches the
  guest on the macOS host.
- [x] Preserve ordinary OCI distro/application images as authoring inputs
  rather than pretending they are directly bootable. Those images must be
  converted through the rootfs-source path before the prepared-bundle launcher
  can run them.
- [x] Implement the rootfs-source authoring path from ordinary OCI images to a
  bootable raw ext4 root disk.
- [x] Implement the prepared OS-bundle consumption path from an OCI image
  containing `libkrun-os-bundle/` to an extracted, validated, APFS-cloned,
  host-launched VM.
- [x] Validate the path locally with a Debian systemd `linux/arm64` bundle on
  macOS/ARM64 HVF, with PID 1 observed as `systemd`.
- [x] Validate repeat launch from the same extracted bundle directory using
  `--reuse-extracted-output-dir` and a fresh APFS clone destination.
- [x] Make smoke/perf evidence record structured observed root, PID 1, console,
  network, launcher process, child process, and timing fields.
- [x] Make bundle smoke enrichment reject stale or edited evidence whose
  observed root, console, or PID 1 does not match the manifest.
- [x] Publish or otherwise provide a durable sample `linux/arm64`
  `libkrun.os-bundle.v1` image outside `/private/tmp` so a clean macOS host can
  reproduce the documented flow without rebuilding the bundle locally. Current
  local artifact:
  `os_mode_artifacts/debian-systemd-bookworm-arm64/libkrun-osmode-debian-systemd-bundle-bookworm-arm64.tar`
  with SHA-256 sidecar, copied bundle/source manifests, and
  `libkrun-osmode-debian-systemd-bundle-bookworm-arm64.artifact.json`.
- [x] Add a stable product-facing command or script name. The first wrapper is
  `examples/krun_os_run.py IMAGE`, which delegates to the bundle importer while
  supplying product defaults.
- [x] Make the stable command represent the required macOS "Linux OS in a
  container" UX: one container image reference in, one host-side libkrun/HVF
  Linux OS boot out, with APFS clone provisioning in between.
- [x] Make the product-facing command require only an image reference for the
  default happy path. `examples/krun_os_run.py` derives an output/cache
  directory, enables extracted-bundle reuse, generates unique per-launch APFS
  clone and smoke evidence paths, and defaults strict digest checking on for
  digest-pinned image references while leaving all values overridable.
- [x] Require normal startup to avoid a rootfs rebuild. Prepared-bundle launch
  may load or pull/extract the container image when the cache is cold, but it
  must then use the extracted immutable bundle plus APFS clone creation; raw
  ext4 authoring belongs only in the explicit build/publish path.
- [x] Define the default macOS cache layout for extracted bundles and APFS
  clones. The wrapper uses `$KRUN_OS_BUNDLE_CACHE` when set, otherwise
  `~/Library/Caches/libkrun/os-bundles` on macOS, with one sanitized
  image-reference cache entry per bundle and per-launch clone/evidence files
  inside the extracted bundle directory.
- [x] Implement or document cache cleanup commands that can remove ephemeral
  clones and stale extracted bundles without deleting persistent VM disks.
  `examples/krun_os_run.py --clean-cache` removes only wrapper-generated
  ephemeral clone/evidence files by default; `--delete-extracted-bundles`
  removes safe extracted bundle cache entries only after refusing entries with
  unknown files.
- [x] Add a clean-host macOS runbook that starts from installing Docker Desktop
  or Podman and Homebrew dependencies, then runs one prepared OS-bundle image
  through libkrun/HVF with no local root-disk build.
- [x] Add a clean-host preflight helper that can be run before a release gate
  on a fresh Mac. `examples/os_mode_clean_host_preflight.py` validates
  macOS/arm64 host metadata, Docker/Podman availability, digest-pinned image or
  artifact-manifest input, artifact archive SHA-256, APFS placement, an absent
  derived bundle cache entry, a fresh release-evidence output path, and the
  exact `--clean-host-baseline` release-gate command without pulling, loading,
  APFS-cloning, or booting the guest. The helper requires `--json-output` so a
  passing preflight always leaves the JSON file consumed by the release gate's
  `--preflight-json`. Clean-host release gates copy that report into
  `clean-host-preflight.json` in the release-evidence archive and verify that
  it matches the image, cache entry, output directory, APFS checks,
  macOS/arm64 host assumptions, a valid UTC preflight timestamp, and the UTC
  ordering between preflight collection and release-evidence collection. The
  release gate also checks
  that the preflight's recorded `release_gate_command` names the expected
  `os_mode_release_gate.py` helper, does not use
  `--allow-existing-output-dir` or `--skip-pull`, contains no unknown options
  or repeated options or trailing positional arguments, keeps the
  preflight-generated option order, ends with `--clean-host-baseline`, and is
  bound to the same `--preflight-json`, `--output-dir`, explicit
  `--cache-dir`, runtime, cache entry, positional image, and artifact-manifest
  or registry image mode before booting the guest. The preflight helper itself
  also rejects existing-output and
  existing-cache compatibility flags so an `ok=true` preflight cannot emit a
  command that the clean-host release gate will refuse.
- [x] Add a single clean-host baseline wrapper so the final manual run does not
  depend on copy/pasting matching preflight and gate commands.
  `examples/os_mode_clean_host_baseline.py` builds a matching
  `os_mode_clean_host_preflight.py --json-output ...` command and
  `os_mode_release_gate.py --clean-host-baseline --preflight-json ...` command
  from one image or artifact manifest, one cache configuration, and one
  release-evidence output directory. `make os-mode-clean-host-baseline` wraps
  the same helper for root-level release runs and forwards cache, preflight,
  runtime, build-command provenance, and accepted-output paths. When both
  `IMAGE` and `ARTIFACT_MANIFEST` are supplied, the Make wrapper forwards both
  so the helper can reject digest-reference mismatches instead of silently
  trusting only the artifact manifest. The clean-host preflight report also
  records both inputs in its generated release-gate command when both are
  supplied. The release gate records `image_was_explicit` in
  `release-gate-summary.json` and verifies that an artifact-manifest preflight
  includes a positional image exactly when `IMAGE` was supplied to the gate.
  The offline release-evidence verifier repeats that check, including the
  recorded release-gate command's option values, `clean_host_baseline=true`,
  and any digest-pinned image references in that command, before accepting an
  archived clean-host baseline table. It also verifies that the
  archived smoke importer command ran the same digest-pinned `image_ref` from
  the same derived bundle cache entry and wrote smoke markers matching the
  archived smoke JSON, that the perf command used the APFS clone created by the
  recorded perf clone command and wrote perf root, PID 1, console, optional
  network, and timing markers matching the archived perf JSON, and that
  artifact-delivered runs loaded the archive recorded by the artifact manifest.
- [x] Make the baseline wrapper optionally run final strict acceptance after
  the release gate. `--accept-json-output` and `--accept-table-output` append
  an `os_mode_clean_host_acceptance.py` command with the correct `--artifact`
  or `--pull` requirement for archive-delivered or registry-delivered evidence.
  `--design-doc-output` then renders the accepted JSON into the design-doc
  snippet only after strict acceptance succeeds; `--evidence-label` and
  `--final-release-baseline` are rejected unless a design-doc output path is
  present.
- [x] Replace any `/private/tmp/...` evidence paths in user-facing docs with
  reproducible commands and stable artifact names; keep `/private/tmp` paths
  only in the validation log as historical local evidence.
- [x] Add a release artifact policy for bundle images: required tags, digest
  publication, supported guest architecture, guest kernel provenance, root disk
  provenance, and update cadence.
- [x] Add signature or attestation guidance for bundle images. Digest checking
  proves immutability, not trust; a release process needs a separate trust
  story before users run third-party OS bundles.
- [x] Add a negative end-to-end test where a bundle image has a valid container
  layout but the manifest declares the wrong platform, root digest, console, or
  expected PID 1, and prove launch is blocked before HVF starts.
- [x] Add a negative prepared-bundle launcher test for generic/non-bundle
  images: missing `/libkrun-os-bundle/manifest.json` must fail as an image
  extraction or manifest-validation problem before APFS clone creation or HVF
  launch.
- [x] Add a negative end-to-end test where a bundle imports successfully but
  smoke evidence reports `init.krun`, the wrong root, or the wrong console, and
  prove evidence enrichment rejects it.
- [x] Add a performance baseline table for the product path on a clean Apple
  Silicon host: image load/pull/export, bundle extraction, APFS clone, first
  kernel log, root marker, PID 1 marker, ready marker, clean poweroff, and
  total time.
  The importer now has `--pull` so clean-host runs can record an explicit image
  pull phase in smoke evidence, `examples/os_mode_baseline_table.py` renders
  the table from release evidence archives, and `examples/os_mode_release_gate.py`
  orchestrates the clean-host run from either a digest-pinned registry image or
  a `libkrun.os-bundle.artifact.v1` archive manifest. Local release-gate
  evidence now exists under
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-local2/`
  and artifact-manifest evidence exists under
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-local/`,
  with a stricter fresh-cache artifact run under
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-clean-fresh-local/`
  and an absent-cache artifact run under
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-absent-local/`.
  `--clean-host-baseline` is now the preferred command mode for this gate; the
  local shortcut run under
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-clean-host-shortcut-local/`
  recorded `bundle_extraction=7646 ms`, `apfs_clone=114 ms`, `root=842 ms`,
  `pid1=845 ms`, `ready=848 ms`, clean poweroff, and `total=9778 ms`, with
  `clean_host_baseline=true` and `require_cache_entry_absent=true`. That local
  run predates the archived `clean-host-preflight.json` requirement, so it is
  historical timing evidence rather than current clean-host acceptance
  evidence. The strict local rehearsal that introduced artifact manifest
  preflight, smoke-based first-boot-log timing, perf marker timing, artifact
  archive-load timing, and enforced acceptance-checklist paths is
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8/`
  with historical accepted table
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8.baseline.md`.
  It recorded artifact load `933 ms`, export `1684 ms`, bundle extraction
  `17812 ms`, APFS clone `401 ms`, first boot log `208 ms`, root marker
  `2093 ms`, PID 1 marker `2103 ms`, ready marker `2115 ms`, clean poweroff,
  and total `22310 ms`; the table's first timing column renders this as
  `933/-/1684` for load/pull/export. This run also records and verifies the
  host-side launcher process relationship in the release-evidence summary:
  `launcher_pid=74750`, `process_parent_pid=74750`, and `process_pid=74751`.
  A historical command-binding acceptance output also exists at
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8.command-binding.acceptance.json`;
  its checklist includes `host-side launch command binding` proving the smoke
  helper launched host-side `examples/os_mode` with the APFS clone destination
  as the root disk. After adding the bundle-provenance checklist item,
  acceptance was run again historically and wrote
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8.audit.acceptance.json`;
  its checklist includes `bundle provenance`, tying the accepted row to the
  source image, source digest, platform, root disk digest, kernel digest,
  initramfs digest, expected root, expected console, expected PID 1, and
  imported bundle image. This archive now predates the required
  `image_was_explicit` summary field, so the current verifier rejects it; the
  failed re-acceptance record is
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local8.image-mode.acceptance.json`.
  The historical local9 rehearsal was accepted under the image-mode summary
  contract before the build-provenance checklist item existed, and the
  historical local10 rehearsal was accepted only as a throwaway check because
  the caller-supplied build command was malformed. The current local rehearsal
  is
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local12/`
  with accepted JSON
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local12.strict3.acceptance.json`,
  accepted table
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local12.strict3.baseline.md`,
  and rehearsal design-doc snippet
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-current-local12.strict3.design-doc.md`.
  It records the current summary contract, including
  `image_was_explicit=false` for artifact-manifest-only invocation and a
  preflight `release_gate_command` with no positional image. It also records
  build provenance: a caller-supplied libkrun build command plus generated
  `artifact_load_command=...` and `smoke_importer_command=...` entries. It
  recorded artifact load `1123 ms`, export `1684 ms`, bundle extraction
  `8237 ms`, APFS clone `113 ms`, first boot log `110 ms`, root marker
  `806 ms`, PID 1 marker `812 ms`, ready marker `815 ms`, clean poweroff, and
  total `10010 ms`; the table's first timing column renders this as
  `1123/-/1684` for load/pull/export.
  The current acceptance checklist also includes `build provenance` and
  `release-gate summary`; together these expose the build command, generated
  artifact-load and smoke-import commands, strict clean-host summary fields,
  and path bindings enforced by the verifier with
  `--require-build-provenance`, including whether the release-gate image was
  explicit and whether that matches the preflight command's positional
  arguments. The current accepted JSON records
  `accepted_at_utc=2026-05-18T23:01:50Z` and
  `final_release_baseline=false`, so the rehearsal snippet remains `Open`.
  `examples/os_mode_design_doc_baseline.py` and
  `make os-mode-design-doc-baseline` now turn the accepted JSON into the exact
  Markdown snippet and completion-audit row needed below; local rehearsal
  snippets keep that row `Open` unless `FINAL_RELEASE_BASELINE=1` is supplied.
  Final clean-host evidence now exists under
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-final-clean-host-20260519b/`
  with accepted JSON
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-final-clean-host-20260519b.acceptance.json`,
  accepted table
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-final-clean-host-20260519b.baseline.md`,
  and design-doc snippet
  `os_mode_artifacts/debian-systemd-bookworm-arm64/release-evidence-artifact-final-clean-host-20260519b.design-doc.md`.
  The accepted JSON records `final_release_baseline=true`, all 18 required
  checklist items passed, and `make os-mode-audit-final-baseline` accepted the
  artifact set. The final table is:

  | Label | Image load/pull/export ms | Bundle extraction ms | APFS clone ms | First log ms | Root marker ms | PID 1 marker ms | Ready marker ms | Clean poweroff | Total ms |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | libkrun-osmode-debian-systemd-bundle@sha256:fd33fd3b49ad19fb63770f60a844c0f085d2b59c8f28ccb79e84816c0cb7fc0b | 2692/-/1684 | 4595 | 245 | 472 | 612 | 614 | 617 | yes | 6500 |
- [x] Add a no-Docker-rebuild repeat-launch baseline showing the same bundle
  image can start repeatedly from cached extracted artifacts using only APFS
  clone creation plus host-side libkrun/HVF boot. Latest local evidence:
  `smoke-repeat-baseline1.json` recorded `bundle_extraction_reused=true`,
  `bundle_extraction=0 ms`, `apfs_clone=74 ms`, `smoke=751 ms`,
  `post_extraction_run=827 ms`, and PID 1 `systemd`.
- [x] Decide whether the first released macOS path requires Docker/Podman for
  pure bundle extraction or includes a native OCI extractor. Native extraction
  remains optional for correctness but may be required for the fastest product
  startup.
- [x] If a native extractor is added, validate it against the same path
  traversal, symlink escape, digest, APFS, clone, launch, and smoke-evidence
  invariants as the Docker/Podman backend. Native extraction is not included in
  the first release path; the required future validation invariants are
  documented above.
- [x] Add user-facing diagnostics that clearly separate image resolution,
  image extraction, manifest validation, APFS clone, HVF entitlement,
  guest-kernel boot, guest-init readiness, and networking failures. The first
  implemented surface is `diagnostic_category=...` from the bundle importer;
  host-independent tests cover representative image-resolution,
  manifest-validation, output-path, cache-reuse, APFS, host-launcher, and
  guest-readiness classifications.
- [x] Add a macOS manual or CI release gate on Apple Silicon that archives the
  exact image reference, bundle manifest, smoke JSON, perf JSON, host macOS
  version, host CPU, APFS volume, libkrun build flags, and command lines.
- [x] Add a verifier for release-gate archives so clean-host evidence can be
  checked mechanically before its baseline table is accepted. The verifier
  rejects missing copied artifacts, checksum mismatches, mutable image refs,
  stale clean-cache preflight, wrong root/console/PID 1 markers, missing perf
  timing fields, non-APFS evidence when required, and non-macOS/arm64 evidence
  when required.
- [x] Make the release-evidence verifier reject stale `baseline.md` content by
  recomputing the Markdown table from the archived release evidence before a
  clean-host baseline can be accepted.
- [x] Add a final clean-host acceptance helper that runs the strict verifier
  flags for a completed release-evidence archive and prints the baseline table
  only after clean-cache, absent-cache, APFS, macOS/arm64, perf,
  clean-poweroff, and clean-host-preflight evidence are all accepted. The
  helper validates requested accepted-output paths before archive verification,
  so bad final artifact destinations fail before the evidence is read. The
  acceptance JSON now also includes `schema_version=1`, `accepted_at_utc`,
  `required_checklist`, naming every required checklist item for that run, and an
  `evidence_checklist` tying the accepted row to concrete archived facts for
  `clean cache`, `absent cache entry`, `APFS output`, `macOS arm64 host`,
  `build provenance`, host-side launcher process metadata, host-side launch
  command binding to the APFS clone, bundle provenance, clean-host preflight,
  release-gate summary strict-mode fields, guest PID 1, first boot log
  timing, perf marker timings, clean poweroff, baseline row timings, and
  artifact load or registry pull timing; acceptance fails if any required
  checklist item is missing or not satisfied.
- [x] Keep Linux/KVM boot, Linux passt networking, and Linux `/dev/kvm` Docker
  smoke runs marked deferred until a real Linux host or Linux CI runner with
  KVM is available. Those gates are portability work, not blockers for proving
  the macOS container-to-HVF product path.

## macOS Product Completion Audit

This section is the short-form audit for the current product requirement:
consume a Linux OS packaged in a container image on a macOS host, provision it
quickly with APFS CoW, and boot it as a host-side libkrun/HVF VM. Linux/KVM
parity remains deferred and is not used to declare this macOS path complete.

| Requirement | Status | Validation |
| --- | --- | --- |
| One container image reference is the product input | Implemented | `examples/krun_os_run.py IMAGE` and `examples/os_mode_import_container_bundle.py --image ... --run` accept a prepared OS bundle image and launch from the macOS host. |
| The container runtime is not the production VM runtime | Implemented | Release evidence records the host-side smoke command and launcher process; acceptance requires `host-side launcher process` and `host-side launch command binding`. |
| Prepared bundle image contains a complete bootable OS artifact set | Implemented | `examples/os_mode_publish_container_bundle.py` writes `/libkrun-os-bundle/manifest.json`, `root.raw`, kernel, optional initramfs, and command metadata. |
| Ordinary OCI rootfs images can be used as authoring inputs | Implemented | `examples/os_mode_build_container_rootfs.py` exports a rootfs with Docker/Podman, builds raw ext4, validates the manifest, and records source/runtime provenance. |
| Generic non-bundle images are not silently treated as bootable OS bundles | Implemented | Host checks cover missing bundle-manifest failures before APFS clone creation or HVF launch. |
| Fast per-launch disk provisioning uses APFS CoW | Implemented | `examples/os_mode_apfs_clone.sh` creates a fresh clone and importer/release-gate evidence records APFS clone timing. Acceptance requires APFS evidence and clone-to-launch root binding. |
| Repeat launch skips rootfs rebuild and bundle extraction when cache is valid | Implemented | `examples/krun_os_run.py` uses a derived cache directory and `--reuse-extracted-output-dir`; repeat evidence records `bundle_extraction_reused=true`. |
| Guest boots its own Linux init rather than `init.krun` | Implemented | Smoke and verifier require observed PID 1 to match bundle `expected_pid1` and reject `init.krun`. Current local Debian systemd evidence observes `systemd`. |
| Boot/readiness timing is measured with phase separation | Implemented | Smoke/perf evidence separates image load or pull, export, bundle extraction, APFS clone, first kernel log, root marker, PID 1 marker, ready marker, clean poweroff, and total time; final accepted evidence is `release-evidence-artifact-final-clean-host-20260519b`. |
| Build commands are tied to accepted evidence | Implemented | Clean-host acceptance requires a caller-supplied build command plus generated artifact-load and smoke-import commands before a baseline table can be accepted. |
| Bundle provenance is mechanically tied to accepted evidence | Implemented | Release verifier and clean-host acceptance compare source image, source digest, platform, root disk digest, kernel digest, initramfs digest, expected root, console, PID 1, and imported image across bundle manifest, release summary, and archived smoke JSON. |
| Clean-host preflight proves the cache/output were absent before the final run | Implemented | `examples/os_mode_clean_host_preflight.py`, `examples/os_mode_clean_host_baseline.py`, and `examples/os_mode_release_gate.py --clean-host-baseline --preflight-json` archive and verify matching preflight facts. |
| Clean-host baseline table on a fresh Apple Silicon host | Implemented | Accepted final clean-host evidence `release-evidence-artifact-final-clean-host-20260519b` produced the baseline table below; checklist: clean cache, absent cache entry, APFS output, macOS arm64 host, build provenance, host-side launcher process, host-side launch command binding, bundle provenance, clean-host preflight, release-gate summary, guest OS markers, perf markers, first boot log timing, baseline marker timings, clean poweroff, baseline timing row, image load/pull/export timing, artifact delivery. |

### Prompt-to-Artifact Checklist

This checklist maps the user-requested deliverables to concrete artifacts that
must exist before the macOS container-to-HVF product path is considered done.

| User requirement | Artifact or gate | Current evidence |
| --- | --- | --- |
| Write the design in a repo-local `design_docs` directory | `design_docs/full_linux_os_mode.md` and `design_docs/os_mode_validation_log.md` | Implemented; this file is the design and the validation log records each local proof and guardrail. |
| Add a thorough TODO list | `## Detailed TODO` plus Phase 23 in this file | Implemented; all non-deferred Phase 23 items are checked. |
| Re-review for accuracy, validation, and macOS progress | Validation gates, completion audit, release-evidence verifier, and validation log | Implemented for host-independent checks, macOS/HVF runtime evidence, and final clean-host baseline acceptance. |
| Mark Linux-host-required work deferred | Linux/KVM boot, passt networking, Linux `/dev/kvm` Docker smoke, and Linux kernel-config gates | Implemented; Linux-host runtime gates are explicitly deferred and are not used to claim the macOS product path complete. |
| Run a Linux OS from a container image on a macOS host | `examples/krun_os_run.py`, `examples/os_mode_import_container_bundle.py`, and prepared `libkrun.os-bundle.v1` images | Implemented locally; evidence shows the macOS host extracts a prepared bundle image, creates an APFS clone, launches libkrun/HVF, and observes guest `systemd`. |
| Use APFS CoW for very fast startup from host files | `examples/os_mode_apfs_clone.sh`, importer APFS policy, smoke/perf timing evidence | Implemented locally; acceptance requires APFS evidence and launch-command binding to the APFS clone. |
| Avoid treating Docker Desktop as the runtime proof | Release evidence and acceptance checklist items for host-side launcher process and command binding | Implemented; Docker/Podman are only image transport/build tools, while `examples/os_mode` runs as a macOS host process. |
| Validate progress mechanically | `make os-mode-checks`, `examples/os_mode_verify_release_evidence.py`, `examples/os_mode_clean_host_acceptance.py` | Implemented; host-independent checks cover helper syntax, negative cases, command construction, verifier contracts, and final-baseline guardrails. |
| Produce final release-ready baseline artifacts | Fresh clean-host evidence directory, accepted JSON, accepted Markdown table, design-doc snippet, `final_release_baseline=true`, and a passing final-baseline artifact-set audit | Implemented; `release-evidence-artifact-final-clean-host-20260519b.acceptance.json` records `final_release_baseline=true`, the accepted Markdown and design-doc snippet match that JSON, and `make os-mode-audit-final-baseline` passed. |

The preferred final clean-host command for an archive-delivered run is:

```sh
make os-mode-clean-host-baseline \
  ARTIFACT_MANIFEST=path/to/libkrun-os-bundle.artifact.json \
  OUTPUT_DIR=path/to/fresh-clean-host-release-evidence \
  CACHE_DIR=path/to/fresh-clean-host-cache \
  PREFLIGHT_JSON=path/to/fresh-clean-host-preflight.json \
  ACCEPT_JSON_OUTPUT=path/to/fresh-clean-host-acceptance.json \
  ACCEPT_TABLE_OUTPUT=path/to/fresh-clean-host-baseline.md \
  DESIGN_DOC_OUTPUT=path/to/fresh-clean-host-design-doc.md \
  EVIDENCE_LABEL=fresh-clean-host-release-evidence \
  FINAL_RELEASE_BASELINE=1 \
  BUILD_COMMAND='LIBCLANG_PATH=/opt/homebrew/opt/llvm/lib PATH=/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/llvm/bin:$PATH make BLK=1 NET=1 CLANG=/opt/homebrew/opt/llvm/bin/clang'
```

The lower-level mechanical acceptance commands for an already archived
artifact-delivered run are:

```sh
make os-mode-accept-clean-host \
  EVIDENCE_DIR=path/to/fresh-clean-host-release-evidence \
  ARTIFACT=1 \
  JSON_OUTPUT=path/to/fresh-clean-host-acceptance.json \
  TABLE_OUTPUT=path/to/fresh-clean-host-baseline.md \
  FINAL_RELEASE_BASELINE=1

make os-mode-design-doc-baseline \
  ACCEPTANCE_JSON=path/to/fresh-clean-host-acceptance.json \
  EVIDENCE_LABEL=fresh-clean-host-release-evidence \
  DESIGN_DOC_OUTPUT=path/to/fresh-clean-host-design-doc.md \
  FINAL_RELEASE_BASELINE=1

make os-mode-audit-final-baseline \
  ACCEPTANCE_JSON=path/to/fresh-clean-host-acceptance.json \
  TABLE_OUTPUT=path/to/fresh-clean-host-baseline.md \
  DESIGN_DOC_OUTPUT=path/to/fresh-clean-host-design-doc.md \
  EVIDENCE_LABEL=fresh-clean-host-release-evidence
```

For lower-level acceptance, `FINAL_RELEASE_BASELINE=1` requires `JSON_OUTPUT`
and `TABLE_OUTPUT` so the final-baseline attestation is preserved in the
accepted JSON consumed by `make os-mode-design-doc-baseline` and the accepted
Markdown table is archived as a standalone artifact.

Before any release claim, use the fresh clean-host archive produced by
`make os-mode-clean-host-baseline`. The accepted `required_checklist` must
exactly match the ordered `evidence_checklist` names. For archive-delivered
evidence, the ordered list is:
`clean cache`, `absent cache entry`, `APFS output`, `macOS arm64 host`,
`build provenance`, `host-side launcher process`,
`host-side launch command binding`, `bundle provenance`, `clean-host
preflight`, `release-gate summary`, `guest OS markers`, `perf markers`,
`first boot log timing`, `baseline marker timings`, `clean poweroff`,
`baseline timing row`, `image load/pull/export timing`, and `artifact
delivery`. For registry-delivered evidence, replace
`artifact delivery` with `registry pull`.

## Open Design Questions

- Resolved for the first implementation: OS mode requires direct kernel boot through `krun_set_kernel()`.
- Resolved for the first implementation: `krun_set_os_root()` requires explicit prior `krun_set_os_mode()`.
- Resolved for the first implementation: no convenience `krun_configure_os_boot()` API is added until the smaller APIs are validated through runtime boot tests.
- Resolved for the first implementation: generated OS parameters are appended after caller-provided kernel command-line text.
- Resolved for the first implementation: workload-only APIs return `-EINVAL` after OS mode is selected.
- Resolved for the first implementation: raw root disks are the documented path; other formats remain unvalidated.
- Resolved for the first implementation: implicit vsock/TSI is disabled in OS mode, and networking must be explicit.
- Resolved for the first implementation: non-root `krun_add_virtiofs*()` mounts
  remain allowed, but `krun_set_root()` and `krun_add_virtiofs*()` with
  `KRUN_FS_ROOT_TAG` are rejected because they configure a workload-mode
  virtio-fs root.
- Resolved for the first implementation: x86_64 serial uses the existing legacy serial path and `ttyS0`; aarch64 uses PL011 and `ttyAMA0`.
- Resolved for the first implementation: aarch64 `earlycon=pl011,mmio32,...` is left to the existing MMIO serial registration path and is separate from the primary `console=ttyAMA0`.
- Resolved for the first implementation: block IDs are host-side identifiers, not a stable guest root naming contract; use `/dev/vda1` only for first smoke tests and prefer `PARTUUID=` for robust images.
- Resolved for the first implementation: APFS clone creation lives in example/helper tooling, not libkrun core.
- Resolved for the first implementation: APFS clone persistence is a caller policy; ephemeral callers delete clones after shutdown.
- Resolved for the current Alpine aarch64 smoke artifacts: runtime validation proved the documented aarch64 `ttyAMA0` console path on macOS/ARM64 HVF.
- Resolved for the current Alpine aarch64 smoke artifacts: virtio-blk root appears as `/dev/vda` on QEMU/HVF and libkrun/HVF.
- Resolved for the macOS container-rootfs design: Docker or Podman is used only
  to export and build Linux filesystem artifacts; the resulting OS runs as a
  libkrun/HVF VM from a raw virtio-blk disk.
- Resolved for the pull-to-launch design: an OCI image may package the complete
  libkrun OS bundle, but the macOS host still extracts the artifacts and starts
  libkrun/HVF outside Docker or Podman.
- Resolved for the current APFS validation: repeated boots of the same Debian
  systemd clone can write journald state and package-manager metadata without
  modifying the immutable base root image.
- Deferred until Linux host: known-good Linux/KVM guest kernel versions must be recorded after Linux smoke tests.

## Risks

- Stock distro kernels may not include virtio-mmio support in the right form, so the supported guest contract must be clear.
- Device names can differ across kernels and initramfs configurations. `/dev/vda1` should be treated as a convention, not a guarantee.
- macOS/ARM64 HVF parity constrains device and interrupt choices. Avoiding PCI in the first milestone is what keeps the feature tractable.
- APFS clones accelerate disk provisioning, not guest boot itself. Boot-time claims must report clone creation time separately from kernel and userspace startup.
- APFS clone behavior depends on the host filesystem. The implementation must detect unsupported filesystems and use a clear fallback rather than silently doing a slow full copy.
- APFS clone-backed disks still consume real storage as guests write. Clone cleanup and allocated-size monitoring need to be part of the operational model.
- Existing APIs have backwards compatibility requirements, especially `krun_set_root_disk_remount()` and workload-mode command-line behavior.
- Fast boot depends more on the guest image than on libkrun once the OS-mode handoff exists.
- Most OCI application images are not bootable OS images. The builder must
  either adapt them by injecting init/console/network setup or reject them with
  clear diagnostics.
- Docker Desktop on macOS runs Linux containers inside its own VM, so it cannot
  validate libkrun runtime behavior. It is useful for image construction only.
- OCI-packaged OS bundles can be large because they contain raw disk images.
  The importer must support digest-pinned caching and avoid unnecessary
  re-export or rebuild work after the first pull.
- Bundle extraction is a host filesystem write path. It must reject unsafe
  paths and symlinks before any APFS clone or launch command is generated.
- Resolved for the first importer: cache reuse is explicit and metadata-bound;
  default imports still require a fresh or empty output directory.
- Publishing a mutable per-VM clone as an OS bundle would bake guest state into
  the reusable image. The publisher must package only immutable base images
  unless the user explicitly creates a persistent VM image artifact.

## Success Criteria

The first complete version is successful when:

- Existing workload-mode tests and examples behave unchanged.
- A prepared Linux root disk boots with `/sbin/init` as PID 1.
- The same OS-mode API works on Linux/KVM and macOS/ARM64 HVF with documented architecture-specific guest kernels and console names.
- Console output is visible from early boot through login or init completion.
- A documented minimal image can boot without firmware, PCI, or libkrun's `init.krun` handoff.
- A Linux OS root disk can be generated from an OCI/container image on macOS,
  APFS-cloned, and booted with libkrun/HVF.
- A Linux OS bundle can also be consumed as an OCI image on macOS: pull or
  export the image, validate the included artifacts, APFS-clone `root.raw`, and
  boot it with host-side libkrun/HVF without rebuilding the root disk.
- macOS/ARM64 HVF can boot from an APFS clone-backed root disk created from an immutable base image.
- Validation records distinguish disk provisioning time, VMM setup time, kernel boot time, and guest userspace readiness time.
