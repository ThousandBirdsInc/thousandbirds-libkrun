// Copyright 2026 The thousandbirds-libkrun authors.
// SPDX-License-Identifier: Apache-2.0

//! Snapshot / restore for libkrun-managed VMs.
//!
//! This is the **Phase A foundations + Phase B/C/D scaffolding** layer of the
//! plan in `design_docs/snapshot_restore_implementation.md`. See that doc for
//! the full audit, phasing, and exit criteria.
//!
//! ## What this module provides
//!
//! - [`SnapshotableVm`] / [`SnapshotableVcpu`] traits — backend-agnostic
//!   surface for capturing and restoring VM and vCPU state.
//! - [`VmStateV1`] / [`VcpuStateV1`] — versioned, backend-tagged state
//!   containers. The `V1` suffix is deliberate; future format changes get a
//!   `V2` variant without breaking `V1` consumers.
//! - [`MemoryImage`] — on-disk format for captured guest memory.
//!   Page-aligned. Sparse where supported (skips zero pages on capture, maps
//!   on demand at restore via mmap so pages fault in lazily).
//! - [`SnapshotError`] — typed errors for the whole module.
//!
//! ## On-disk layout
//!
//! `krun_snapshot(ctx, path)` writes the following files under `path`:
//!
//! ```text
//!   snapshot.bin     — VmStateV1 (binary; see state.rs for encoding)
//!   vcpu_NNN.bin     — VcpuStateV1, one per vCPU
//!   memory.bin       — guest physical memory, page-aligned, sparse
//! ```
//!
//! The wrapper layer (`thousandbirds-agent-sandbox`) owns the higher-level
//! `manifest.json` that references these files plus a disk clone, credentials,
//! and the original sandbox config.
//!
//! ## Backend support matrix (this build)
//!
//! | Backend        | VM state                       | vCPU state                  | Memory | Notes |
//! |----------------|--------------------------------|-----------------------------|--------|-------|
//! | KVM x86_64     | PIC, IOAPIC, PIT, clock        | full (CPUID, MSRs, XSAVE…)  | yes    | Wraps the existing private save_state in `linux/vstate.rs`. |
//! | HVF aarch64    | none captured                  | general + system registers  | yes    | GICv3 capture is a follow-on; snapshot site validates "no pending interrupts" as a precondition. |
//! | KVM aarch64    | not implemented                | not implemented             | n/a    | Out of scope for first release. |
//! | HVF x86_64     | not implemented                | not implemented             | n/a    | libkrun's HVF backend is aarch64 only. |
//!
//! ## What is NOT in this module
//!
//! - Cooperative guest quiesce — that is the wrapper's responsibility. By
//!   the time `krun_snapshot` is called the guest should be paused and
//!   filesystems flushed.
//! - The umbrella JSON manifest that names this snapshot and references the
//!   disk clone / credentials staging — that lives in the wrapper.
//! - Cross-backend or cross-host restore — explicitly out of scope per
//!   `design_docs/snapshot_restore.md` §"Restore Contract".

pub mod error;
pub mod memory;
pub mod state;

pub use error::SnapshotError;
pub use memory::{
    MemoryImageReader, MemoryImageWriter, MemoryRegionDescriptor, MemoryRegionMeta,
    MEMORY_IMAGE_FILE,
};
pub use state::{
    ArchKind, BackendKind, SnapshotableVcpu, SnapshotableVm, VcpuStateV1, VmStateV1,
    SNAPSHOT_FORMAT_VERSION, VCPU_STATE_FILE_PREFIX, VM_STATE_FILE,
};
