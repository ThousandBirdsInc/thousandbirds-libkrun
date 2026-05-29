# Snapshot/Restore Implementation Plan

Companion to [`snapshot_restore.md`](snapshot_restore.md). That document is
the **audit + design contract**: what state libkrun must capture/restore,
what restore must avoid (entropy cloning, MAC reuse, time stalls), what
the boundaries are (same host/backend family, same libkrun version, same
CPU feature profile). This document is the **scheduled, file-pathed
implementation plan** that follows it.

## Status

- Audit + design contract: **landed** in `snapshot_restore.md`.
- This implementation plan: **landed** here.
- Wrapper-side scaffolding (manifest format, options, integration points):
  **landed** in the sibling `thousandbirds-agent-sandbox` repo (commit
  `<filled-in-after-commit>`). Wrapper consumers can already write code
  against `SandboxManager::snapshot` with `capture_memory: true`; it
  surfaces a typed error pointing at this doc until libkrun lands the
  capture path.
- Libkrun-side implementation (Phases A–D below): **not started**.

## Phasing

Phased so each phase is independently mergeable, compile-tested, and
moves the snapshot story forward without breaking the prior phase.

### Phase A — Public type surface + memory image format [foundations]

Goal: a stable Rust API surface the rest of the work hangs off, plus the
on-disk format. No backend implementation yet; no behavioral change for
existing libkrun consumers. Compile-only deliverable.

Concrete additions:

- New module `src/vmm/src/snapshot/` with:
  - `mod.rs` — public re-exports.
  - `state.rs` —
    - `pub trait SnapshotableVm` with `fn save_state(&self) -> Result<VmStateV1, SnapshotError>` and `fn restore_state(&self, state: &VmStateV1) -> Result<(), SnapshotError>`.
    - `pub trait SnapshotableVcpu` with the same `save_state`/`restore_state` shape over `VcpuStateV1`.
    - `pub struct VmStateV1`, `VcpuStateV1`: versioned, backend-tagged
      (`Kvm`, `Hvf`), tagged-union of architecture-specific state. The
      `V1` suffix is deliberate — Phase 4 dedup or future format changes
      get `V2` types without breaking `V1` consumers.
  - `image.rs` —
    - `pub struct MemoryImage` referencing a path + a manifest of which
      guest-physical regions are present.
    - `pub struct MemoryImageWriter { ... }` — streams guest memory
      regions to a sparse file. Page-aligned. Holes for never-touched
      pages.
    - `pub struct MemoryImageReader { ... }` — mmaps the image for
      restore. `MAP_PRIVATE` so the restored VM gets its own pages;
      Phase E (dedup) promotes selected immutable chunks to shared.
  - `manifest.rs` —
    - `pub struct SnapshotManifest`: libkrun version, format version,
      host backend (`kvm`/`hvf`), arch, vCPU count, memory size, CPU
      feature profile, kernel/initramfs/disk base checksum, device list
      + per-device state version, quiescence marker + timestamp, MAC
      policy, entropy reseed policy. Mirrors §"Restore Contract" in
      `snapshot_restore.md`.
    - JSON serialization. Manifest path conventions match what the
      sibling `thousandbirds-agent-sandbox` already writes for disk-only
      snapshots, so Phase 3 manifests can live in the same directory
      tree.
  - `errors.rs` — `pub enum SnapshotError` with variants
    `UnsupportedBackend`, `VcpuNotPaused`, `DeviceQuiesceFailed`,
    `MemoryWalkFailed`, `IoError`, `VersionMismatch`,
    `BackendCapabilityMismatch`.

- `src/vmm/src/snapshot/device.rs` — `pub trait SnapshotableDevice`:
  `save_state() -> DeviceStateV1`, `restore_state(&DeviceStateV1)`.
  Default impl returns `SnapshotError::UnsupportedBackend` so existing
  devices compile without immediate work.

- `Cargo.toml` and `src/vmm/src/lib.rs`: register the new module.

**Exit criteria:** `cargo check` passes. New types and traits are
exported. No existing code paths change behavior. A `tests/` snapshot
that builds against the new public API verifies it compiles from the
outside.

**Effort:** ~3–5 days, single engineer.

### Phase B — KVM x86_64 capture (Linux) [first runnable]

Goal: the existing private KVM `save_state`/`restore_state` in
`src/vmm/src/linux/vstate.rs:834` are exposed through the public
Snapshotable trait. Add memory walk + device serialization. Verifiable
on any Linux/KVM host or CI runner with `/dev/kvm`.

Concrete changes:

- `src/vmm/src/linux/vstate.rs`:
  - Promote the existing `VmState`/`VcpuState` to be wrappers around
    `VmStateV1::Kvm { ... }` / `VcpuStateV1::Kvm { ... }`. Today they
    are pub but their fields are private and the types are not
    re-exported; the Phase A wrapper types fix that.
  - `impl SnapshotableVm for Vm` and `impl SnapshotableVcpu for Vcpu`
    bridging existing private methods.

- `src/vmm/src/builder.rs`:
  - Add `pub fn save_guest_memory(&self, dst: &mut MemoryImageWriter)
    -> Result<(), SnapshotError>` walking `GuestMemoryMmap` regions.
  - Add `pub fn restore_guest_memory(&self, src: &MemoryImageReader)
    -> Result<(), SnapshotError>` mmap'ing into the new VM's regions
    before any vCPU runs.

- `src/devices/src/virtio/`:
  - Minimal `impl SnapshotableDevice` for `virtio-mmio` transport,
    `virtio-blk`, `serial`, `virtio-net` (when present), balloon, and
    `virtio-fs`. Each one captures features, status, queue PFNs, queue
    state, in-flight policy. Phase B requires a quiescent device set
    (zero in-flight requests) — the cooperative quiesce path in the
    sibling repo already provides that for Phase 2.

- KVM IRQ chip state: already captured by the existing `save_state`.
  Promote to public.

- `examples/snapshot_kvm_smoke.rs` (or under `tests/`): boots a tiny
  kernel, runs a marker, snapshots, exits, restores, verifies the
  marker is unchanged.

**Exit criteria:** on a KVM Linux host, boot a guest, write a marker
to anonymous memory, snapshot, exit the VM, restore, verify (a) the
marker is intact, (b) `uptime` resumes from the snapshot point not
from zero, (c) MAC has been refreshed, (d) wall-clock has advanced
without the guest observing a long stall. Verified by `cargo test
--features=kvm-snapshot` gated behind a `KRUN_SNAPSHOT_E2E=1` env so
HVF-only CI skips cleanly.

**Effort:** ~2 weeks. Most of it is device-level serialization (one
device at a time) and the memory walk; the vCPU/VM IRQ state work is
already there.

### Phase C — HVF aarch64 capture (macOS) [the hard one]

Goal: a full snapshot on macOS/HVF. This is the work
`snapshot_restore.md` audit identifies but defers. Split into
sub-phases so each one is independently reviewable.

#### C.1 — Pause + general register capture

- `src/hvf/src/lib.rs`:
  - `pub fn HvfVcpu::pause(&self) -> Result<(), Error>` using
    `hv_vcpus_exit` plus a per-vCPU acknowledgement so the caller can
    prove no vCPU is concurrently mutating guest memory.
  - `pub fn HvfVcpu::save_general_registers(&self) ->
    Result<AArch64GeneralRegs, Error>` covering x0–x30, sp_el0,
    sp_el1, pc, pstate, FP/SIMD state (q0–q31, fpsr, fpcr).
  - Matching `restore_general_registers`.

#### C.2 — System register capture

- `src/hvf/src/lib.rs`:
  - `pub fn HvfVcpu::save_system_registers(&self) ->
    Result<AArch64SystemRegs, Error>` covering `SCTLR_EL1`, `TCR_EL1`,
    `TTBR0_EL1`, `TTBR1_EL1`, `MAIR_EL1`, `VBAR_EL1`, `SPSR_EL1`,
    `ELR_EL1`, `ESR_EL1`, `FAR_EL1`, `MDSCR_EL1`, `CONTEXTIDR_EL1`,
    `CPACR_EL1`, `AFSR0_EL1`, `AFSR1_EL1`, `AMAIR_EL1`, `TPIDR_EL0`,
    `TPIDR_EL1`, `TPIDRRO_EL0`.
  - Virtual timer state: `CNTV_CTL_EL0`, `CNTV_CVAL_EL0`,
    `CNTVOFF_EL2`, with a documented restore policy that rebases the
    virtual timer to wall-clock-at-restore (per `snapshot_restore.md`
    §"Entropy, Identity, And Time").

#### C.3 — GICv3 state capture

- `src/hvf/src/lib.rs` (or new `src/hvf/src/gic.rs`):
  - `pub fn HvfVm::save_gic_state(&self) -> Result<Gicv3State, Error>`:
    distributor (`GICD_*`), redistributor per vCPU (`GICR_*`), per-SPI
    `IPRIORITYR`, `IROUTER`, `ICFGR`, pending+active bits, enable
    bits.
  - Matching `restore_gic_state`.
  - For the first version: require a constrained snapshot point where
    no SPI is pending. Validate at capture time; return
    `BackendCapabilityMismatch` if violated.

#### C.4 — HVF Snapshotable impls + memory walk on macOS

- New `src/vmm/src/macos/vstate.rs` (parallel to the Linux file):
  - `impl SnapshotableVm for Vmm` (or the macOS-side VM wrapper) that
    composes pause + GIC capture + per-vCPU state from C.1/C.2/C.3.
  - `impl SnapshotableVcpu for HvfVcpu`.

- `src/vmm/src/builder.rs` already has the memory walk from Phase B;
  on macOS it walks the same `GuestMemoryMmap` regions. The macOS
  reclaim work (`MADV_FREE_REUSABLE` notes from the wrapper repo's
  memory) does not interfere with capture — capture reads pages
  before any unmap.

#### C.5 — Restore path on macOS

- `src/hvf/src/lib.rs`:
  - `pub fn HvfVcpu::restore_general_registers(...)`,
    `restore_system_registers(...)`.
- `src/vmm/src/macos/vstate.rs`:
  - Restore order: memory image mmap'd into guest regions → device
    state → GIC state → vCPU registers → resume.

**Exit criteria:** on macOS/HVF, the equivalent of Phase B's KVM
smoke test passes. Restore wall-clock < 200ms for a 2048 MiB VM with a
256 MiB working set (sparse image + mmap'd restore, per the wrapper
repo's gap plan Phase 3 exit criteria).

**Effort:** 4–6 weeks. C.3 (GICv3) is the largest sub-phase; HVF's
API for GIC state is intentionally limited and requires careful
ordering. Each sub-phase is mergeable on its own behind a feature
flag.

### Phase D — Public C API + os_mode integration [consumer-facing]

Goal: external consumers (the wrapper, crun, krunkit, anything else
linking libkrun) can call snapshot/restore over the C ABI.

- `include/libkrun.h`:
  ```c
  /// Snapshot a paused VM context to a directory. The VM must have been
  /// paused by the caller (e.g. via a cooperative quiesce protocol); this
  /// call does not signal the guest. Returns 0 on success or a negative
  /// errno on failure. On failure no partial artifact is left behind.
  int32_t krun_snapshot(uint32_t ctx_id, const char *path);

  /// Restore a VM context from a snapshot directory. The context must be
  /// freshly created (no kernel/disk attached); restore wires up memory,
  /// device state, vCPUs, and IRQ controller state from the snapshot. The
  /// caller is responsible for providing a fresh root disk (per the design
  /// doc's restore contract). Returns 0 or negative errno.
  int32_t krun_restore(uint32_t ctx_id, const char *path);
  ```
- `src/libkrun/src/lib.rs`: bridge the C API to the Rust Snapshotable
  traits. Map `SnapshotError` variants to negative errno codes.

- `examples/os_mode.c`:
  - `--snapshot-out PATH` flag taking a directory. After boot, on
    receiving a `snapshot` command on the existing control socket
    (per the wrapper's quiesce protocol path), os_mode pauses vCPUs,
    calls `krun_snapshot(ctx, path)`, resumes.
  - `--restore PATH` flag, mutually exclusive with `--kernel`,
    `--initramfs`, `--root`. When set, os_mode creates a fresh ctx
    and calls `krun_restore(ctx, path)` before starting vCPUs.

**Exit criteria:** the sibling wrapper repo's
`SandboxManager::snapshot` with `capture_memory: true` round-trips
end-to-end on macOS, verified by the wrapper-side memory-marker test.

**Effort:** ~1 week after Phases A–C.

### Phase E — Memory deduplication [deferred per `snapshot_restore.md`]

Per the audit doc §"Memory Deduplication", deferred until Phase 3 is
in production. The format chosen in Phase A (`MemoryImage` page-
aligned with sparse holes) does not preclude promoting to a
content-addressed chunk store under `<cache>/snapshot-chunks/` with
shared read-only mappings + `MAP_PRIVATE` overlays.

## Sequencing

If one engineer works this end-to-end:

1. Phase A (foundations) — 3–5 days
2. Phase B (KVM x86_64) — 2 weeks
3. Phase C (HVF aarch64) — 4–6 weeks
4. Phase D (C API + os_mode) — 1 week
5. Phase E (dedup) — deferred

**Critical path** is Phases A → C → D. Phase B is parallelizable with C
once A is in. Phase E waits on production usage feedback.

If two engineers work in parallel after Phase A, engineer 1 takes
B+D (KVM + API), engineer 2 takes C (HVF). Merge at end of C.

## Boundaries (re-stating `snapshot_restore.md`)

- **Same host/backend family only** for the first production release.
  No cross-backend (KVM ↔ HVF) restore.
- **Same libkrun version, CPU feature profile, kernel, disk base.**
  Manifest version is checked on restore; mismatch returns
  `BackendCapabilityMismatch`.
- **Cooperative quiesce is the caller's responsibility.** The wrapper
  repo already implements the protocol (sync; freeze in a follow-on);
  libkrun assumes the VM is paused when `krun_snapshot` is called.
- **Restore generates fresh MAC and reseeds entropy** unless the
  caller explicitly preserves them. Wrapper repo defaults match.

## What does NOT change in this plan

- The existing `os_mode` boot flow is unaffected when neither
  `--snapshot-out` nor `--restore` is passed.
- The existing private KVM `save_state`/`restore_state` in
  `src/vmm/src/linux/vstate.rs:834` stay — Phase B promotes them via
  trait impl rather than rewriting.
- The HVF-side memory reclaim work (`hv_vm_unmap` + on-fault remap)
  noted in the wrapper repo's density doc is independent. Snapshot
  reads before reclaim unmaps; the two paths don't conflict.
