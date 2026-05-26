use std::cmp;
use std::convert::TryInto;
use std::io::Write;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;

use utils::eventfd::EventFd;
use vm_memory::{ByteValued, Bytes, GuestAddress, GuestMemory, GuestMemoryMmap};

use super::super::{
    ActivateError, ActivateResult, BalloonError, DeviceQueue, DeviceState, QueueConfig,
    VirtioDevice,
};
use super::{defs, defs::uapi};
use crate::virtio::InterruptTransport;

// Inflate queue.
pub(crate) const IFQ_INDEX: usize = 0;
// Deflate queue.
pub(crate) const DFQ_INDEX: usize = 1;
// Stats queue.
pub(crate) const STQ_INDEX: usize = 2;
// Page-hinting queue.
pub(crate) const PHQ_INDEX: usize = 3;
// Free page reporting queue.
pub(crate) const FRQ_INDEX: usize = 4;

// The virtio-balloon protocol always describes pages in 4KiB units, regardless
// of the host or guest page size.
const VIRTIO_BALLOON_PFN_SHIFT: u64 = 12;
const VIRTIO_BALLOON_PAGE_SIZE: usize = 1 << VIRTIO_BALLOON_PFN_SHIFT;
// Offset of the `actual` field within VirtioBalloonConfig (num_pages is first).
const CONFIG_ACTUAL_OFFSET: u64 = 4;

// Supported features.
pub(crate) const AVAIL_FEATURES: u64 = (1 << uapi::VIRTIO_F_VERSION_1 as u64)
    | (1 << uapi::VIRTIO_BALLOON_F_STATS_VQ as u64)
    | (1 << uapi::VIRTIO_BALLOON_F_FREE_PAGE_HINT as u64)
    | (1 << uapi::VIRTIO_BALLOON_F_REPORTING as u64);

#[derive(Copy, Clone, Debug, Default)]
#[repr(C, packed)]
pub struct VirtioBalloonConfig {
    /* Number of pages host wants Guest to give up. */
    num_pages: u32,
    /* Number of pages we've actually got in balloon. */
    actual: u32,
    /* Free page report command id, readonly by guest */
    free_page_report_cmd_id: u32,
    /* Stores PAGE_POISON if page poisoning is in use */
    poison_val: u32,
}

// Safe because it only has data and has no implicit padding.
unsafe impl ByteValued for VirtioBalloonConfig {}

/// Handle for adjusting a running balloon's target from outside the VMM event
/// loop (e.g. a control-socket listener thread). Cloneable and thread-safe;
/// the actual queue/memory work still happens on the event loop thread after
/// `control_evt` is signalled.
#[derive(Clone)]
pub struct BalloonControl {
    target_pages: Arc<AtomicU32>,
    control_evt: Arc<EventFd>,
    /// Maximum number of 4KiB pages that may be reclaimed from the guest
    /// (i.e. boot RAM ceiling minus the configured floor).
    max_pages: u32,
}

impl BalloonControl {
    /// Request that the guest relinquish `pages` 4KiB pages, clamped to the
    /// configured maximum. Wakes the device's event loop to apply the change.
    pub fn set_target_pages(&self, pages: u32) -> u32 {
        let clamped = pages.min(self.max_pages);
        self.target_pages.store(clamped, Ordering::SeqCst);
        if let Err(e) = self.control_evt.write(1) {
            error!("balloon: failed to signal control event: {e:?}");
        }
        clamped
    }

    /// Convenience: set the guest's usable memory to `target_mib`, given the
    /// boot ceiling `ceiling_mib`. Returns the clamped page target applied.
    pub fn set_target_mib(&self, target_mib: u32, ceiling_mib: u32) -> u32 {
        let reclaim_mib = ceiling_mib.saturating_sub(target_mib);
        self.set_target_pages(mib_to_pages(reclaim_mib))
    }

    pub fn max_pages(&self) -> u32 {
        self.max_pages
    }
}

/// Convert MiB to 4KiB balloon pages (1 MiB == 256 pages).
pub fn mib_to_pages(mib: u32) -> u32 {
    mib.saturating_mul(256)
}

pub struct Balloon {
    pub(crate) queues: Option<Vec<DeviceQueue>>,
    pub(crate) avail_features: u64,
    pub(crate) acked_features: u64,
    pub(crate) activate_evt: EventFd,
    pub(crate) control_evt: Arc<EventFd>,
    pub(crate) device_state: DeviceState,
    config: VirtioBalloonConfig,
    target_pages: Arc<AtomicU32>,
    max_pages: u32,
}

impl Balloon {
    /// Create a balloon device.
    ///
    /// `initial_target_pages` is how many 4KiB pages the guest should give up
    /// at boot (start inflated so memory can later be grown back). `max_pages`
    /// bounds runtime reclaim; pass 0 for both to disable resizing.
    pub fn new(initial_target_pages: u32, max_pages: u32) -> super::Result<Balloon> {
        let initial = initial_target_pages.min(max_pages);
        let mut config = VirtioBalloonConfig::default();
        config.num_pages = initial;
        Ok(Balloon {
            queues: None,
            avail_features: AVAIL_FEATURES,
            acked_features: 0,
            activate_evt: EventFd::new(utils::eventfd::EFD_NONBLOCK)
                .map_err(BalloonError::EventFd)?,
            control_evt: Arc::new(
                EventFd::new(utils::eventfd::EFD_NONBLOCK).map_err(BalloonError::EventFd)?,
            ),
            device_state: DeviceState::Inactive,
            config,
            target_pages: Arc::new(AtomicU32::new(initial)),
            max_pages,
        })
    }

    /// Returns a cloneable handle for adjusting the balloon target at runtime.
    pub fn control(&self) -> BalloonControl {
        BalloonControl {
            target_pages: self.target_pages.clone(),
            control_evt: self.control_evt.clone(),
            max_pages: self.max_pages,
        }
    }

    pub fn id(&self) -> &str {
        defs::BALLOON_DEV_ID
    }

    /// Apply the latest target requested via the control handle: update the
    /// device config and notify the guest driver via a config-change interrupt.
    /// The guest then drives the inflate/deflate queues to converge.
    pub(crate) fn apply_control_target(&mut self) {
        let target = self.target_pages.load(Ordering::SeqCst).min(self.max_pages);
        self.config.num_pages = target;
        self.device_state.signal_config_change();
        info!(
            "balloon: target set to {target} pages ({} MiB reclaimed from guest)",
            (target as u64) / 256
        );
    }

    /// Drain a PFN-carrying queue (inflate or deflate). On inflate we return
    /// the relinquished pages to the host via `madvise(MADV_DONTNEED)`; on
    /// deflate the guest simply reclaims them, so we only ack the buffers.
    fn process_pfn_queue(&mut self, queue_index: usize, release_to_host: bool) -> bool {
        let mem = match self.device_state {
            DeviceState::Activated(ref mem, _) => mem,
            // Validated by the event handler before this is reached.
            DeviceState::Inactive => unreachable!(),
        };

        let queues = self
            .queues
            .as_mut()
            .expect("queues should exist when activated");
        let mut have_used = false;

        while let Some(head) = queues[queue_index].queue.pop(mem) {
            let index = head.index;
            for desc in head.into_iter() {
                // Each buffer holds an array of little-endian 4KiB PFNs.
                let num_pfns = desc.len / 4;
                for i in 0..num_pfns {
                    let pfn: u32 = match mem.read_obj(GuestAddress(desc.addr.0 + (i as u64) * 4)) {
                        Ok(pfn) => pfn,
                        Err(e) => {
                            error!("balloon: failed to read pfn from queue {queue_index}: {e:?}");
                            continue;
                        }
                    };
                    if !release_to_host {
                        continue;
                    }
                    let gpa = GuestAddress((pfn as u64) << VIRTIO_BALLOON_PFN_SHIFT);
                    if let Ok(host_addr) = mem.get_host_address(gpa) {
                        // Best-effort: on hosts with a larger page size this may
                        // not physically reclaim every page, but the guest still
                        // accounts the page as removed from its allocator.
                        unsafe {
                            libc::madvise(
                                host_addr as *mut libc::c_void,
                                VIRTIO_BALLOON_PAGE_SIZE,
                                libc::MADV_DONTNEED,
                            )
                        };
                    }
                }
            }

            have_used = true;
            if let Err(e) = queues[queue_index].queue.add_used(mem, index, 0) {
                error!("failed to add used elements to the queue: {e:?}");
            }
        }

        have_used
    }

    pub fn process_ifq(&mut self) -> bool {
        debug!("balloon: process_ifq()");
        self.process_pfn_queue(IFQ_INDEX, true)
    }

    pub fn process_dfq(&mut self) -> bool {
        debug!("balloon: process_dfq()");
        self.process_pfn_queue(DFQ_INDEX, false)
    }

    pub fn process_frq(&mut self) -> bool {
        debug!("balloon: process_frq()");
        let mem = match self.device_state {
            DeviceState::Activated(ref mem, _) => mem,
            // This should never happen, it's been already validated in the event handler.
            DeviceState::Inactive => unreachable!(),
        };

        let queues = self
            .queues
            .as_mut()
            .expect("queues should exist when activated");
        let mut have_used = false;

        while let Some(head) = queues[FRQ_INDEX].queue.pop(mem) {
            let index = head.index;
            for desc in head.into_iter() {
                let host_addr = mem.get_host_address(desc.addr).unwrap();
                debug!(
                    "balloon: should release guest_addr={:?} host_addr={:p} len={}",
                    desc.addr, host_addr, desc.len
                );
                unsafe {
                    libc::madvise(
                        host_addr as *mut libc::c_void,
                        desc.len.try_into().unwrap(),
                        libc::MADV_DONTNEED,
                    )
                };
            }

            have_used = true;
            if let Err(e) = queues[FRQ_INDEX].queue.add_used(mem, index, 0) {
                error!("failed to add used elements to the queue: {e:?}");
            }
        }

        have_used
    }
}

impl VirtioDevice for Balloon {
    fn avail_features(&self) -> u64 {
        self.avail_features
    }

    fn acked_features(&self) -> u64 {
        self.acked_features
    }

    fn set_acked_features(&mut self, acked_features: u64) {
        self.acked_features = acked_features
    }

    fn device_type(&self) -> u32 {
        uapi::VIRTIO_ID_BALLOON
    }

    fn device_name(&self) -> &str {
        "balloon"
    }

    fn queue_config(&self) -> &[QueueConfig] {
        &defs::QUEUE_CONFIG
    }

    fn read_config(&self, offset: u64, mut data: &mut [u8]) {
        let config_slice = self.config.as_slice();
        let config_len = config_slice.len() as u64;
        if offset >= config_len {
            error!("Failed to read config space");
            return;
        }
        if let Some(end) = offset.checked_add(data.len() as u64) {
            // This write can't fail, offset and end are checked against config_len.
            data.write_all(&config_slice[offset as usize..cmp::min(end, config_len) as usize])
                .unwrap();
        }
    }

    fn write_config(&mut self, offset: u64, data: &[u8]) {
        // The guest reports how many pages it has actually relinquished by
        // writing the `actual` field; everything else is read-only.
        if offset == CONFIG_ACTUAL_OFFSET && data.len() == 4 {
            let mut buf = [0u8; 4];
            buf.copy_from_slice(&data[..4]);
            self.config.actual = u32::from_le_bytes(buf);
            return;
        }
        warn!(
            "balloon: guest driver attempted to write device config (offset={:x}, len={:x})",
            offset,
            data.len()
        );
    }

    fn activate(
        &mut self,
        mem: GuestMemoryMmap,
        interrupt: InterruptTransport,
        queues: Vec<DeviceQueue>,
    ) -> ActivateResult {
        if queues.len() != defs::NUM_QUEUES {
            error!(
                "Cannot perform activate. Expected {} queue(s), got {}",
                defs::NUM_QUEUES,
                queues.len()
            );
            return Err(ActivateError::BadActivate);
        }

        if self.activate_evt.write(1).is_err() {
            error!("Cannot write to activate_evt",);
            return Err(ActivateError::BadActivate);
        }

        self.queues = Some(queues);
        self.device_state = DeviceState::Activated(mem, interrupt);

        Ok(())
    }

    fn is_activated(&self) -> bool {
        self.device_state.is_activated()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mib_to_pages_uses_4kib_units() {
        assert_eq!(mib_to_pages(0), 0);
        assert_eq!(mib_to_pages(1), 256);
        assert_eq!(mib_to_pages(2048), 524_288);
    }

    #[test]
    fn new_starts_inflated_to_initial_target() {
        // Boot ceiling 4096 MiB, usable 2048 MiB => inflate 2048 MiB worth.
        let initial = mib_to_pages(2048);
        let max = mib_to_pages(4096 - 512);
        let balloon = Balloon::new(initial, max).unwrap();
        let num_pages = balloon.config.num_pages; // copy out of packed struct
        assert_eq!(num_pages, initial);
        assert_eq!(balloon.control().target_pages.load(Ordering::SeqCst), initial);
    }

    #[test]
    fn control_clamps_target_to_max() {
        let max = mib_to_pages(1024);
        let control = Balloon::new(0, max).unwrap().control();
        assert_eq!(control.set_target_pages(max + 999), max);
        assert_eq!(control.target_pages.load(Ordering::SeqCst), max);
    }

    #[test]
    fn set_target_mib_reclaims_difference_from_ceiling() {
        // Ceiling 8192, floor 512 => max reclaim (8192-512) MiB of pages.
        let ceiling = 8192;
        let max = mib_to_pages(ceiling - 512);
        let control = Balloon::new(0, max).unwrap().control();
        // Asking for 6144 MiB usable should reclaim 8192-6144 = 2048 MiB.
        assert_eq!(control.set_target_mib(6144, ceiling), mib_to_pages(2048));
        // Asking below the floor clamps to max reclaim.
        assert_eq!(control.set_target_mib(0, ceiling), max);
    }
}
