// Copyright 2021 Red Hat, Inc.
// SPDX-License-Identifier: Apache-2.0

#[allow(non_camel_case_types)]
#[allow(improper_ctypes)]
#[allow(dead_code)]
#[allow(non_snake_case)]
#[allow(non_upper_case_globals)]
#[allow(deref_nullptr)]
pub mod bindings;

#[macro_use]
extern crate log;

use bindings::*;

#[cfg(target_arch = "aarch64")]
use std::arch::asm;

use std::convert::TryInto;
use std::fmt::{Display, Formatter};
use std::sync::{Arc, LazyLock};
use std::time::Duration;

#[cfg(all(target_arch = "aarch64", target_os = "macos"))]
use arch::aarch64::sysreg::{sys_reg_name, SYSREG_MASK};
use log::debug;

extern "C" {
    pub fn mach_absolute_time() -> u64;
}

const HV_EXIT_REASON_CANCELED: hv_exit_reason_t = 0;
const HV_EXIT_REASON_EXCEPTION: hv_exit_reason_t = 1;
const HV_EXIT_REASON_VTIMER_ACTIVATED: hv_exit_reason_t = 2;

const TMR_CTL_ENABLE: u64 = 1 << 0;
const TMR_CTL_IMASK: u64 = 1 << 1;
const TMR_CTL_ISTATUS: u64 = 1 << 2;

const PSR_MODE_EL1H: u64 = 0x0000_0005;
const PSR_MODE_EL2H: u64 = 0x0000_0009;
const PSR_F_BIT: u64 = 0x0000_0040;
const PSR_I_BIT: u64 = 0x0000_0080;
const PSR_A_BIT: u64 = 0x0000_0100;
const PSR_D_BIT: u64 = 0x0000_0200;
const PSTATE_EL1_FAULT_BITS_64: u64 = PSR_MODE_EL1H | PSR_A_BIT | PSR_F_BIT | PSR_I_BIT | PSR_D_BIT;
const PSTATE_EL2_FAULT_BITS_64: u64 = PSR_MODE_EL2H | PSR_A_BIT | PSR_F_BIT | PSR_I_BIT | PSR_D_BIT;

const HCR_TLOR: u64 = 1 << 35;
const HCR_RW: u64 = 1 << 31;
const HCR_TSW: u64 = 1 << 22;
const HCR_TACR: u64 = 1 << 21;
const HCR_TIDCP: u64 = 1 << 20;
const HCR_TSC: u64 = 1 << 19;
const HCR_TID3: u64 = 1 << 18;
const HCR_TWE: u64 = 1 << 14;
const HCR_TWI: u64 = 1 << 13;
const HCR_BSU_IS: u64 = 1 << 10;
const HCR_FB: u64 = 1 << 9;
const HCR_AMO: u64 = 1 << 5;
const HCR_IMO: u64 = 1 << 4;
const HCR_FMO: u64 = 1 << 3;
const HCR_PTW: u64 = 1 << 2;
const HCR_SWIO: u64 = 1 << 1;
const HCR_VM: u64 = 1 << 0;
// Use the same bits as KVM uses in vcpu reset.
const HCR_EL2_BITS: u64 = HCR_TSC
    | HCR_TSW
    | HCR_TWE
    | HCR_TWI
    | HCR_VM
    | HCR_BSU_IS
    | HCR_FB
    | HCR_TACR
    | HCR_AMO
    | HCR_SWIO
    | HCR_TIDCP
    | HCR_RW
    | HCR_TLOR
    | HCR_FMO
    | HCR_IMO
    | HCR_PTW
    | HCR_TID3;

const CNTHCTL_EL0VCTEN: u64 = 1 << 1;
const CNTHCTL_EL0PCTEN: u64 = 1 << 0;
// Trap accesses to both virtual and physical counter registers.
const CNTHCTL_EL2_BITS: u64 = CNTHCTL_EL0VCTEN | CNTHCTL_EL0PCTEN;

const AA64PFR0_EL1_EL2EN: u64 = 1 << 8;
const AA64PFR0_EL1_GIC3EN: u64 = 1 << 24;
const AA64PFR1_EL1_SMEMASK: u64 = 3 << 24;

const EC_WFX_TRAP: u64 = 0x1;
const EC_AA64_HVC: u64 = 0x16;
const EC_AA64_SMC: u64 = 0x17;
#[cfg(all(target_arch = "aarch64", target_os = "macos"))]
const EC_SYSTEMREGISTERTRAP: u64 = 0x18;
const EC_DATAABORT: u64 = 0x24;
const EC_AA64_BKPT: u64 = 0x3c;

#[derive(Debug)]
pub enum Error {
    EnableEL2,
    FindSymbol(libloading::Error),
    MemoryMap,
    MemoryUnmap,
    NestedCheck,
    VcpuCreate,
    VcpuInitialRegisters,
    VcpuReadRegister,
    VcpuReadSystemRegister,
    VcpuRequestExit,
    VcpuRun,
    VcpuSetPendingIrq,
    VcpuSetRegister,
    VcpuSetSystemRegister(u16, u64),
    VcpuSetVtimerMask,
    VmCreate,
}

impl Display for Error {
    fn fmt(&self, f: &mut Formatter) -> std::fmt::Result {
        use self::Error::*;

        match self {
            EnableEL2 => write!(f, "Error enabling EL2 mode in HVF"),
            FindSymbol(ref err) => write!(f, "Couldn't find symbol in HVF library: {err}"),
            MemoryMap => write!(f, "Error registering memory region in HVF"),
            MemoryUnmap => write!(f, "Error unregistering memory region in HVF"),
            NestedCheck => write!(
                f,
                "Nested virtualization was requested but it's not support in this system"
            ),
            VcpuCreate => write!(f, "Error creating HVF vCPU instance"),
            VcpuInitialRegisters => write!(f, "Error setting up initial HVF vCPU registers"),
            VcpuReadRegister => write!(f, "Error reading HVF vCPU register"),
            VcpuReadSystemRegister => write!(f, "Error reading HVF vCPU system register"),
            VcpuRequestExit => write!(f, "Error requesting HVF vCPU exit"),
            VcpuRun => write!(f, "Error running HVF vCPU"),
            VcpuSetPendingIrq => write!(f, "Error setting HVF vCPU pending irq"),
            VcpuSetRegister => write!(f, "Error setting HVF vCPU register"),
            VcpuSetSystemRegister(reg, val) => write!(
                f,
                "Error setting HVF vCPU system register 0x{reg:#x} to 0x{val:#x}"
            ),
            VcpuSetVtimerMask => write!(f, "Error setting HVF vCPU vtimer mask"),
            VmCreate => write!(f, "Error creating HVF VM instance"),
        }
    }
}

pub enum InterruptType {
    Irq,
    Fiq,
}

pub trait Vcpus {
    fn set_vtimer_irq(&self, vcpuid: u64);
    fn should_wait(&self, vcpuid: u64) -> bool;
    fn has_pending_irq(&self, vcpuid: u64) -> bool;
    fn get_pending_irq(&self, vcpuid: u64) -> u32;
    fn handle_sysreg_read(&self, vcpuid: u64, reg: u32) -> Option<u64>;
    fn handle_sysreg_write(&self, vcpuid: u64, reg: u32, val: u64) -> bool;
}

pub fn vcpu_request_exit(vcpuid: u64) -> Result<(), Error> {
    let mut vcpu: u64 = vcpuid;
    let ret = unsafe { hv_vcpus_exit(&mut vcpu, 1) };

    if ret != HV_SUCCESS {
        Err(Error::VcpuRequestExit)
    } else {
        Ok(())
    }
}

pub fn vcpu_set_pending_irq(
    vcpuid: u64,
    irq_type: InterruptType,
    pending: bool,
) -> Result<(), Error> {
    let _type = match irq_type {
        InterruptType::Irq => hv_interrupt_type_t_HV_INTERRUPT_TYPE_IRQ,
        InterruptType::Fiq => hv_interrupt_type_t_HV_INTERRUPT_TYPE_FIQ,
    };

    let ret = unsafe { hv_vcpu_set_pending_interrupt(vcpuid, _type, pending) };

    if ret != HV_SUCCESS {
        Err(Error::VcpuSetPendingIrq)
    } else {
        Ok(())
    }
}

pub fn vcpu_set_vtimer_mask(vcpuid: u64, masked: bool) -> Result<(), Error> {
    let ret = unsafe { hv_vcpu_set_vtimer_mask(vcpuid, masked) };

    if ret != HV_SUCCESS {
        Err(Error::VcpuSetVtimerMask)
    } else {
        Ok(())
    }
}

/// Checks if Nested Virtualization is supported on the current system. Only
/// M3 or newer chips on macOS 15+ will satisfy the requirements.
pub fn check_nested_virt() -> Result<bool, Error> {
    type GetEL2Supported =
        libloading::Symbol<'static, unsafe extern "C" fn(*mut bool) -> hv_return_t>;

    let get_el2_supported: Result<GetEL2Supported, libloading::Error> =
        unsafe { HVF.get(b"hv_vm_config_get_el2_supported") };
    if get_el2_supported.is_err() {
        info!("cannot find hv_vm_config_get_el2_supported symbol");
        return Ok(false);
    }

    let mut el2_supported: bool = false;
    let ret = unsafe { (get_el2_supported.unwrap())(&mut el2_supported) };
    if ret != HV_SUCCESS {
        error!("hv_vm_config_get_el2_supported failed: {ret:?}");
        return Err(Error::NestedCheck);
    }

    Ok(el2_supported)
}

pub struct HvfVm {}

static HVF: LazyLock<libloading::Library> = LazyLock::new(|| unsafe {
    libloading::Library::new(
        "/System/Library/Frameworks/Hypervisor.framework/Versions/A/Hypervisor",
    )
    .unwrap()
});

impl HvfVm {
    pub fn new(nested_enabled: bool) -> Result<Self, Error> {
        let config = unsafe { hv_vm_config_create() };
        if nested_enabled {
            let set_el2_enabled: libloading::Symbol<
                'static,
                unsafe extern "C" fn(hv_vm_config_t, bool) -> hv_return_t,
            > = unsafe {
                HVF.get(b"hv_vm_config_set_el2_enabled")
                    .map_err(Error::FindSymbol)?
            };

            let ret = unsafe { (set_el2_enabled)(config, true) };
            if ret != HV_SUCCESS {
                return Err(Error::EnableEL2);
            }
        }

        let ret = unsafe { hv_vm_create(config) };

        if ret != HV_SUCCESS {
            Err(Error::VmCreate)
        } else {
            Ok(Self {})
        }
    }

    pub fn map_memory(
        &self,
        host_start_addr: u64,
        guest_start_addr: u64,
        size: u64,
    ) -> Result<(), Error> {
        let ret = unsafe {
            hv_vm_map(
                host_start_addr as *mut core::ffi::c_void,
                guest_start_addr,
                size.try_into().unwrap(),
                (HV_MEMORY_READ | HV_MEMORY_WRITE | HV_MEMORY_EXEC).into(),
            )
        };
        if ret != HV_SUCCESS {
            Err(Error::MemoryMap)
        } else {
            Ok(())
        }
    }

    pub fn unmap_memory(&self, guest_start_addr: u64, size: u64) -> Result<(), Error> {
        let ret = unsafe { hv_vm_unmap(guest_start_addr, size.try_into().unwrap()) };
        if ret != HV_SUCCESS {
            Err(Error::MemoryUnmap)
        } else {
            Ok(())
        }
    }
}

#[derive(Debug)]
pub enum VcpuExit<'a> {
    Breakpoint,
    Canceled,
    CpuOn(u64, u64, u64),
    HypervisorCall,
    MmioRead(u64, &'a mut [u8]),
    MmioWrite(u64, &'a [u8]),
    PsciHandled,
    SecureMonitorCall,
    Shutdown,
    SystemRegister,
    VtimerActivated,
    WaitForEvent,
    WaitForEventExpired,
    WaitForEventTimeout(Duration),
}

struct MmioRead {
    addr: u64,
    len: usize,
    srt: u32,
}

pub struct HvfVcpu<'a> {
    vcpuid: hv_vcpu_t,
    vcpu_exit: &'a hv_vcpu_exit_t,
    cntfrq: u64,
    mmio_buf: [u8; 8],
    pending_mmio_read: Option<MmioRead>,
    pending_advance_pc: bool,
    vtimer_masked: bool,
    nested_enabled: bool,
}

impl HvfVcpu<'_> {
    pub fn new(mpidr: u64, nested_enabled: bool) -> Result<Self, Error> {
        let mut vcpuid: hv_vcpu_t = 0;
        let vcpu_exit_ptr: *mut hv_vcpu_exit_t = std::ptr::null_mut();

        #[cfg(target_arch = "aarch64")]
        let cntfrq = {
            let cntfrq: u64;
            unsafe { asm!("mrs {}, cntfrq_el0", out(reg) cntfrq) };
            cntfrq
        };
        #[cfg(target_arch = "x86_64")]
        let cntfrq = 0u64;
        #[cfg(target_arch = "riscv64")]
        let cntfrq = 0u64;

        let ret = unsafe {
            hv_vcpu_create(
                &mut vcpuid,
                &vcpu_exit_ptr as *const _ as *mut *mut _,
                std::ptr::null_mut(),
            )
        };
        if ret != HV_SUCCESS {
            return Err(Error::VcpuCreate);
        }

        // We write vcpuid to Aff1 as otherwise it won't match the redistributor ID
        // when using HVF in-kernel GICv3.
        let ret = unsafe { hv_vcpu_set_sys_reg(vcpuid, hv_sys_reg_t_HV_SYS_REG_MPIDR_EL1, mpidr) };
        if ret != HV_SUCCESS {
            return Err(Error::VcpuCreate);
        }

        let vcpu_exit: &hv_vcpu_exit_t = unsafe { vcpu_exit_ptr.as_mut().unwrap() };

        Ok(Self {
            vcpuid,
            vcpu_exit,
            cntfrq,
            mmio_buf: [0; 8],
            pending_mmio_read: None,
            pending_advance_pc: false,
            vtimer_masked: false,
            nested_enabled,
        })
    }

    pub fn set_initial_state(&self, entry_addr: u64, fdt_addr: u64) -> Result<(), Error> {
        if self.nested_enabled {
            let ret = unsafe {
                hv_vcpu_set_reg(self.vcpuid, hv_reg_t_HV_REG_CPSR, PSTATE_EL2_FAULT_BITS_64)
            };
            if ret != HV_SUCCESS {
                return Err(Error::VcpuInitialRegisters);
            }

            let ret = unsafe {
                hv_vcpu_set_sys_reg(self.vcpuid, hv_sys_reg_t_HV_SYS_REG_HCR_EL2, HCR_EL2_BITS)
            };
            if ret != HV_SUCCESS {
                return Err(Error::VcpuInitialRegisters);
            }

            let ret = unsafe {
                hv_vcpu_set_sys_reg(
                    self.vcpuid,
                    hv_sys_reg_t_HV_SYS_REG_CNTHCTL_EL2,
                    CNTHCTL_EL2_BITS,
                )
            };
            if ret != HV_SUCCESS {
                return Err(Error::VcpuInitialRegisters);
            }

            // Enable EL2 and GICv3 in ID_AA64PFR0_EL1
            let val: u64 = 0;
            let ret = unsafe {
                hv_vcpu_get_sys_reg(
                    self.vcpuid,
                    hv_sys_reg_t_HV_SYS_REG_ID_AA64PFR0_EL1,
                    &val as *const _ as *mut _,
                )
            };
            if ret != HV_SUCCESS {
                return Err(Error::VcpuInitialRegisters);
            }
            let ret = unsafe {
                hv_vcpu_set_sys_reg(
                    self.vcpuid,
                    hv_sys_reg_t_HV_SYS_REG_ID_AA64PFR0_EL1,
                    val | AA64PFR0_EL1_EL2EN | AA64PFR0_EL1_GIC3EN,
                )
            };
            if ret != HV_SUCCESS {
                return Err(Error::VcpuInitialRegisters);
            }

            // If SME is enabled in ID_AA64PFR1_EL1 in the VM, the guest will
            // break after enabling the MMU. Mask it out.
            let val: u64 = 0;
            let ret = unsafe {
                hv_vcpu_get_sys_reg(
                    self.vcpuid,
                    hv_sys_reg_t_HV_SYS_REG_ID_AA64PFR1_EL1,
                    &val as *const _ as *mut _,
                )
            };
            if ret != HV_SUCCESS {
                return Err(Error::VcpuInitialRegisters);
            }
            let ret = unsafe {
                hv_vcpu_set_sys_reg(
                    self.vcpuid,
                    hv_sys_reg_t_HV_SYS_REG_ID_AA64PFR1_EL1,
                    val & !AA64PFR1_EL1_SMEMASK,
                )
            };
            if ret != HV_SUCCESS {
                return Err(Error::VcpuInitialRegisters);
            }
        } else {
            let ret = unsafe {
                hv_vcpu_set_reg(self.vcpuid, hv_reg_t_HV_REG_CPSR, PSTATE_EL1_FAULT_BITS_64)
            };
            if ret != HV_SUCCESS {
                return Err(Error::VcpuInitialRegisters);
            }
        }

        let ret = unsafe { hv_vcpu_set_reg(self.vcpuid, hv_reg_t_HV_REG_PC, entry_addr) };
        if ret != HV_SUCCESS {
            return Err(Error::VcpuInitialRegisters);
        }

        let ret = unsafe { hv_vcpu_set_reg(self.vcpuid, hv_reg_t_HV_REG_X0, fdt_addr) };
        if ret != HV_SUCCESS {
            return Err(Error::VcpuInitialRegisters);
        }

        Ok(())
    }

    pub fn id(&self) -> u64 {
        self.vcpuid
    }

    fn read_reg(&self, reg: u32) -> Result<u64, Error> {
        let val: u64 = 0;
        let ret = unsafe { hv_vcpu_get_reg(self.vcpuid, reg, &val as *const _ as *mut _) };
        if ret != HV_SUCCESS {
            Err(Error::VcpuReadRegister)
        } else {
            Ok(val)
        }
    }

    pub fn write_reg(&self, rt: u32, val: u64) -> Result<(), Error> {
        let ret = unsafe { hv_vcpu_set_reg(self.vcpuid, rt, val) };
        if ret != HV_SUCCESS {
            Err(Error::VcpuSetRegister)
        } else {
            Ok(())
        }
    }

    fn read_sys_reg(&self, reg: u16) -> Result<u64, Error> {
        let val: u64 = 0;
        let ret = unsafe { hv_vcpu_get_sys_reg(self.vcpuid, reg, &val as *const _ as *mut _) };
        if ret != HV_SUCCESS {
            Err(Error::VcpuReadSystemRegister)
        } else {
            Ok(val)
        }
    }

    fn hvf_sync_vtimer(&mut self, vcpu_list: Arc<dyn Vcpus>) {
        if !self.vtimer_masked {
            return;
        }

        let ctl = self
            .read_sys_reg(hv_sys_reg_t_HV_SYS_REG_CNTV_CTL_EL0)
            .unwrap();
        let irq_state = (ctl & (TMR_CTL_ENABLE | TMR_CTL_IMASK | TMR_CTL_ISTATUS))
            == (TMR_CTL_ENABLE | TMR_CTL_ISTATUS);
        vcpu_list.set_vtimer_irq(self.vcpuid);
        if !irq_state {
            vcpu_set_vtimer_mask(self.vcpuid, false).unwrap();
            self.vtimer_masked = false;
        }
    }

    fn handle_psci_request(&self) -> Result<VcpuExit<'_>, Error> {
        match self.read_reg(hv_reg_t_HV_REG_X0)? {
            0x8400_0000 /* QEMU_PSCI_0_2_FN_PSCI_VERSION */ => {
                self.write_reg(hv_reg_t_HV_REG_X0, 2)?;
                Ok(VcpuExit::PsciHandled)
            },
            0x8400_0006 /* QEMU_PSCI_0_2_FN_MIGRATE_INFO_TYPE */ => {
                self.write_reg(hv_reg_t_HV_REG_X0, 2)?;
                Ok(VcpuExit::PsciHandled)
            },
            0x8400_0008 /* QEMU_PSCI_0_2_FN_SYSTEM_OFF */ => {
                Ok(VcpuExit::Shutdown)
            },
            0x8400_0009 /* QEMU_PSCI_0_2_FN_SYSTEM_RESET */ => {
                Ok(VcpuExit::Shutdown)
            },
            0xc400_0003 /* QEMU_PSCI_0_2_FN64_CPU_ON */ => {
                let mpidr = self.read_reg(hv_reg_t_HV_REG_X1)?;
                let entry = self.read_reg(hv_reg_t_HV_REG_X2)?;
                let context_id = self.read_reg(hv_reg_t_HV_REG_X3)?;
                self.write_reg(hv_reg_t_HV_REG_X0, 0)?;
                Ok(VcpuExit::CpuOn(mpidr, entry, context_id))
            }
            val => panic!("Unexpected val={val}")
        }
    }

    pub fn run(&mut self, vcpu_list: Arc<dyn Vcpus>) -> Result<VcpuExit<'_>, Error> {
        let pending_irq = vcpu_list.has_pending_irq(self.vcpuid);

        if let Some(mmio_read) = self.pending_mmio_read.take() {
            if mmio_read.srt < 31 {
                let val = match mmio_read.len {
                    1 => u8::from_le_bytes(self.mmio_buf[0..1].try_into().unwrap()) as u64,
                    2 => u16::from_le_bytes(self.mmio_buf[0..2].try_into().unwrap()) as u64,
                    4 => u32::from_le_bytes(self.mmio_buf[0..4].try_into().unwrap()) as u64,
                    8 => u64::from_le_bytes(self.mmio_buf[0..8].try_into().unwrap()),
                    _ => panic!(
                        "unsupported mmio pa={} len={}",
                        mmio_read.addr, mmio_read.len
                    ),
                };

                self.write_reg(mmio_read.srt, val)?;
            }
        }

        if self.pending_advance_pc {
            let pc = self.read_reg(hv_reg_t_HV_REG_PC)?;
            self.write_reg(hv_reg_t_HV_REG_PC, pc + 4)?;
            self.pending_advance_pc = false;
        }

        if pending_irq {
            vcpu_set_pending_irq(self.vcpuid, InterruptType::Irq, true)?;
        }

        let ret = unsafe { hv_vcpu_run(self.vcpuid) };
        if ret != HV_SUCCESS {
            return Err(Error::VcpuRun);
        }

        match self.vcpu_exit.reason {
            HV_EXIT_REASON_EXCEPTION => { /* This is the main one, handle below. */ }
            HV_EXIT_REASON_VTIMER_ACTIVATED => {
                self.vtimer_masked = true;
                return Ok(VcpuExit::VtimerActivated);
            }
            HV_EXIT_REASON_CANCELED => return Ok(VcpuExit::Canceled),
            _ => {
                let pc = self.read_reg(hv_reg_t_HV_REG_PC)?;
                panic!(
                    "unexpected exit reason: vcpuid={} 0x{:x} at pc=0x{:x}",
                    self.id(),
                    self.vcpu_exit.reason,
                    pc
                );
            }
        }

        self.hvf_sync_vtimer(vcpu_list.clone());

        let syndrome = self.vcpu_exit.exception.syndrome;
        let ec = (syndrome >> 26) & 0x3f;
        match ec {
            EC_AA64_BKPT => {
                debug!("vcpu[{}]: BRK exit", self.vcpuid);
                Ok(VcpuExit::Breakpoint)
            }
            EC_DATAABORT => {
                let isv: bool = (syndrome & (1 << 24)) != 0;
                let iswrite: bool = ((syndrome >> 6) & 1) != 0;
                let s1ptw: bool = ((syndrome >> 7) & 1) != 0;
                let sas: u32 = ((syndrome >> 22) & 3) as u32;
                let len: usize = (1 << sas) as usize;
                let srt: u32 = ((syndrome >> 16) & 0x1f) as u32;
                let cm: u32 = ((syndrome >> 8) & 0x1) as u32;

                debug!(
                    "EC_DATAABORT {} {} {} {} {} {} {} {}",
                    syndrome, isv as u8, iswrite as u8, s1ptw as u8, sas, len, srt, cm
                );

                let pa = self.vcpu_exit.exception.physical_address;
                self.pending_advance_pc = true;

                if iswrite {
                    let val = if srt < 31 {
                        self.read_reg(hv_reg_t_HV_REG_X0 + srt)?
                    } else {
                        0
                    };

                    match len {
                        1 => self.mmio_buf[0..1].copy_from_slice(&(val as u8).to_le_bytes()),
                        2 => self.mmio_buf[0..2].copy_from_slice(&(val as u16).to_le_bytes()),
                        4 => self.mmio_buf[0..4].copy_from_slice(&(val as u32).to_le_bytes()),
                        8 => self.mmio_buf[0..8].copy_from_slice(&val.to_le_bytes()),
                        _ => panic!("unsupported mmio len={len}"),
                    };

                    Ok(VcpuExit::MmioWrite(pa, &self.mmio_buf[0..len]))
                } else {
                    self.pending_mmio_read = Some(MmioRead { addr: pa, srt, len });
                    Ok(VcpuExit::MmioRead(pa, &mut self.mmio_buf[0..len]))
                }
            }
            #[cfg(all(target_arch = "aarch64", target_os = "macos"))]
            EC_SYSTEMREGISTERTRAP => {
                let isread: bool = (syndrome & 1) != 0;
                let rt: u32 = ((syndrome >> 5) & 0x1f) as u32;
                let reg: u32 = syndrome as u32 & SYSREG_MASK;
                debug!(
                    "EC_SYSTEMREGISTERTRAP isread={}, syndrome={}, rt={}, reg={}, reg_name={}",
                    isread as u32,
                    syndrome,
                    rt,
                    reg,
                    sys_reg_name(reg).unwrap_or("unknown sysreg")
                );

                self.pending_advance_pc = true;

                if isread {
                    assert!(rt < 32);

                    // See https://developer.arm.com/documentation/dui0801/l/Overview-of-AArch64-state/Registers-in-AArch64-state
                    if rt == 31 {
                        return Ok(VcpuExit::SystemRegister);
                    }

                    match vcpu_list.handle_sysreg_read(self.vcpuid, reg) {
                        Some(val) => {
                            self.write_reg(rt, val)?;
                            Ok(VcpuExit::SystemRegister)
                        }
                        None => panic!(
                            "UNKNOWN rt={}, reg={} name={}",
                            rt,
                            reg,
                            sys_reg_name(reg).unwrap_or("unknown sysreg")
                        ),
                    }
                } else {
                    assert!(rt < 32);

                    // See https://developer.arm.com/documentation/dui0801/l/Overview-of-AArch64-state/Registers-in-AArch64-state
                    let val = if rt == 31 { 0u64 } else { self.read_reg(rt)? };

                    if vcpu_list.handle_sysreg_write(self.vcpuid, reg, val) {
                        Ok(VcpuExit::SystemRegister)
                    } else {
                        panic!(
                            "unexpected write: {} name={}",
                            reg,
                            sys_reg_name(reg).unwrap_or("unknown sysreg")
                        );
                    }
                }
            }
            EC_WFX_TRAP => {
                let ctl = self.read_sys_reg(hv_sys_reg_t_HV_SYS_REG_CNTV_CTL_EL0)?;

                self.pending_advance_pc = true;
                if ((ctl & 1) == 0) || (ctl & 2) != 0 {
                    return Ok(VcpuExit::WaitForEvent);
                }

                // Also CNTV_CVAL & CNTV_CVAL_EL0
                let cval = self.read_sys_reg(hv_sys_reg_t_HV_SYS_REG_CNTV_CVAL_EL0)?;
                let now = unsafe { mach_absolute_time() };
                if now > cval {
                    return Ok(VcpuExit::WaitForEventExpired);
                }

                let timeout = Duration::from_nanos((cval - now) * (1_000_000_000 / self.cntfrq));
                Ok(VcpuExit::WaitForEventTimeout(timeout))
            }
            EC_AA64_HVC => self.handle_psci_request(),
            EC_AA64_SMC => {
                self.pending_advance_pc = true;
                self.handle_psci_request()
            }
            _ => panic!("unexpected exception: 0x{ec:x}"),
        }
    }
}

// ============================================================================
// Snapshot / restore: leaf HVF state capture
// ============================================================================
//
// Phase C of `design_docs/snapshot_restore_implementation.md`. These methods
// expose the HVF Framework register get/set calls in a snapshot-friendly
// shape. Vcpu-thread orchestration (sending a Snapshot event to the running
// thread so it pauses on its own context and captures) lives in
// `src/vmm/src/macos/vstate.rs`; this file owns only the leaf primitives
// the orchestrator calls.
//
// What this build captures (per vCPU):
//
// - General regs: X0..X30, PC, FPCR, FPSR, CPSR.
// - SP_EL0, SP_EL1.
// - SIMD/FP: Q0..Q31 (128 bits each).
// - System regs: the fixed list in `HVF_SYS_REG_IDS` below — MMU
//   (SCTLR/TCR/TTBR0/TTBR1/MAIR/AMAIR/CONTEXTIDR/CPACR/VBAR), exception
//   state (SPSR/ELR/ESR/FAR), debug (MDSCR + AFSR0/AFSR1), thread
//   pointers (TPIDR_EL0/EL1, TPIDRRO_EL0), virtual timer
//   (CNTKCTL/CNTV_CTL/CNTV_CVAL).
//
// GICv3 distributor + redistributor state is **not** captured. The
// wrapper-level snapshot site is expected to validate "no pending
// interrupts" as a precondition; full GIC capture is Phase C.3 in the
// design doc.

/// HVF system registers we capture. Byte serialization order matches this
/// list; the restore path reads them back into a parallel array.
pub const HVF_SYS_REG_IDS: &[u16] = &[
    hv_sys_reg_t_HV_SYS_REG_SCTLR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_TCR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_TTBR0_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_TTBR1_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_MAIR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_AMAIR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_CONTEXTIDR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_CPACR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_VBAR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_SPSR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_ELR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_ESR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_FAR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_MDSCR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_AFSR0_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_AFSR1_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_TPIDR_EL0 as u16,
    hv_sys_reg_t_HV_SYS_REG_TPIDR_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_TPIDRRO_EL0 as u16,
    hv_sys_reg_t_HV_SYS_REG_CNTKCTL_EL1 as u16,
    hv_sys_reg_t_HV_SYS_REG_CNTV_CTL_EL0 as u16,
    hv_sys_reg_t_HV_SYS_REG_CNTV_CVAL_EL0 as u16,
];

/// Captured HVF vCPU state.
#[derive(Debug, Clone)]
pub struct HvfVcpuState {
    /// X0..X30, PC, FPCR, FPSR, CPSR (in that order). 35 entries.
    pub general_regs: [u64; 35],
    /// SP_EL0, SP_EL1.
    pub stack_pointers: [u64; 2],
    /// Q0..Q31, 128 bits each.
    pub simd_regs: [u128; 32],
    /// One entry per ID in [`HVF_SYS_REG_IDS`], same order.
    pub sys_regs: Vec<u64>,
}

const HVF_VCPU_STATE_VERSION: u32 = 1;
const HVF_VCPU_STATE_MAGIC: &[u8; 8] = b"KRUNHVS1";

impl HvfVcpuState {
    /// Serialize for embedding in a `VcpuStateV1::payload` byte buffer.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(
            HVF_VCPU_STATE_MAGIC.len()
                + 4
                + 4
                + self.general_regs.len() * 8
                + self.stack_pointers.len() * 8
                + self.simd_regs.len() * 16
                + self.sys_regs.len() * 8,
        );
        buf.extend_from_slice(HVF_VCPU_STATE_MAGIC);
        buf.extend_from_slice(&HVF_VCPU_STATE_VERSION.to_le_bytes());
        buf.extend_from_slice(&(self.sys_regs.len() as u32).to_le_bytes());
        for v in &self.general_regs {
            buf.extend_from_slice(&v.to_le_bytes());
        }
        for v in &self.stack_pointers {
            buf.extend_from_slice(&v.to_le_bytes());
        }
        for v in &self.simd_regs {
            buf.extend_from_slice(&v.to_le_bytes());
        }
        for v in &self.sys_regs {
            buf.extend_from_slice(&v.to_le_bytes());
        }
        buf
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() < HVF_VCPU_STATE_MAGIC.len() + 4 + 4 {
            return Err("HvfVcpuState bytes too short for header".into());
        }
        if &bytes[..HVF_VCPU_STATE_MAGIC.len()] != HVF_VCPU_STATE_MAGIC {
            return Err("bad HvfVcpuState magic".into());
        }
        let mut pos = HVF_VCPU_STATE_MAGIC.len();
        let version = u32::from_le_bytes(bytes[pos..pos + 4].try_into().unwrap());
        pos += 4;
        if version != HVF_VCPU_STATE_VERSION {
            return Err(format!(
                "HvfVcpuState version mismatch: expected {HVF_VCPU_STATE_VERSION}, got {version}"
            ));
        }
        let sys_regs_len = u32::from_le_bytes(bytes[pos..pos + 4].try_into().unwrap()) as usize;
        pos += 4;

        let expected = pos + 35 * 8 + 2 * 8 + 32 * 16 + sys_regs_len * 8;
        if bytes.len() != expected {
            return Err(format!(
                "HvfVcpuState bytes wrong size: expected {expected}, got {}",
                bytes.len()
            ));
        }

        let mut general_regs = [0u64; 35];
        for v in &mut general_regs {
            *v = u64::from_le_bytes(bytes[pos..pos + 8].try_into().unwrap());
            pos += 8;
        }
        let mut stack_pointers = [0u64; 2];
        for v in &mut stack_pointers {
            *v = u64::from_le_bytes(bytes[pos..pos + 8].try_into().unwrap());
            pos += 8;
        }
        let mut simd_regs = [0u128; 32];
        for v in &mut simd_regs {
            *v = u128::from_le_bytes(bytes[pos..pos + 16].try_into().unwrap());
            pos += 16;
        }
        let mut sys_regs = Vec::with_capacity(sys_regs_len);
        for _ in 0..sys_regs_len {
            sys_regs.push(u64::from_le_bytes(bytes[pos..pos + 8].try_into().unwrap()));
            pos += 8;
        }
        Ok(Self {
            general_regs,
            stack_pointers,
            simd_regs,
            sys_regs,
        })
    }
}

// --- GICv3 distributor + redistributor capture (Phase C.3) ---------------

/// A subset of GICv3 distributor registers we capture/restore. These are
/// the registers that meaningfully affect interrupt routing post-restore:
/// the global enable (CTLR) and the per-IRQ enable / priority / config
/// banks. The full GICv3 has many more (SGI generation, message-based
/// SPIs, etc); a future revision can extend this list. The order here is
/// the serialization order.
pub const HVF_GIC_DISTRIBUTOR_REG_IDS: &[u16] =
    &[hv_gic_distributor_reg_t_HV_GIC_DISTRIBUTOR_REG_GICD_CTLR as u16];

/// Per-vCPU redistributor registers we capture/restore.
pub const HVF_GIC_REDISTRIBUTOR_REG_IDS: &[u32] = &[];

/// Captured GICv3 state. Distributor + per-vCPU redistributor values
/// packed alongside an enum tag for forward compatibility.
#[derive(Debug, Clone, Default)]
pub struct HvfGicState {
    /// One value per ID in `HVF_GIC_DISTRIBUTOR_REG_IDS`, same order.
    pub distributor: Vec<u64>,
    /// `redistributor[i]` is the per-vCPU state for vCPU `i`, one entry
    /// per `HVF_GIC_REDISTRIBUTOR_REG_IDS` slot.
    pub redistributor: Vec<Vec<u64>>,
}

const HVF_GIC_STATE_MAGIC: &[u8; 8] = b"KRUNGIC1";
const HVF_GIC_STATE_VERSION: u32 = 1;

impl HvfGicState {
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        buf.extend_from_slice(HVF_GIC_STATE_MAGIC);
        buf.extend_from_slice(&HVF_GIC_STATE_VERSION.to_le_bytes());
        buf.extend_from_slice(&(self.distributor.len() as u32).to_le_bytes());
        buf.extend_from_slice(&(self.redistributor.len() as u32).to_le_bytes());
        for v in &self.distributor {
            buf.extend_from_slice(&v.to_le_bytes());
        }
        for vcpu in &self.redistributor {
            buf.extend_from_slice(&(vcpu.len() as u32).to_le_bytes());
            for v in vcpu {
                buf.extend_from_slice(&v.to_le_bytes());
            }
        }
        buf
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() < HVF_GIC_STATE_MAGIC.len() + 4 + 4 + 4 {
            return Err("HvfGicState bytes too short".into());
        }
        if &bytes[..HVF_GIC_STATE_MAGIC.len()] != HVF_GIC_STATE_MAGIC {
            return Err("bad HvfGicState magic".into());
        }
        let mut pos = HVF_GIC_STATE_MAGIC.len();
        let version = u32::from_le_bytes(bytes[pos..pos + 4].try_into().unwrap());
        pos += 4;
        if version != HVF_GIC_STATE_VERSION {
            return Err(format!(
                "HvfGicState version mismatch: expected {HVF_GIC_STATE_VERSION}, got {version}"
            ));
        }
        let dist_len = u32::from_le_bytes(bytes[pos..pos + 4].try_into().unwrap()) as usize;
        pos += 4;
        let redist_count = u32::from_le_bytes(bytes[pos..pos + 4].try_into().unwrap()) as usize;
        pos += 4;
        let mut distributor = Vec::with_capacity(dist_len);
        for _ in 0..dist_len {
            distributor.push(u64::from_le_bytes(bytes[pos..pos + 8].try_into().unwrap()));
            pos += 8;
        }
        let mut redistributor = Vec::with_capacity(redist_count);
        for _ in 0..redist_count {
            let n = u32::from_le_bytes(bytes[pos..pos + 4].try_into().unwrap()) as usize;
            pos += 4;
            let mut vcpu = Vec::with_capacity(n);
            for _ in 0..n {
                vcpu.push(u64::from_le_bytes(bytes[pos..pos + 8].try_into().unwrap()));
                pos += 8;
            }
            redistributor.push(vcpu);
        }
        Ok(Self {
            distributor,
            redistributor,
        })
    }
}

/// Capture GICv3 state across the whole VM (distributor + every vCPU's
/// redistributor). Caller must have paused all vCPUs first — GIC get/set
/// is read-modify-write on shared state.
///
/// `vcpu_count` is the number of vCPUs whose redistributors to capture.
pub fn save_gic_state(vcpu_count: u32) -> Result<HvfGicState, Error> {
    let mut distributor = Vec::with_capacity(HVF_GIC_DISTRIBUTOR_REG_IDS.len());
    for &reg in HVF_GIC_DISTRIBUTOR_REG_IDS {
        let mut value: u64 = 0;
        let ret = unsafe { hv_gic_get_distributor_reg(reg, &mut value as *mut _) };
        if ret != HV_SUCCESS {
            return Err(Error::VcpuReadSystemRegister);
        }
        distributor.push(value);
    }
    let mut redistributor = Vec::with_capacity(vcpu_count as usize);
    for vcpu_id in 0..vcpu_count {
        let mut vcpu_regs = Vec::with_capacity(HVF_GIC_REDISTRIBUTOR_REG_IDS.len());
        for &reg in HVF_GIC_REDISTRIBUTOR_REG_IDS {
            let mut value: u64 = 0;
            let ret =
                unsafe { hv_gic_get_redistributor_reg(vcpu_id as u64, reg, &mut value as *mut _) };
            if ret != HV_SUCCESS {
                return Err(Error::VcpuReadSystemRegister);
            }
            vcpu_regs.push(value);
        }
        redistributor.push(vcpu_regs);
    }
    Ok(HvfGicState {
        distributor,
        redistributor,
    })
}

/// Restore GICv3 state. Order matters: the GIC must be in the same
/// state as at snapshot time before vCPUs run.
pub fn restore_gic_state(state: &HvfGicState) -> Result<(), Error> {
    if state.distributor.len() != HVF_GIC_DISTRIBUTOR_REG_IDS.len() {
        return Err(Error::VcpuInitialRegisters);
    }
    for (idx, &reg) in HVF_GIC_DISTRIBUTOR_REG_IDS.iter().enumerate() {
        let ret = unsafe { hv_gic_set_distributor_reg(reg, state.distributor[idx]) };
        if ret != HV_SUCCESS {
            return Err(Error::VcpuSetSystemRegister(reg, state.distributor[idx]));
        }
    }
    for (vcpu_id, vcpu_regs) in state.redistributor.iter().enumerate() {
        if vcpu_regs.len() != HVF_GIC_REDISTRIBUTOR_REG_IDS.len() {
            return Err(Error::VcpuInitialRegisters);
        }
        for (idx, &reg) in HVF_GIC_REDISTRIBUTOR_REG_IDS.iter().enumerate() {
            let ret = unsafe { hv_gic_set_redistributor_reg(vcpu_id as u64, reg, vcpu_regs[idx]) };
            if ret != HV_SUCCESS {
                return Err(Error::VcpuSetSystemRegister(
                    u16::try_from(reg).unwrap_or(0),
                    vcpu_regs[idx],
                ));
            }
        }
    }
    Ok(())
}

impl HvfVcpu<'_> {
    /// Capture this vCPU's HVF state. The vCPU must not be currently
    /// executing in `run()` — HVF rejects register get/set on a running
    /// vCPU. The caller's vCPU-thread orchestration (`vcpu_request_exit`
    /// + acknowledgement via the event channel) is responsible for that.
    pub fn save_state(&self) -> Result<HvfVcpuState, Error> {
        let mut general_regs = [0u64; 35];
        for i in 0..=30 {
            general_regs[i as usize] = self.read_reg(hv_reg_t_HV_REG_X0 + i)?;
        }
        general_regs[31] = self.read_reg(hv_reg_t_HV_REG_PC)?;
        general_regs[32] = self.read_reg(hv_reg_t_HV_REG_FPCR)?;
        general_regs[33] = self.read_reg(hv_reg_t_HV_REG_FPSR)?;
        general_regs[34] = self.read_reg(hv_reg_t_HV_REG_CPSR)?;

        let stack_pointers = [
            self.read_sys_reg(hv_sys_reg_t_HV_SYS_REG_SP_EL0 as u16)?,
            self.read_sys_reg(hv_sys_reg_t_HV_SYS_REG_SP_EL1 as u16)?,
        ];

        let mut simd_regs = [0u128; 32];
        for (i, slot) in simd_regs.iter_mut().enumerate() {
            let mut raw: hv_simd_fp_uchar16_t = 0;
            let ret = unsafe {
                hv_vcpu_get_simd_fp_reg(
                    self.vcpuid,
                    hv_simd_fp_reg_t_HV_SIMD_FP_REG_Q0 + i as u32,
                    &mut raw as *mut _,
                )
            };
            if ret != HV_SUCCESS {
                return Err(Error::VcpuReadRegister);
            }
            *slot = raw;
        }

        let mut sys_regs = Vec::with_capacity(HVF_SYS_REG_IDS.len());
        for &id in HVF_SYS_REG_IDS {
            sys_regs.push(self.read_sys_reg(id)?);
        }

        Ok(HvfVcpuState {
            general_regs,
            stack_pointers,
            simd_regs,
            sys_regs,
        })
    }

    /// Restore this vCPU's HVF state. Same precondition: vCPU must not be
    /// running. The vCPU resumes at the saved PC when its run loop is next
    /// entered.
    pub fn restore_state(&self, state: &HvfVcpuState) -> Result<(), Error> {
        if state.sys_regs.len() != HVF_SYS_REG_IDS.len() {
            // Mismatched capture vs restore set — the snapshot was taken
            // with a different libkrun build. Caller should surface this
            // as a version error.
            return Err(Error::VcpuInitialRegisters);
        }
        for i in 0..=30u32 {
            self.write_reg(hv_reg_t_HV_REG_X0 + i, state.general_regs[i as usize])?;
        }
        self.write_reg(hv_reg_t_HV_REG_PC, state.general_regs[31])?;
        self.write_reg(hv_reg_t_HV_REG_FPCR, state.general_regs[32])?;
        self.write_reg(hv_reg_t_HV_REG_FPSR, state.general_regs[33])?;
        self.write_reg(hv_reg_t_HV_REG_CPSR, state.general_regs[34])?;

        self.write_sys_reg(
            hv_sys_reg_t_HV_SYS_REG_SP_EL0 as u16,
            state.stack_pointers[0],
        )?;
        self.write_sys_reg(
            hv_sys_reg_t_HV_SYS_REG_SP_EL1 as u16,
            state.stack_pointers[1],
        )?;

        for (i, q) in state.simd_regs.iter().enumerate() {
            let ret = unsafe {
                hv_vcpu_set_simd_fp_reg(
                    self.vcpuid,
                    hv_simd_fp_reg_t_HV_SIMD_FP_REG_Q0 + i as u32,
                    *q as hv_simd_fp_uchar16_t,
                )
            };
            if ret != HV_SUCCESS {
                return Err(Error::VcpuSetRegister);
            }
        }

        for (i, &id) in HVF_SYS_REG_IDS.iter().enumerate() {
            self.write_sys_reg(id, state.sys_regs[i])?;
        }
        Ok(())
    }

    fn write_sys_reg(&self, reg: u16, val: u64) -> Result<(), Error> {
        let ret = unsafe { hv_vcpu_set_sys_reg(self.vcpuid, reg, val) };
        if ret != HV_SUCCESS {
            Err(Error::VcpuSetSystemRegister(reg, val))
        } else {
            Ok(())
        }
    }
}

#[cfg(test)]
mod snapshot_tests {
    use super::*;

    #[test]
    fn vcpu_state_round_trip_preserves_all_fields() {
        let original = HvfVcpuState {
            general_regs: {
                let mut a = [0u64; 35];
                for (i, slot) in a.iter_mut().enumerate() {
                    *slot = 0x1000 + i as u64;
                }
                a
            },
            stack_pointers: [0xDEAD_BEEF_0000, 0xCAFE_BABE_0000],
            simd_regs: {
                let mut a = [0u128; 32];
                for (i, slot) in a.iter_mut().enumerate() {
                    *slot = ((i as u128) << 64) | 0xFEED_F00D;
                }
                a
            },
            sys_regs: (0..HVF_SYS_REG_IDS.len() as u64)
                .map(|i| 0xAA_0000 + i)
                .collect(),
        };
        let bytes = original.to_bytes();
        let parsed = HvfVcpuState::from_bytes(&bytes).unwrap();
        assert_eq!(parsed.general_regs, original.general_regs);
        assert_eq!(parsed.stack_pointers, original.stack_pointers);
        assert_eq!(parsed.simd_regs, original.simd_regs);
        assert_eq!(parsed.sys_regs, original.sys_regs);
    }

    #[test]
    fn bad_magic_fails() {
        // 16 bytes (header size) of junk that isn't the expected magic.
        let bytes = b"GARBAGE!\x00\x00\x00\x00\x00\x00\x00\x00";
        let err = HvfVcpuState::from_bytes(bytes).unwrap_err();
        assert!(err.contains("magic"));
    }

    #[test]
    fn wrong_size_fails() {
        let mut bytes = HvfVcpuState {
            general_regs: [0; 35],
            stack_pointers: [0; 2],
            simd_regs: [0; 32],
            sys_regs: vec![0; HVF_SYS_REG_IDS.len()],
        }
        .to_bytes();
        bytes.push(0);
        let err = HvfVcpuState::from_bytes(&bytes).unwrap_err();
        assert!(err.contains("size"));
    }
}
