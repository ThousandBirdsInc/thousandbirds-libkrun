// Copyright 2026 The thousandbirds-libkrun authors.
// SPDX-License-Identifier: Apache-2.0

//! Backend-agnostic VM / vCPU state types and traits for snapshot+restore.
//!
//! The state types are versioned (V1) and backend-tagged (KVM/HVF, x86_64/
//! aarch64). Phase A defines the surface; backend implementations live in
//! `src/vmm/src/linux/vstate.rs` (KVM) and `src/vmm/src/macos/vstate.rs` (HVF)
//! as `impl SnapshotableVm for Vm` and `impl SnapshotableVcpu for Vcpu`.
//!
//! Serialization is a deliberately small hand-rolled binary format. We avoid
//! pulling `serde` here because libkrun's existing serde dependency is
//! optional (TEE-only); making snapshot depend on it would force every libkrun
//! consumer to pay the cost.

use super::error::SnapshotError;
use std::io::{Read, Write};

/// Current on-disk format version. Bump whenever the bytes that
/// [`VmStateV1::write_to`] / [`VcpuStateV1::write_to`] emit change in a
/// non-backward-compatible way. Restores check this against the file header
/// and fail with [`SnapshotError::VersionMismatch`] on mismatch.
pub const SNAPSHOT_FORMAT_VERSION: u32 = 1;

/// Conventional file names inside a snapshot directory. The wrapper layer's
/// manifest references these so the on-disk shape is stable across
/// wrappers.
pub const VM_STATE_FILE: &str = "snapshot.bin";
pub const VCPU_STATE_FILE_PREFIX: &str = "vcpu_";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackendKind {
    Kvm,
    Hvf,
}

impl BackendKind {
    fn as_u8(self) -> u8 {
        match self {
            Self::Kvm => 1,
            Self::Hvf => 2,
        }
    }
    fn from_u8(v: u8) -> Result<Self, SnapshotError> {
        match v {
            1 => Ok(Self::Kvm),
            2 => Ok(Self::Hvf),
            other => Err(SnapshotError::Parse(format!(
                "unknown backend tag {other}"
            ))),
        }
    }
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Kvm => "kvm",
            Self::Hvf => "hvf",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArchKind {
    X86_64,
    Aarch64,
}

impl ArchKind {
    fn as_u8(self) -> u8 {
        match self {
            Self::X86_64 => 1,
            Self::Aarch64 => 2,
        }
    }
    fn from_u8(v: u8) -> Result<Self, SnapshotError> {
        match v {
            1 => Ok(Self::X86_64),
            2 => Ok(Self::Aarch64),
            other => Err(SnapshotError::Parse(format!("unknown arch tag {other}"))),
        }
    }
    pub fn as_str(self) -> &'static str {
        match self {
            Self::X86_64 => "x86_64",
            Self::Aarch64 => "aarch64",
        }
    }
}

/// Versioned, backend-tagged container for VM-level state (interrupt
/// controllers, timers, anything that lives at the VM scope rather than per-
/// vCPU).
///
/// The `payload` is an opaque byte vector encoded by the backend. The header
/// (magic + version + backend + arch) is fixed across backends so a
/// `from_reader` call can dispatch to the right decoder.
#[derive(Debug, Clone)]
pub struct VmStateV1 {
    pub backend: BackendKind,
    pub arch: ArchKind,
    pub payload: Vec<u8>,
}

const VM_MAGIC: &[u8; 8] = b"KRUNVMs1";

impl VmStateV1 {
    pub fn new(backend: BackendKind, arch: ArchKind, payload: Vec<u8>) -> Self {
        Self {
            backend,
            arch,
            payload,
        }
    }

    pub fn write_to(&self, mut writer: impl Write) -> Result<(), SnapshotError> {
        writer.write_all(VM_MAGIC)?;
        writer.write_all(&SNAPSHOT_FORMAT_VERSION.to_le_bytes())?;
        writer.write_all(&[self.backend.as_u8(), self.arch.as_u8()])?;
        writer.write_all(&(self.payload.len() as u64).to_le_bytes())?;
        writer.write_all(&self.payload)?;
        Ok(())
    }

    pub fn read_from(mut reader: impl Read) -> Result<Self, SnapshotError> {
        let mut magic = [0u8; 8];
        reader.read_exact(&mut magic)?;
        if &magic != VM_MAGIC {
            return Err(SnapshotError::Parse("bad VmStateV1 magic".to_string()));
        }
        let mut version = [0u8; 4];
        reader.read_exact(&mut version)?;
        let version = u32::from_le_bytes(version);
        if version != SNAPSHOT_FORMAT_VERSION {
            return Err(SnapshotError::VersionMismatch {
                expected: SNAPSHOT_FORMAT_VERSION,
                found: version,
            });
        }
        let mut tags = [0u8; 2];
        reader.read_exact(&mut tags)?;
        let backend = BackendKind::from_u8(tags[0])?;
        let arch = ArchKind::from_u8(tags[1])?;
        let mut len = [0u8; 8];
        reader.read_exact(&mut len)?;
        let len = u64::from_le_bytes(len);
        let mut payload = vec![0u8; len as usize];
        reader.read_exact(&mut payload)?;
        Ok(Self {
            backend,
            arch,
            payload,
        })
    }

    pub fn backend_str(&self) -> &'static str {
        self.backend.as_str()
    }
    pub fn arch_str(&self) -> &'static str {
        self.arch.as_str()
    }
}

/// Same shape as [`VmStateV1`] but for per-vCPU state (general + system
/// registers, FP/SIMD, vCPU events on KVM, etc).
#[derive(Debug, Clone)]
pub struct VcpuStateV1 {
    pub backend: BackendKind,
    pub arch: ArchKind,
    pub cpu_index: u32,
    pub payload: Vec<u8>,
}

const VCPU_MAGIC: &[u8; 8] = b"KRUNVCs1";

impl VcpuStateV1 {
    pub fn new(backend: BackendKind, arch: ArchKind, cpu_index: u32, payload: Vec<u8>) -> Self {
        Self {
            backend,
            arch,
            cpu_index,
            payload,
        }
    }

    pub fn write_to(&self, mut writer: impl Write) -> Result<(), SnapshotError> {
        writer.write_all(VCPU_MAGIC)?;
        writer.write_all(&SNAPSHOT_FORMAT_VERSION.to_le_bytes())?;
        writer.write_all(&[self.backend.as_u8(), self.arch.as_u8()])?;
        writer.write_all(&self.cpu_index.to_le_bytes())?;
        writer.write_all(&(self.payload.len() as u64).to_le_bytes())?;
        writer.write_all(&self.payload)?;
        Ok(())
    }

    pub fn read_from(mut reader: impl Read) -> Result<Self, SnapshotError> {
        let mut magic = [0u8; 8];
        reader.read_exact(&mut magic)?;
        if &magic != VCPU_MAGIC {
            return Err(SnapshotError::Parse("bad VcpuStateV1 magic".to_string()));
        }
        let mut version = [0u8; 4];
        reader.read_exact(&mut version)?;
        let version = u32::from_le_bytes(version);
        if version != SNAPSHOT_FORMAT_VERSION {
            return Err(SnapshotError::VersionMismatch {
                expected: SNAPSHOT_FORMAT_VERSION,
                found: version,
            });
        }
        let mut tags = [0u8; 2];
        reader.read_exact(&mut tags)?;
        let backend = BackendKind::from_u8(tags[0])?;
        let arch = ArchKind::from_u8(tags[1])?;
        let mut cpu_index = [0u8; 4];
        reader.read_exact(&mut cpu_index)?;
        let cpu_index = u32::from_le_bytes(cpu_index);
        let mut len = [0u8; 8];
        reader.read_exact(&mut len)?;
        let len = u64::from_le_bytes(len);
        let mut payload = vec![0u8; len as usize];
        reader.read_exact(&mut payload)?;
        Ok(Self {
            backend,
            arch,
            cpu_index,
            payload,
        })
    }
}

/// VM-scope snapshot/restore. Implemented by `linux::vstate::Vm` (KVM) and
/// `macos::vstate::Vm` (HVF).
pub trait SnapshotableVm {
    /// Capture VM-scope state. Caller must have paused all vCPUs first.
    fn save_vm_state(&self) -> Result<VmStateV1, SnapshotError>;
    /// Restore VM-scope state. Caller must have freshly created the VM and
    /// not started vCPUs.
    fn restore_vm_state(&self, state: &VmStateV1) -> Result<(), SnapshotError>;
}

/// Per-vCPU snapshot/restore. Implemented by `linux::vstate::Vcpu` (KVM) and
/// `macos::vstate::Vcpu` (HVF).
pub trait SnapshotableVcpu {
    /// Capture vCPU state. Caller must have paused the vCPU first
    /// (`hv_vcpus_exit` + ack on HVF; vCPU thread paused on KVM).
    fn save_vcpu_state(&self) -> Result<VcpuStateV1, SnapshotError>;
    /// Restore vCPU state into a freshly created vCPU that has not yet run.
    fn restore_vcpu_state(&self, state: &VcpuStateV1) -> Result<(), SnapshotError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vm_state_round_trip() {
        let original = VmStateV1::new(BackendKind::Kvm, ArchKind::X86_64, vec![1, 2, 3, 4, 5]);
        let mut buf = Vec::new();
        original.write_to(&mut buf).unwrap();
        let parsed = VmStateV1::read_from(&buf[..]).unwrap();
        assert_eq!(parsed.backend, BackendKind::Kvm);
        assert_eq!(parsed.arch, ArchKind::X86_64);
        assert_eq!(parsed.payload, original.payload);
    }

    #[test]
    fn vcpu_state_round_trip_preserves_cpu_index() {
        let original = VcpuStateV1::new(BackendKind::Hvf, ArchKind::Aarch64, 7, vec![9, 8, 7]);
        let mut buf = Vec::new();
        original.write_to(&mut buf).unwrap();
        let parsed = VcpuStateV1::read_from(&buf[..]).unwrap();
        assert_eq!(parsed.backend, BackendKind::Hvf);
        assert_eq!(parsed.arch, ArchKind::Aarch64);
        assert_eq!(parsed.cpu_index, 7);
        assert_eq!(parsed.payload, vec![9, 8, 7]);
    }

    #[test]
    fn version_mismatch_fails_loudly() {
        let mut buf = Vec::new();
        buf.extend_from_slice(VM_MAGIC);
        buf.extend_from_slice(&999u32.to_le_bytes());
        buf.extend_from_slice(&[1, 1]);
        buf.extend_from_slice(&0u64.to_le_bytes());
        let err = VmStateV1::read_from(&buf[..]).unwrap_err();
        assert!(matches!(err, SnapshotError::VersionMismatch { .. }));
    }

    #[test]
    fn bad_magic_fails() {
        let buf = b"GARBAGE!";
        let err = VmStateV1::read_from(&buf[..]).unwrap_err();
        assert!(matches!(err, SnapshotError::Parse(_)));
    }
}
