// Copyright 2026 The thousandbirds-libkrun authors.
// SPDX-License-Identifier: Apache-2.0

//! Errors for the snapshot module.

use std::fmt;
use std::io;

#[derive(Debug)]
pub enum SnapshotError {
    /// The current backend has no implementation for the requested
    /// operation. Today: KVM aarch64, HVF x86_64.
    UnsupportedBackend(&'static str),
    /// A vCPU was running when capture started. Caller must pause first.
    VcpuNotPaused,
    /// The host CPU or backend reports state the snapshot format cannot
    /// represent at its current version.
    BackendCapabilityMismatch(String),
    /// Loaded state does not match this libkrun build's snapshot format.
    VersionMismatch {
        expected: u32,
        found: u32,
    },
    /// The backend or arch tag in a state file does not match the running
    /// VM (e.g. tried to restore an x86_64 snapshot on an aarch64 host).
    BackendMismatch {
        expected: &'static str,
        found: String,
    },
    /// The guest had pending interrupts at snapshot time and this build
    /// cannot represent them. See `design_docs/snapshot_restore_implementation.md`
    /// §Phase C.3.
    PendingInterruptsUnsupported,
    /// Memory region walk failed (size mismatch, mmap error, etc).
    MemoryWalkFailed(String),
    /// I/O error reading or writing snapshot files.
    Io(io::Error),
    /// Backend-specific capture error wrapped in a string.
    BackendError(String),
    /// Parsing error in a state file. Carries a short description.
    Parse(String),
}

impl fmt::Display for SnapshotError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnsupportedBackend(what) => {
                write!(f, "snapshot: {what} is not implemented for this backend")
            }
            Self::VcpuNotPaused => {
                write!(f, "snapshot: vCPUs must be paused before capture")
            }
            Self::BackendCapabilityMismatch(msg) => {
                write!(f, "snapshot: backend capability mismatch: {msg}")
            }
            Self::VersionMismatch { expected, found } => {
                write!(
                    f,
                    "snapshot: format version mismatch (expected {expected}, found {found})"
                )
            }
            Self::BackendMismatch { expected, found } => {
                write!(
                    f,
                    "snapshot: backend mismatch (expected {expected}, found {found})"
                )
            }
            Self::PendingInterruptsUnsupported => write!(
                f,
                "snapshot: pending interrupts detected at snapshot time; \
                 this build requires a quiescent interrupt state \
                 (GICv3 state capture is a Phase C.3 follow-on)"
            ),
            Self::MemoryWalkFailed(msg) => write!(f, "snapshot: memory walk failed: {msg}"),
            Self::Io(err) => write!(f, "snapshot: {err}"),
            Self::BackendError(msg) => write!(f, "snapshot: backend error: {msg}"),
            Self::Parse(msg) => write!(f, "snapshot: parse error: {msg}"),
        }
    }
}

impl std::error::Error for SnapshotError {}

impl From<io::Error> for SnapshotError {
    fn from(err: io::Error) -> Self {
        Self::Io(err)
    }
}
