# ADR-0002: Target 32-bit Protected Mode

> **In the context of** having chosen the x86 architecture (ADR-0001),
> **facing** the choice of which CPU operating mode FaradayOS's kernel runs in,
> **we decided for** 32-bit protected mode (IA-32) **and against** 16-bit real mode and 64-bit long mode,
> **to achieve** a browser-bootable demo, alignment with every learning resource, and the shortest honest path from power-on to a working kernel,
> **accepting** a 4 GB address-space ceiling, eight general-purpose registers, and a future migration cost should long mode later be adopted.

**Status:** Accepted
**Date:** 2026-07-11
**Decider:** Devansh
**Related:** ADR-0001 (x86) · PRD — FaradayOS Level 1 · Level Ladder (L3 = paging)

---

## Context

Unlike most architectures, x86 does not have *a* mode — it has several, and they are historical strata rather than alternatives. A CPU's mode determines register width, how memory addresses are formed, what protection exists, and which instructions are legal.

The relevant facts:

- **Every x86 CPU powers on in 16-bit real mode**, regardless of its actual capabilities. A modern 64-bit processor begins execution pretending to be an 8086 from 1978.
- **The path to long mode is real → protected → long.** Long mode cannot be entered directly from real mode; the CPU must already be in protected mode with a GDT loaded before long mode can be enabled. *Targeting 64-bit does not avoid the 32-bit work — it adds a third stage on top of it.*
- **Long mode requires paging.** Unlike 32-bit protected mode, where paging is optional, long mode cannot be activated without page tables (PAE + a 4-level PML4 structure). Paging is Level 3 on the FaradayOS Level Ladder, out of scope for Level 1.
- **The v86 browser emulator does not support 64-bit kernels.** It emulates an x86 CPU at roughly Pentium 4 level and boots via SeaBIOS; attempts to run UEFI/64-bit configurations under it have not succeeded. A browser demo therefore constrains the target to 16- or 32-bit.
- **Every classic learning resource targets 32-bit protected mode** — Blundell's curriculum, the OSDev beginner path, and the overwhelming majority of hobby-OS tutorials.
- **The PRD defines Level 1 as ending at a 32-bit kernel stub** printing to VGA text memory.

## Considered Options

### 1. 16-bit real mode only

Stop where the BIOS leaves you: 16-bit registers, segmented addressing, 1 MB of addressable memory, no memory protection.

**Pros:** Simplest possible target; BIOS services (int 0x10, int 0x13) remain available throughout; a complete OS can genuinely fit in a boot sector, as several projects demonstrate.

**Cons:** No memory protection, no privilege separation, no path to any modern OS concept. Real mode is the *starting line*, not a destination — stopping here would mean never crossing the threshold that makes an operating system an operating system.

### 2. 32-bit protected mode (IA-32) — *chosen*

The 80386's contribution: 32-bit registers, a 4 GB address space, memory protection via descriptors, privilege rings, and optional paging.

**Pros:** Compatible with the v86 browser demo. Every learning resource targets it. Protected mode is the meaningful threshold — it is where memory protection, privilege rings, and the possibility of a real kernel begin. Paging is *optional* here, which allows Level 1 to cross into protected mode without also building a memory manager. And crucially: **this work is a mandatory prerequisite for long mode anyway**, so nothing built here is discarded if 64-bit is adopted later.

**Cons:** 4 GB address-space ceiling. Only eight general-purpose registers. Not what modern machines actually run in production. Kernel code written for 32-bit requires rewriting for 64-bit's wider registers and different calling convention.

### 3. 64-bit long mode (x86-64)

The modern target: 64-bit registers, sixteen general-purpose registers, RIP-relative addressing, the NX bit, a vast address space.

**Pros:** What real machines actually run. More registers, better ABI. No future migration needed.

**Cons:** **Kills the browser demo** — v86 cannot boot it, and the alternative (server-side QEMU streamed via noVNC) requires paid hosting and is more fragile. **Requires paging before the kernel can run at all**, pulling Level 3's work into Level 1 and violating the level ladder's dependency ordering. Fewer beginner resources. And it does not save any work: the real → protected climb is still mandatory, so this option is strictly *additive* complexity for Level 1.

## Decision

**FaradayOS Level 1 targets 32-bit protected mode (IA-32).**

The reasoning is that 64-bit offers no Level-1 benefit while imposing three costs — losing the browser demo, requiring paging prematurely, and thinning the resource base — and, decisively, it does not eliminate a single line of the work being done anyway. Real mode is where the machine starts; protected mode is the first meaningful threshold; long mode is a *later* stratum reachable from protected mode, not instead of it.

## Consequences

**Positive**

- The browser-bootable demo (v86) becomes achievable, satisfying the PRD's demonstrability aim at zero hosting cost.
- Every resource in the learning path applies without adaptation.
- Level 1 can cross into protected mode without building a memory manager, preserving the Level Ladder's dependency ordering (paging stays at Level 3, where it belongs).
- All Level-1 work is a strict prerequisite of any future 64-bit path — the boot sector, disk loader, GDT, and CR0.PE switch are required regardless.

**Negative**

- 4 GB address-space ceiling and eight general-purpose registers.
- The kernel stub and any 32-bit-specific assembly will require rewriting if long mode is adopted (mitigated by the fact that at Level 1 the kernel is a stub of minimal size).
- FaradayOS does not run in the mode modern production machines use.

**On the future migration to 64-bit**

This decision is *revisitable by design*, and the machinery is already in place:

- The natural transition point is **Level 3 (paging)**, because long mode requires paging and Level 3 builds paging regardless. Adopting long mode there means building PAE/PML4 tables instead of 32-bit page tables — a variation on planned work, not a separate project.
- The transition itself is roughly: enable PAE (CR4), build PML4 tables, set EFER.LME, enable paging (CR0.PG), add a 64-bit code descriptor to the GDT (the L bit), and far-jump. On the order of forty additional lines atop what Level 1 already produces.
- **The browser demo survives.** The Level-1 image is a tagged, released artifact (`v1.0.0`) with the image attached to a GitHub Release. The v86 demo page points at *that* image permanently. If later levels move to long mode and v86 can no longer boot current builds, the demo simply continues to demonstrate v1.0 — a complete, working, honest artifact.
- Per the ADR immutability rule, adopting long mode will **not** edit this record. A new ADR will be written and this one marked *Superseded by ADR-00NN*. The pair will then document the full reasoning: chose 32-bit for these forces, outgrew them for those forces.
