# Snapshot/Restore Follow-Up Design

This document tracks the snapshot/restore work that follows full Linux OS mode.
It is intentionally separate from the initial OS-mode patch series. OS mode must
continue to boot, validate, and measure without depending on memory
snapshot/restore.

## Scope

The first snapshot milestone should target fast startup of prepared OS-mode
guests on macOS/ARM64 HVF, while keeping the design compatible with a later
Linux/KVM implementation. The feature should snapshot a paused VM at a known
guest readiness point, restore it with fresh disk and network identity, and make
the restored guest observe sane time, entropy, and storage semantics.

APFS root disk clones are part of disk provisioning. They are not a replacement
for memory snapshot/restore. On macOS, a restore should create or select the
per-VM APFS disk clone before guest memory and device state become visible to
the restored VM.

## Current State Audit

### Configuration State

`VmResources` in `src/vmm/src/resources.rs` contains the build-time VM
configuration: VM size, kernel payload, kernel command line, block, network,
console, display, input, SMBIOS, nested virtualization, and boot-mode related
settings. This is mostly serializable configuration, but it is not the running
machine state. It can seed a restore but cannot prove that a resumed guest is at
the same execution point.

### Guest Memory

The VMM builds `GuestMemoryMmap` regions in `src/vmm/src/builder.rs`. There is
no repository-level abstraction today for freezing those regions, writing dirty
page deltas, or restoring pages into an already-created VM. Snapshot work needs
a memory image format and an explicit dirty-tracking strategy before it can
claim fast restore at scale.

For macOS, the realistic first version is a private memory image per snapshot
plus APFS-backed disk clones per restore. For dense restores, a later milestone
can consider shared immutable memory files plus copy-on-write private mappings
if the HVF mapping path can support the required permissions and lifecycle.

### Device State

The virtio trait in `src/devices/src/virtio/device.rs` supports feature
negotiation, config reads and writes, activation, reset, and optional shared
memory regions. It does not expose `save_state()` or `restore_state()`. The
virtio-mmio transport and every participating device must gain explicit state
objects before a restored VM can resume reliably.

The minimum OS-mode snapshot device set is:

- virtio-mmio transport state: selected features, driver status, config
  generation, interrupt status, queue PFNs or descriptor addresses, queue size,
  ready bits, and notification state.
- virtio-blk: negotiated features, request queue state, backing file identity,
  in-flight request policy, flush/writeback state, and a guarantee that no
  partially handled request is snapshotted.
- serial console: register state, pending input/output buffers, interrupt
  state, and host-side file descriptor policy. The first version may require a
  quiescent console with no pending input.
- virtio-net, when enabled: MAC address, feature state, queue state, backend
  socket identity, DHCP state expectations, and a mandatory post-restore network
  identity refresh.
- legacy interrupt controller state: GIC/IOAPIC/PIC state, pending interrupts,
  timer state, and IRQ routing.

Devices that cannot provide deterministic state must be disabled for snapshot
guests until their state model exists.

### Linux/KVM Backend

The Linux KVM backend already has partial x86_64 save and restore helpers:
`Vm::save_state()` captures PIT, clock, PIC, IOAPIC, and IRQ routing, and
`Vcpu::save_state()` / `Vcpu::restore_state()` cover CPUID, MSRs, debug regs,
LAPIC, MP state, general registers, special registers, vCPU events, XCRs, and
XSAVE state. vCPU threads also have pause and resume events.

This is useful scaffolding, not a complete snapshot implementation. It is
x86_64-specific, not wired into a public libkrun API, not paired with guest
memory or device serialization, and not validated by the OS-mode runtime gates.
Linux/KVM runtime validation remains deferred until a Linux host or CI runner
with `/dev/kvm` is available.

### macOS/HVF Backend

The HVF wrapper in `src/hvf/src/lib.rs` can create VMs, map and unmap memory,
create vCPUs, set initial registers, read/write general registers internally,
read system registers internally, run vCPUs, request vCPU exit, set pending
interrupts, and mask the virtual timer. It does not currently expose a complete
public vCPU state object or VM/GIC/timer state object suitable for
snapshot/restore.

The first HVF snapshot milestone needs:

- A pause point that exits all vCPUs and proves no vCPU is concurrently
  mutating guest memory or device state.
- Public backend methods to collect and restore all general registers required
  by the aarch64 execution state.
- Public backend methods to collect and restore the required system registers,
  including timer and exception state.
- GICv3 state capture and restore, or a constrained snapshot point where no
  pending interrupts can exist.
- A timer model that can rebase virtual time on restore.

HVF should be treated as the first runtime target because macOS support is a
hard requirement for this feature set.

## Restore Contract

Snapshots should be host-backend-specific for the first production milestone.
Do not promise cross-host or cross-backend restore until both KVM and HVF have
complete, tested state coverage. A snapshot created on macOS/HVF may be restored
on the same host/backend family with a compatible libkrun version, CPU feature
profile, guest kernel, device set, and disk base image.

The snapshot manifest should record:

- libkrun version and snapshot format version.
- Host backend and architecture.
- Guest CPU count, memory size, and CPU feature profile.
- Kernel, initramfs, root disk base image checksum, and APFS clone source.
- Device list and per-device state format versions.
- Guest quiescence marker and timestamp.
- Network identity policy and whether a new MAC is required on restore.
- Entropy reseed policy.

## Quiescence

The first reliable snapshot point should be cooperative. The guest should emit a
readiness marker, stop workload entry, flush filesystems, bring application
state to a known point, and optionally freeze userspace before the host captures
state. Host-only pause without guest cooperation can be a later milestone.

Before writing a snapshot:

- Stop accepting new host requests for block and network devices.
- Drain or fail in-flight virtio requests.
- Flush block devices and require the root disk clone to be consistent.
- Pause every vCPU and verify all pause acknowledgements.
- Snapshot device state only after vCPUs are paused.
- Snapshot memory only after device state cannot mutate guest memory.

## Entropy, Identity, And Time

Every restore must avoid cloning guest identity accidentally.

- Entropy: require a guest agent, virtio-rng reseed, or documented init hook
  that reseeds the kernel RNG and application secrets after restore.
- MAC address: generate a fresh MAC by default and expose an explicit opt-in for
  preserving the old MAC. DHCP leases and hostname-derived identity must be
  refreshed after restore.
- Timekeeping: record host monotonic and wall-clock time at snapshot and
  restore, then rebase virtual timer state so the guest does not observe a long
  stall as normal CPU execution. For the first version, document that NTP or
  guest time sync must run after restore.

## Disk Copy-On-Write

For macOS/HVF, the restore sequence should be:

1. Verify the immutable base root image checksum.
2. Create a fresh APFS clone for the restored VM.
3. Attach the clone path to virtio-blk.
4. Restore memory, vCPU, interrupt-controller, transport, and device state.
5. Resume vCPUs only after the clone-backed block device is ready.

For Linux/KVM, the equivalent can use raw file reflinks where supported or a
documented full-copy fallback. The Linux host path is deferred until a real
Linux host or CI runner is available.

## Memory Deduplication

The first version should prefer correctness over density: a restored VM gets
private guest memory. The next milestone can deduplicate immutable pages by
using content-addressed memory chunks or shared read-only mappings plus
copy-on-write private pages. On Linux, KSM and userfaultfd are possible tools.
On macOS, the design needs validation against HVF memory mapping semantics and
APFS-backed memory image behavior before promising deduplication.

## Initial Patch Boundary

Snapshot/restore must stay out of the initial OS-mode patch series. The OS-mode
series should end with:

- Public OS-mode APIs.
- Command-line and console handling.
- Block-root boot on macOS/HVF.
- APFS clone provisioning and validation.
- Docker/Linux compile validation.
- Deferred Linux/KVM runtime gates clearly documented.

The snapshot series should start only after the OS-mode validation log contains
macOS/HVF boot and APFS clone evidence, which it now does.
