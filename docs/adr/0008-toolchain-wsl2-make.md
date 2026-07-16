# ADR-0008: Toolchain — WSL2/Ubuntu with NASM, Make, QEMU, GDB and Git

> **In the context of** developing FaradayOS on a Windows laptop (Lenovo LOQ 15IRX9) with a Unix-native toolchain (ADR-0004, 0007),
> **facing** the choice of host environment and build system,
> **we decided for** WSL2/Ubuntu with GNU Make **and against** native Windows tooling, dual-boot, a virtual machine, and CMake or shell scripts,
> **to achieve** a Unix toolchain matching every resource in the curriculum, with zero risk to the working Windows install and a one-command build,
> **accepting** WSL2's slight indirection and Make's notorious tab-sensitivity.

**Status:** Accepted
**Date:** 2026-07-11
**Decider:** Devansh
**Related:** ADR-0004 (NASM) · ADR-0007 (QEMU) · Epic FARA-E1 (Project setup) · Milestone v0.1

---

## Context

The tools are already largely determined by earlier decisions: **NASM** by ADR-0004, **QEMU** and **GDB** by ADR-0007. What remains genuinely open is *where they run* and *what orchestrates them*.

The forces:

- The development machine runs **Windows** and must continue to — it is the daily driver and the LOQ's Windows install is UEFI/GPT (ADR-0003 notes), meaning firmware experiments carry real risk.
- The entire toolchain is **Unix-native**. NASM, QEMU, Make, GDB, and every subsequent tool assume a Unix shell. Blundell's curriculum and the OSDev canon assume Linux.
- The build is **small**: a handful of `.asm` files, a concatenation step, and a QEMU invocation. Whatever orchestrates it must be legible at a glance, because Success Metric 1 covers the build as much as the code — an opaque build system would hide steps the project exists to understand.
- **CI must run the same build** (Success Metric 7), so the build must work identically on GitHub Actions' Ubuntu runners.

## Considered Options

### Host environment

**1. WSL2 / Ubuntu — *chosen***

A real Linux kernel running alongside Windows.

**Pros:** The full Unix toolchain via `apt`, matching every resource verbatim. Zero risk to the Windows install — no partitioning, no bootloader changes, nothing touched. QEMU's window surfaces as an ordinary Windows window via WSLg, so nothing is lost visually. The filesystem is reachable from both sides. It matches GitHub Actions' Ubuntu runners, so local and CI builds agree.

**Cons:** A layer of indirection; occasional filesystem-performance and path quirks at the Windows/Linux boundary. Nested virtualization (QEMU inside WSL2) means falling back to TCG emulation rather than KVM — irrelevant at Level 1's scale, where boot time is dominated by BIOS init rather than execution speed.

**2. Native Linux (dual-boot or replacement)**

**Pros:** The cleanest environment; no indirection; KVM available.

**Cons:** Requires repartitioning a UEFI/GPT machine whose firmware has already proven inflexible — real risk to a working install for a benefit that does not bind at this scale. Dual-booting also imposes a reboot between OS development and everything else in life, which is a genuine tax on a one-hour-a-day track.

**3. Native Windows tooling**

NASM and QEMU both have Windows builds; Make via MSYS2 or similar.

**Pros:** No layers.

**Cons:** Path handling, shell differences, and Makefile portability fight every tutorial in the curriculum. Hours would be spent translating Unix-assuming instructions rather than learning the boot process — friction with no educational payload.

**4. A Linux VM (VirtualBox/VMware)**

**Pros:** Isolated, disposable.

**Cons:** Strictly worse than WSL2 here — heavier, slower, and running QEMU inside a VM inside Windows compounds the nesting WSL2 already imposes.

### Build system

**1. GNU Make — *chosen***

**Pros:** Ancient, ubiquitous, present everywhere including CI runners. Its model — targets, prerequisites, recipes — maps exactly onto the build's actual shape (`boot.bin` depends on `boot.asm`; `os-image.bin` depends on both stages). A four-line Makefile is legible in full at a glance, so the build hides nothing. Every resource in the curriculum uses it. Learning Make is itself career-relevant, since it underpins most of the C and systems world.

**Cons:** Recipes must be indented with **tabs, not spaces** — a notorious, silent, and infuriating failure mode. Its syntax ages poorly for large projects.

**2. CMake**

**Pros:** Modern, industry-standard for large C/C++ projects.

**Cons:** A build-system *generator* — it produces Makefiles or Ninja files. For five assembly files this adds an abstraction layer whose entire purpose is managing complexity that does not exist here, and it would obscure the very steps Success Metric 1 requires be legible.

**3. Shell scripts**

**Pros:** Maximum transparency; no dependency on any tool.

**Cons:** No dependency tracking — every build rebuilds everything and, worse, nothing declares *why* a file exists or what it depends on. That declaration is precisely the useful part.

**4. Meson / Ninja**

**Surveyed and dismissed.** Excellent for large modern projects; unnecessary overhead for this one.

## Decision

**FaradayOS is developed in WSL2/Ubuntu, built with GNU Make, assembled with NASM, run under QEMU, debugged with GDB via QEMU's remote stub, and versioned with Git.**

Setup is one command — `sudo apt install nasm qemu-system-x86 make git gdb` — after `wsl --install -d Ubuntu`.

The deciding factors: WSL2 gives a Unix toolchain at zero risk to a working Windows install on a machine whose firmware is already known to be inflexible; and Make is the only build system small enough that the build itself remains an object of understanding rather than a black box.

## Consequences

**Positive**

- Every command in every tutorial works verbatim; no translation friction.
- The Windows install is untouched — no partitioning, no firmware changes, no risk.
- The local environment matches GitHub Actions' Ubuntu runners, so CI and local builds agree by construction.
- The Makefile is short enough to be read in full, keeping the build inside Success Metric 1's scope rather than outside it.
- Total setup is roughly ten minutes and one `apt` line; milestone v0.1 is reachable the same evening.

**Negative**

- WSL2 adds indirection; occasional path and filesystem-performance quirks at the boundary.
- QEMU under WSL2 uses TCG rather than KVM — immaterial at this scale, potentially relevant at Level 4+ if boot times grow.
- Make's tab-sensitivity will silently break the build at least once. This is recorded here so that when it happens, the cause is already documented rather than discovered at midnight.

**Follow-on**

- If the kernel language question at Level 2 resolves toward C (ADR-0004), this toolchain gains a **cross-compiler** — a genuinely non-trivial addition, since the host GCC targets Linux userland and will silently emit code assuming a runtime that does not exist. That will warrant its own ADR.
- The v1.1 real-hardware path adds image-writing tooling (`dd` to a USB stick) and the pre-2020 test machine. No change to this decision.

---

*This ADR closes the Level 1 set (0001–0008). All architecturally significant decisions for milestones v0.1–v1.0 are now recorded.*
