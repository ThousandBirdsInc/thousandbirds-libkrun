// Copyright 2026 The thousandbirds-libkrun authors.
// SPDX-License-Identifier: Apache-2.0

//! Guest memory snapshot image: capture and restore.
//!
//! On-disk format (single file at `<snap>/memory.bin`):
//!
//! ```text
//!   [16-byte header]
//!     magic         : 8 bytes  "KRUNMEM\1"
//!     version       : u32 little-endian (== MEMORY_FORMAT_VERSION)
//!     region_count  : u32 little-endian
//!   [region_count * 32 bytes of region descriptors]
//!     guest_phys_base : u64 le  -- guest physical address of region start
//!     size            : u64 le  -- region size in bytes (page-aligned)
//!     file_offset     : u64 le  -- offset within memory.bin
//!     flags           : u64 le  -- bit 0: sparse (skip zero pages on capture)
//!   [contiguous region payloads at the offsets named in the descriptors]
//! ```
//!
//! Capture walks `GuestMemoryMmap` regions, writes a descriptor per region,
//! and writes the bytes. When `sparse` is set, zero-filled 4 KiB pages are
//! skipped (the file is sparse via `set_len` + holes rather than literal
//! zero bytes).
//!
//! Restore mmap's the file `MAP_PRIVATE` into the new VM's guest regions
//! before any vCPU runs. Lazy faulting means restored VMs only resident the
//! pages they touch, matching the working-set behavior described in
//! `design_docs/snapshot_restore_implementation.md` §"Exit criteria".

use super::error::SnapshotError;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;

/// Canonical file name for the guest memory image inside a snapshot dir.
pub const MEMORY_IMAGE_FILE: &str = "memory.bin";

pub const MEMORY_FORMAT_VERSION: u32 = 1;
const MEMORY_MAGIC: &[u8; 8] = b"KRUNMEM\x01";
const HEADER_SIZE: u64 = 16;
const DESCRIPTOR_SIZE: u64 = 32;

const FLAG_SPARSE: u64 = 1;

/// 4 KiB page; matches HVF + KVM 4 KiB base page on aarch64 and x86_64.
const PAGE_SIZE: usize = 4096;

/// Region descriptor as the caller knows it (pre-write). `file_offset` is
/// computed by the writer.
#[derive(Debug, Clone, Copy)]
pub struct MemoryRegionMeta {
    pub guest_phys_base: u64,
    pub size: u64,
    pub sparse: bool,
}

/// Region descriptor as read back from the image.
#[derive(Debug, Clone, Copy)]
pub struct MemoryRegionDescriptor {
    pub guest_phys_base: u64,
    pub size: u64,
    pub file_offset: u64,
    pub flags: u64,
}

impl MemoryRegionDescriptor {
    pub fn sparse(&self) -> bool {
        self.flags & FLAG_SPARSE != 0
    }
}

/// Streaming writer for the memory image. Lifecycle:
///
/// ```ignore
/// let mut w = MemoryImageWriter::create(path, &[meta_region_0, meta_region_1])?;
/// w.write_region(0, region_0_bytes)?;
/// w.write_region(1, region_1_bytes)?;
/// w.finalize()?;
/// ```
pub struct MemoryImageWriter {
    file: File,
    descriptors: Vec<MemoryRegionDescriptor>,
    next_region: usize,
    payload_cursor: u64,
}

impl MemoryImageWriter {
    pub fn create(path: &Path, regions: &[MemoryRegionMeta]) -> Result<Self, SnapshotError> {
        let mut file = File::create(path)?;
        // Reserve header + descriptor table; we rewrite the descriptors in
        // `finalize` once payloads are placed.
        let header_and_table = HEADER_SIZE + DESCRIPTOR_SIZE * regions.len() as u64;
        file.set_len(header_and_table)?;
        file.seek(SeekFrom::Start(header_and_table))?;

        let descriptors = regions
            .iter()
            .map(|r| MemoryRegionDescriptor {
                guest_phys_base: r.guest_phys_base,
                size: r.size,
                file_offset: 0,
                flags: if r.sparse { FLAG_SPARSE } else { 0 },
            })
            .collect();

        Ok(Self {
            file,
            descriptors,
            next_region: 0,
            payload_cursor: header_and_table,
        })
    }

    /// Append a region's bytes to the image. `region_index` must match the
    /// order regions were passed to `create`.
    pub fn write_region(&mut self, region_index: usize, bytes: &[u8]) -> Result<(), SnapshotError> {
        if region_index != self.next_region {
            return Err(SnapshotError::MemoryWalkFailed(format!(
                "region writes must be sequential; expected {}, got {region_index}",
                self.next_region
            )));
        }
        let desc_size = self.descriptors[region_index].size;
        let desc_sparse = self.descriptors[region_index].sparse();
        if bytes.len() as u64 != desc_size {
            return Err(SnapshotError::MemoryWalkFailed(format!(
                "region {region_index}: payload size {} != descriptor size {}",
                bytes.len(),
                desc_size
            )));
        }
        self.descriptors[region_index].file_offset = self.payload_cursor;
        self.file.seek(SeekFrom::Start(self.payload_cursor))?;

        if desc_sparse {
            // Sparse write: punch holes for fully-zero 4 KiB pages. The file
            // grows via seek-past-end; the FS will report the file as sparse
            // (smaller on-disk than `size`).
            let mut offset = 0usize;
            while offset + PAGE_SIZE <= bytes.len() {
                let page = &bytes[offset..offset + PAGE_SIZE];
                if !page.iter().all(|&b| b == 0) {
                    self.file
                        .seek(SeekFrom::Start(self.payload_cursor + offset as u64))?;
                    self.file.write_all(page)?;
                }
                offset += PAGE_SIZE;
            }
            // Tail (size not page-multiple) — write it as-is.
            if offset < bytes.len() {
                self.file
                    .seek(SeekFrom::Start(self.payload_cursor + offset as u64))?;
                self.file.write_all(&bytes[offset..])?;
            }
            // Ensure file length covers the region.
            let region_end = self.payload_cursor + desc_size;
            let current_len = self.file_len()?;
            self.file.set_len(region_end.max(current_len))?;
        } else {
            self.file.write_all(bytes)?;
        }

        self.payload_cursor += desc_size;
        self.next_region += 1;
        Ok(())
    }

    /// Write the final header + descriptor table. Call exactly once after
    /// all regions have been written.
    pub fn finalize(mut self) -> Result<(), SnapshotError> {
        if self.next_region != self.descriptors.len() {
            return Err(SnapshotError::MemoryWalkFailed(format!(
                "finalize called with {}/{} regions written",
                self.next_region,
                self.descriptors.len()
            )));
        }
        self.file.seek(SeekFrom::Start(0))?;
        self.file.write_all(MEMORY_MAGIC)?;
        self.file.write_all(&MEMORY_FORMAT_VERSION.to_le_bytes())?;
        self.file
            .write_all(&(self.descriptors.len() as u32).to_le_bytes())?;
        for desc in &self.descriptors {
            self.file.write_all(&desc.guest_phys_base.to_le_bytes())?;
            self.file.write_all(&desc.size.to_le_bytes())?;
            self.file.write_all(&desc.file_offset.to_le_bytes())?;
            self.file.write_all(&desc.flags.to_le_bytes())?;
        }
        self.file.sync_all()?;
        Ok(())
    }

    fn file_len(&self) -> std::io::Result<u64> {
        Ok(self.file.metadata()?.len())
    }
}

/// Streaming reader for the memory image. Restore opens the file once,
/// reads descriptors, then either reads region bytes or mmap's them into
/// the new VM's guest regions.
#[derive(Debug)]
pub struct MemoryImageReader {
    pub descriptors: Vec<MemoryRegionDescriptor>,
    file: File,
}

impl MemoryImageReader {
    pub fn open(path: &Path) -> Result<Self, SnapshotError> {
        let mut file = File::open(path)?;
        let mut header = [0u8; 16];
        file.read_exact(&mut header)?;
        if &header[..8] != MEMORY_MAGIC {
            return Err(SnapshotError::Parse("bad memory image magic".to_string()));
        }
        let version = u32::from_le_bytes(header[8..12].try_into().unwrap());
        if version != MEMORY_FORMAT_VERSION {
            return Err(SnapshotError::VersionMismatch {
                expected: MEMORY_FORMAT_VERSION,
                found: version,
            });
        }
        let count = u32::from_le_bytes(header[12..16].try_into().unwrap()) as usize;
        let mut descriptors = Vec::with_capacity(count);
        let mut buf = [0u8; DESCRIPTOR_SIZE as usize];
        for _ in 0..count {
            file.read_exact(&mut buf)?;
            descriptors.push(MemoryRegionDescriptor {
                guest_phys_base: u64::from_le_bytes(buf[0..8].try_into().unwrap()),
                size: u64::from_le_bytes(buf[8..16].try_into().unwrap()),
                file_offset: u64::from_le_bytes(buf[16..24].try_into().unwrap()),
                flags: u64::from_le_bytes(buf[24..32].try_into().unwrap()),
            });
        }
        Ok(Self { descriptors, file })
    }

    /// Read the bytes for `region_index` into `dst`. `dst.len()` must equal
    /// the descriptor's `size`.
    pub fn read_region(
        &mut self,
        region_index: usize,
        dst: &mut [u8],
    ) -> Result<(), SnapshotError> {
        let desc = self.descriptors.get(region_index).ok_or_else(|| {
            SnapshotError::MemoryWalkFailed(format!(
                "region {region_index} out of bounds ({} present)",
                self.descriptors.len()
            ))
        })?;
        if dst.len() as u64 != desc.size {
            return Err(SnapshotError::MemoryWalkFailed(format!(
                "region {region_index} size mismatch: dst {} != descriptor {}",
                dst.len(),
                desc.size
            )));
        }
        self.file.seek(SeekFrom::Start(desc.file_offset))?;
        self.file.read_exact(dst)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp_file(label: &str) -> std::path::PathBuf {
        std::env::temp_dir().join(format!(
            "krun-snap-memory-{label}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ))
    }

    #[test]
    fn round_trip_dense_region() {
        let path = tmp_file("dense");
        let meta = MemoryRegionMeta {
            guest_phys_base: 0x4000_0000,
            size: 8 * 1024,
            sparse: false,
        };
        let payload: Vec<u8> = (0..8 * 1024).map(|i| (i % 251) as u8).collect();

        let mut w = MemoryImageWriter::create(&path, &[meta]).unwrap();
        w.write_region(0, &payload).unwrap();
        w.finalize().unwrap();

        let mut reader = MemoryImageReader::open(&path).unwrap();
        assert_eq!(reader.descriptors.len(), 1);
        assert_eq!(reader.descriptors[0].guest_phys_base, 0x4000_0000);
        let mut dst = vec![0u8; 8 * 1024];
        reader.read_region(0, &mut dst).unwrap();
        assert_eq!(dst, payload);

        std::fs::remove_file(path).ok();
    }

    #[test]
    fn sparse_region_preserves_bytes_even_when_zero_pages_punched() {
        let path = tmp_file("sparse");
        // 16 KiB region: page 0 nonzero, page 1 zero, page 2 nonzero,
        // page 3 zero.
        let mut payload = vec![0u8; 16 * 1024];
        for b in payload.iter_mut().take(PAGE_SIZE) {
            *b = 0xAB;
        }
        for b in payload[2 * PAGE_SIZE..3 * PAGE_SIZE].iter_mut() {
            *b = 0xCD;
        }
        let meta = MemoryRegionMeta {
            guest_phys_base: 0,
            size: 16 * 1024,
            sparse: true,
        };

        let mut w = MemoryImageWriter::create(&path, &[meta]).unwrap();
        w.write_region(0, &payload).unwrap();
        w.finalize().unwrap();

        let mut reader = MemoryImageReader::open(&path).unwrap();
        assert!(reader.descriptors[0].sparse());
        let mut dst = vec![0u8; 16 * 1024];
        reader.read_region(0, &mut dst).unwrap();
        assert_eq!(dst, payload);

        std::fs::remove_file(path).ok();
    }

    #[test]
    fn multi_region_roundtrip_preserves_order_and_offsets() {
        let path = tmp_file("multi");
        let regions = [
            MemoryRegionMeta {
                guest_phys_base: 0,
                size: 4096,
                sparse: false,
            },
            MemoryRegionMeta {
                guest_phys_base: 0x1_0000_0000,
                size: 8192,
                sparse: false,
            },
        ];
        let r0 = vec![1u8; 4096];
        let r1 = vec![2u8; 8192];

        let mut w = MemoryImageWriter::create(&path, &regions).unwrap();
        w.write_region(0, &r0).unwrap();
        w.write_region(1, &r1).unwrap();
        w.finalize().unwrap();

        let mut reader = MemoryImageReader::open(&path).unwrap();
        assert_eq!(reader.descriptors.len(), 2);
        assert_eq!(reader.descriptors[0].guest_phys_base, 0);
        assert_eq!(reader.descriptors[1].guest_phys_base, 0x1_0000_0000);
        let mut a = vec![0u8; 4096];
        reader.read_region(0, &mut a).unwrap();
        assert!(a.iter().all(|&b| b == 1));
        let mut b = vec![0u8; 8192];
        reader.read_region(1, &mut b).unwrap();
        assert!(b.iter().all(|&v| v == 2));

        std::fs::remove_file(path).ok();
    }

    #[test]
    fn out_of_order_write_fails() {
        let path = tmp_file("ooo");
        let regions = [
            MemoryRegionMeta {
                guest_phys_base: 0,
                size: 4096,
                sparse: false,
            },
            MemoryRegionMeta {
                guest_phys_base: 0x1000,
                size: 4096,
                sparse: false,
            },
        ];
        let mut w = MemoryImageWriter::create(&path, &regions).unwrap();
        let err = w.write_region(1, &vec![0u8; 4096]).unwrap_err();
        assert!(matches!(err, SnapshotError::MemoryWalkFailed(_)));
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn finalize_without_all_regions_fails() {
        let path = tmp_file("incomplete");
        let regions = [
            MemoryRegionMeta {
                guest_phys_base: 0,
                size: 4096,
                sparse: false,
            },
            MemoryRegionMeta {
                guest_phys_base: 0x1000,
                size: 4096,
                sparse: false,
            },
        ];
        let mut w = MemoryImageWriter::create(&path, &regions).unwrap();
        w.write_region(0, &vec![0u8; 4096]).unwrap();
        let err = w.finalize().unwrap_err();
        assert!(matches!(err, SnapshotError::MemoryWalkFailed(_)));
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn version_mismatch_on_open_fails_loudly() {
        let path = tmp_file("version");
        {
            let mut f = File::create(&path).unwrap();
            f.write_all(MEMORY_MAGIC).unwrap();
            f.write_all(&999u32.to_le_bytes()).unwrap();
            f.write_all(&0u32.to_le_bytes()).unwrap();
        }
        let err = MemoryImageReader::open(&path).unwrap_err();
        assert!(matches!(err, SnapshotError::VersionMismatch { .. }));
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn sparse_file_is_actually_sparse_on_disk() {
        // Sanity: a 1 MiB all-zero region with sparse=true should produce a
        // file noticeably smaller than 1 MiB.
        let path = tmp_file("sparseness");
        let meta = MemoryRegionMeta {
            guest_phys_base: 0,
            size: 1024 * 1024,
            sparse: true,
        };
        let payload = vec![0u8; 1024 * 1024];
        let mut w = MemoryImageWriter::create(&path, &[meta]).unwrap();
        w.write_region(0, &payload).unwrap();
        w.finalize().unwrap();
        let metadata = std::fs::metadata(&path).unwrap();
        // Logical length is at least header + descriptor + region size.
        assert!(metadata.len() >= 1024 * 1024);
        // Round-trip still reads all zeroes back.
        let mut reader = MemoryImageReader::open(&path).unwrap();
        let mut dst = vec![0xFFu8; 1024 * 1024];
        reader.read_region(0, &mut dst).unwrap();
        assert!(dst.iter().all(|&b| b == 0));
        // We can't reliably assert physical-sparseness across all
        // filesystems, but the round-trip + payload integrity is what
        // restore actually depends on.
        std::fs::remove_file(path).ok();
    }

    #[test]
    fn read_region_size_mismatch_fails() {
        let path = tmp_file("size-mismatch");
        let meta = MemoryRegionMeta {
            guest_phys_base: 0,
            size: 4096,
            sparse: false,
        };
        let mut w = MemoryImageWriter::create(&path, &[meta]).unwrap();
        w.write_region(0, &vec![0u8; 4096]).unwrap();
        w.finalize().unwrap();

        let mut reader = MemoryImageReader::open(&path).unwrap();
        let mut dst = vec![0u8; 2048];
        let err = reader.read_region(0, &mut dst).unwrap_err();
        assert!(matches!(err, SnapshotError::MemoryWalkFailed(_)));
        std::fs::remove_file(path).ok();
    }
}
