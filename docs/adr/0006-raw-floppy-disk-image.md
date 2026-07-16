# ADR-0006: Ship a Raw Floppy Disk Image

> **In the context of** booting via legacy BIOS on x86 (ADR-0003),
> **facing** the choice of how FaradayOS's disk image is structured and presented to the firmware,
> **we decided for** a raw floppy image with no partition table and no filesystem **and against** a partitioned hard-disk image, an El Torito ISO, or a formatted FAT12 volume,
> **to achieve** the simplest possible `int 0x13` geometry, compatibility with both QEMU and the v86 browser demo, and a Level 1 that stays about the boot process rather than storage formats,
> **accepting** that real-hardware USB boot (v1.1) may present the medium differently and will require handling at that milestone.

**Status:** Accepted
**Date:** 2026-07-11
**Decider:** Devansh
**Related:** ADR-0003 (BIOS) · Milestone v0.3 (disk load) · Milestone v1.1 (real hardware) · Domain Tree OS-9.1 (Block layer, Yellow)

---

## Context

The BIOS contract (ADR-0003) is indifferent to structure: it reads the first 512 bytes of the boot device, checks for `0x55 0xAA`, and jumps. It does not care whether those bytes sit on a floppy, a hard disk, a CD, or a USB stick.

What *does* care is milestone v0.3, where the boot sector must load its second stage from disk using **`int 0x13`**. That call needs to name sectors, and how sectors are named depends on the medium's presented geometry:

- **CHS addressing** (cylinder / head / sector) — the original scheme, and what `int 0x13` function `AH=0x02` uses. A 1.44 MB floppy has a fixed, universally-known geometry: 80 cylinders, 2 heads, 18 sectors per track.
- **The BIOS drive number**, handed to the boot sector in the `DL` register: `0x00` for the first floppy, `0x80` for the first hard disk.

Additional forces:

- **The v86 browser demo** (ADR-0002) accepts floppy, hard-disk, and CD images; floppy is the simplest to configure.
- **Level 1 has no filesystem** — PRD §4a schedules that at Level 5. The second stage is read as *raw sectors at a known offset*, not as a file.
- **Milestone v1.1 (real hardware)** boots from USB, and a real BIOS may present a USB stick as a floppy, a hard disk, or a CD-ROM depending on the machine and the image — the classic source of "works in QEMU, fails on metal."

## Considered Options

### 1. Raw floppy image — *chosen*

`nasm -f bin` output, optionally padded to 1.44 MB. QEMU: `-fda os-image.bin`. Second stage appended by concatenation (`cat boot.bin kernel.bin > os-image.bin`), read from sector 2 onward.

**Pros:** The simplest geometry in existence, fixed and universally known — no partition table to parse, no filesystem to implement, no MBR layout to respect. `int 0x13` CHS reads are straightforward. Works identically in QEMU and v86. Every tutorial in the curriculum assumes it. Keeps v0.3 about *"how does one ask the BIOS for sectors"* rather than about storage formats.

**Cons:** 1.44 MB ceiling (irrelevant — Level 1's image is measured in kilobytes). Floppies are extinct hardware. On real hardware, USB-as-floppy emulation is one of several possibilities, so v1.1 may find the presented geometry differs.

### 2. Raw hard-disk image with an MBR partition table

**Pros:** Closer to how real systems boot; drive `0x80` is what a USB stick usually presents as on modern BIOSes, so arguably v1.1-friendlier.

**Cons:** Requires laying out and respecting an MBR partition table — a structure Level 1 has no use for, since there is nothing to partition and no filesystem to point at. Adds a concept and a failure mode to milestone v0.3 for no Level-1 benefit.

### 3. El Torito bootable ISO (CD-ROM)

**Pros:** Boots on essentially any machine; convenient for distribution.

**Cons:** El Torito is its own specification with emulation modes, and generating the image requires additional tooling. Complexity entirely unrelated to what Level 1 is teaching.

### 4. FAT12-formatted floppy volume

Format the floppy properly and place the kernel as a *file*.

**Pros:** The kernel becomes a real file; a step toward Level 5.

**Cons:** Requires implementing a FAT12 reader in the boot sector — in 512 bytes, alongside everything else. This is filesystem work, which PRD §4a explicitly defers to Level 5. Doing it now would import a whole level's scope into v0.3.

## Decision

**FaradayOS ships as a raw floppy image: no partition table, no filesystem, second stage concatenated after the boot sector and read as raw sectors.**

The deciding factor is that every alternative imports a structure Level 1 has no use for. The purpose of v0.3 is understanding how the boot sector asks firmware for more bytes — not how partition tables or filesystems are laid out. The floppy's fixed, universally-known geometry is the shortest path to that understanding.

## Consequences

**Positive**

- `int 0x13` CHS reads against known-fixed geometry; no parsing of any structure before the second stage loads.
- Identical behaviour in QEMU and v86, so the demo path and the development path agree.
- The build is a concatenation — the image's byte layout stays fully legible and hexdump-verifiable, consistent with v0.1's 512-byte assertion.
- Level 5 (filesystem) has clean ground to build on, since nothing here pre-commits to a format.

**Negative**

- Floppy emulation is a fiction; the medium has not existed in a decade.
- 1.44 MB ceiling — irrelevant at Level 1, but a constraint that will bind eventually.

**For milestone v1.1 (real hardware)**

This decision creates a known risk that v1.1 exists to resolve. On real hardware booting from USB, the BIOS may present the stick as a floppy (`DL = 0x00`), a hard disk (`DL = 0x80`), or a CD — each with different geometry. Two mitigations are therefore **required of the implementation from v0.3 onward**, not deferred:

1. **Never hardcode the drive number.** Preserve the `DL` value the BIOS provides at entry and use it for every `int 0x13` call. QEMU's predictability makes hardcoding tempting and real hardware makes it fatal.
2. **Do not assume geometry beyond what is read.** Where practical, prefer querying drive parameters (`int 0x13, AH=0x08`) or using LBA extensions (`AH=0x42`) over trusting fixed CHS values.

Both are recorded here so that v1.1's debugging session finds fewer surprises — and both are examples of the QEMU-versus-metal gap the milestone is designed to expose.
