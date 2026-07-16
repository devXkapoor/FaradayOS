# ADR-0003: Boot via Legacy BIOS

> **In the context of** targeting x86 IA-32 in 32-bit protected mode (ADR-0001, ADR-0002),
> **facing** the choice of which firmware interface FaradayOS boots through,
> **we decided for** legacy BIOS **and against** UEFI and against delegating to an existing bootloader,
> **to achieve** the primitive boot sequence the project exists to understand, plus a browser-bootable demo,
> **accepting** that modern UEFI-only hardware will require a compatibility shim, and recording that UEFI is **deferred, not rejected**.

**Status:** Accepted
**Date:** 2026-07-11
**Decider:** Devansh
**Related:** ADR-0001 (x86) · ADR-0002 (32-bit protected mode) · PRD §4a (UEFI deferred) · Milestone v1.1 (real hardware)

---

## Context

**Firmware** is the code burned into the machine that runs before any operating system exists. Its job is to wake the hardware, perform self-tests, find a boot device, and hand control to software. It is the first link in the chain of trust and control, and its contract determines what state the machine is in when the first line of FaradayOS executes.

x86 has two firmware interfaces, from two different eras, with entirely different contracts.

**Legacy BIOS** (Basic Input/Output System, 1981, IBM PC). On power-on it performs POST, then reads the **first 512 bytes** of the boot device, verifies the final two bytes are the signature `0x55 0xAA`, copies those bytes to memory address **`0x7C00`**, and jumps there. That is the entire contract. The machine arrives in **16-bit real mode**, and the firmware leaves behind a set of software-interrupt services the boot code may call: `int 0x10` (video), `int 0x13` (disk), `int 0x15` (memory map), `int 0x16` (keyboard).

**UEFI** (Unified Extensible Firmware Interface; descended from Intel's EFI, 1998; UEFI 2.0 in 2006). A far larger firmware that understands FAT filesystems natively. Rather than a raw 512-byte sector, it loads a **PE32+ executable** (a `.efi` file — the same binary format as a Windows `.exe`) from a dedicated EFI System Partition, and hands control to it with the machine **already in 32- or 64-bit mode**, with a rich API of Boot Services (memory allocation, file I/O, graphics via GOP) available. There is no `0x7C00`, no `0x55AA`, no 512-byte constraint, no real mode, and **no `int 0x10` or `int 0x13`**.

The forces at play:

- **The PRD's primary goal is understanding the machine from first principles** (§1, §3), specifically the boot sequence as a causal chain.
- **The browser demo constrains the choice.** The v86 emulator boots via SeaBIOS; attempts to run it with UEFI firmware have not succeeded. A browser-bootable demo therefore requires BIOS.
- **Modern hardware is increasingly UEFI-only.** Intel began removing CSM (Compatibility Support Module — the legacy-BIOS emulation layer inside UEFI firmware) around 2020, so machines from roughly 2020 onward frequently cannot boot a BIOS OS natively.
- **A compatibility shim exists.** CSMWrap is an EFI application that wraps a CSM build of SeaBIOS as an out-of-firmware EFI application, dropped into `/efi/boot`, allowing legacy BIOS operating systems to boot on modern UEFI-only systems.
- **Every learning resource uses BIOS.** Blundell's curriculum and the OSDev beginner path assume the BIOS contract.
- **PRD §4a already records UEFI as deferred with the door intentionally open** — not scheduled to any level, but not excluded either.

## Considered Options

### 1. Legacy BIOS — *chosen*

**Pros:** The BIOS contract *is* the curriculum — `0x7C00`, the `0x55AA` signature, the 512-byte constraint, real mode, and the manual climb to protected mode are precisely the mechanisms the project exists to understand, and each has a documented origin story. Enables the v86 browser demo. Every learning resource applies. QEMU's default with no configuration. Simple enough that Level 1 stays about concepts rather than firmware plumbing.

**Cons:** Obsolete in industry. Real-hardware boot (v1.1) depends on either a CSM option existing in the laptop's firmware or on CSMWrap, which is a young project with caveats. Provides no experience with the firmware interface modern systems actually use.

### 2. UEFI

**Pros:** What modern machines actually run. Native boot on the development laptop with no shim. A richer, better-documented API. The natural path if 64-bit and real hardware ever become simultaneous goals. Would enable Secure Boot study (a subject already explored in the boot-process history document).

**Cons:** **Its value proposition is the opposite of this project's purpose.** UEFI exists to abstract away the primitive boot process so developers don't have to deal with it — while FaradayOS exists precisely to deal with it, on purpose, in order to understand it. Choosing UEFI would mean the firmware performs the real → protected climb *for* you, skipping the single most instructive sequence in the project. It also **kills the browser demo**, requires learning PE32+ and the ESP layout, and diverges from every learning resource in the chosen curriculum.

### 3. Delegate to an existing bootloader (GRUB via Multiboot, or Limine)

A genuine and common path: let GRUB handle firmware, and receive control with the machine already in protected mode via the Multiboot specification. Supports both BIOS and UEFI transparently.

**Pros:** Free multi-firmware support. Skips straight to kernel work. Many hobby OSes take this route.

**Cons:** **It deletes Level 1.** Milestones v0.1–v0.5 — the boot sector, the disk load, the GDT, the mode switch — *are* the work GRUB would do on your behalf. For a project whose stated purpose is understanding the boot process, outsourcing the boot process to someone else's bootloader is a category error. Reasonable for a project that wants a kernel; wrong for a project that wants comprehension.

### 4. Coreboot / open firmware

**Surveyed and dismissed.** Open-source firmware replacing the vendor BIOS/UEFI. Requires flashing supported hardware, adds significant risk and complexity, and answers a question (firmware freedom) the project is not asking.

## Decision

**FaradayOS boots via legacy BIOS.**

The deciding factor is that UEFI's core value — abstracting away the primitive boot sequence — directly contradicts the project's core purpose. UEFI would hand FaradayOS a machine that has already climbed most of the ladder the project exists to climb. BIOS hands it a machine in the most primitive state the architecture offers, which is exactly the starting point required.

The browser-demo constraint independently forces the same answer, and CSMWrap resolves what would otherwise have been the strongest counter-argument (real-hardware boot on modern UEFI-only machines).

## Consequences

**Positive**

- The Level-1 curriculum is preserved intact: real mode, `0x7C00`, the signature, `int 0x10`, `int 0x13`, and the manual GDT/CR0 climb.
- The v86 browser demo remains achievable at zero hosting cost.
- Every learning resource applies without adaptation; QEMU needs no configuration.
- The boot path is simple enough that Level 1 stays about concepts rather than firmware plumbing.

**Negative**

- FaradayOS uses a firmware interface that is obsolete in industry.
- Real-hardware boot (v1.1) is contingent on an empirical fact not yet verified: whether the development laptop exposes a CSM / Legacy Boot option. If it does not, v1.1 depends on CSMWrap, which is young and reserves a logical processor.
- Secure Boot must be disabled on any real hardware used for v1.1.
- No experience is gained with the firmware interface modern systems use.

**On UEFI — deferred, not rejected**

UEFI remains a *Later* per PRD §4a, with the door deliberately open. This ADR records the conditions under which it would be revisited:

1. **If v1.1 fails** — the laptop has no CSM and CSMWrap does not work reliably — then UEFI becomes the only path to real-hardware boot, and the trade (losing the browser demo, gaining metal) would need re-weighing.
2. **If long mode is adopted** (see ADR-0002's migration notes) *and* real-hardware boot is still wanted, UEFI becomes the natural firmware, since the browser demo would already have been sacrificed.
3. **If Secure Boot / trusted boot becomes a study target** at a later level, UEFI is a prerequisite.

Should any of these occur, this ADR will not be edited. A new ADR will be written and this one marked *Superseded by ADR-00NN*, preserving the reasoning that BIOS was correct for the Level-1 understanding goal even if it later ceased to be correct for other goals.
