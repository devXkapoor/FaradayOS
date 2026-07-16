# ADR-0001: Target the x86 Instruction Set Architecture

> **In the context of** building FaradayOS as a from-scratch learning operating system,
> **facing** the choice of which CPU instruction set architecture to target,
> **we decided for** the x86 family (IA-32) **and against** ARM, RISC-V, and legacy ISAs,
> **to achieve** access to the entire hobby-OS resource canon, a browser-bootable demo, and a boot sequence whose legacy layers are themselves the history lesson,
> **accepting** the complexity and inelegance of a backward-compatible architecture that is over forty years old.

**Status:** Accepted
**Date:** 2026-07-11
**Decider:** Devansh
**Related:** PRD — FaradayOS Level 1 · ADR-0002 (CPU mode) · ADR-0003 (firmware)

---

## Context

An operating system is written against an **Instruction Set Architecture (ISA)** — the contract between hardware and software defining which instructions a CPU family executes, which registers exist, how memory is addressed, and how interrupts are delivered. Two chips sharing an ISA run the same binaries regardless of internal differences; two chips with different ISAs cannot, without translation.

This makes the ISA the root architectural decision of the project. It determines the assembly language written, the boot process followed, the privilege model available, the firmware interface encountered, and — practically — which documentation, tutorials, emulators, and debuggers exist to support the work. Every subsequent decision in FaradayOS inherits its constraints from this one.

The forces at play, drawn from the PRD:

- **Understanding is the primary goal** (PRD §1, §3). The project exists to make the machine's operation legible from first principles. Resource availability and pedagogical clarity therefore outweigh architectural elegance.
- **The learning path is Nick Blundell's bare-metal curriculum**, supplemented by the OSDev wiki and the wider hobby-OS canon.
- **QEMU is the primary development target** (PRD §4b, as amended).
- **A browser-bootable demo is desired**, so the artifact is clickable rather than requiring a local toolchain to evaluate.
- **The development machine is an x86-64 laptop** running Windows with WSL2/Ubuntu.
- **Real-hardware boot on that same laptop is desired** (milestone v1.1).
- **Career relevance is secondary but real** — the roles under consideration (SRE, platform, backend, infrastructure) value machine-level understanding, not any specific ISA.

## Considered Options

### 1. x86 (IA-32) — *chosen*

Intel's lineage from the 8086 (1978), formalized as IA-32 by the 80386 (1985). CISC, and ferociously backward-compatible: a modern processor still powers on in 16-bit real mode pretending to be a 1978 chip.

**Pros:** The entire hobby-OS canon targets it — Blundell's curriculum assumes it, the OSDev wiki's beginner path is x86, and decades of accumulated tutorials, forum answers, and reference material exist. It is QEMU's default target with zero configuration. The v86 browser emulator supports it, making the demo possible. The development laptop is x86, so real-hardware boot is same-architecture with no cross-compilation. Its accumulated legacy — segmentation, real mode, the A20 gate, the 0x7C00 convention — is not merely cruft but *preserved computing history*, and each oddity has an origin story, which aligns directly with the project's origin-and-history-before-mechanism method.

**Cons:** Genuinely inelegant. Decades of accreted compatibility layers, a baroque mode-switching sequence, and a vestigial segmentation system that is mandatory to configure but barely used. CISC instruction encoding is irregular and verbose compared to RISC alternatives. Knowledge gained is architecture-specific.

### 2. ARM (AArch32 / AArch64)

RISC; dominant in mobile, Apple Silicon, Raspberry Pi, and increasingly cloud servers.

**Pros:** Cleaner, more orthogonal instruction set. Strong career relevance in embedded and increasingly in cloud. Arguably the more "modern" architecture to learn.

**Cons:** **There is no standard boot process.** Firmware varies by board, device trees describe hardware differently per platform, and bring-up is board-specific. For a project whose explicit purpose is understanding *the* boot process, one would instead learn *a particular board's* boot process. Fewer beginner OS-dev resources, and no browser-emulator path for the demo.

### 3. RISC-V

The open ISA from UC Berkeley (2010).

**Pros:** The cleanest teaching ISA in existence — no legacy, orthogonal, genuinely modern, designed for pedagogy. Good QEMU support. Growing rapidly.

**Cons:** The beginner OS-dev resource ecosystem is thin next to x86's thirty years of accumulation. No browser-emulator path for the demo. And — decisively for this project — *a clean machine with no legacy has no history to teach.* RISC-V teaches the concepts efficiently; x86 teaches the concepts *and why they came to be this way*.

### 4. Legacy ISAs (MIPS, PowerPC, SPARC, 68k)

**Surveyed and dismissed.** MIPS is commercially fading; PowerPC and SPARC are legacy niches; 68k is a retro-hobby scene. None offers a resource base or relevance sufficient to justify the friction.

## Decision

**FaradayOS will target the x86 family, specifically IA-32 as established by the Intel 80386.**

The deciding factor is that x86's greatest weakness on aesthetic grounds is its greatest strength on *this project's* grounds. The real → protected mode climb is not an obstacle between the developer and a working kernel — it *is* the curriculum. Every strange corner (why segmentation exists, why the A20 gate exists, why 0x7C00) has a documented origin, and walking through them in sequence is the history of personal computing preserved in silicon.

RISC-V would have been chosen had the goal been "learn OS concepts with minimum friction." The goal is "understand the machine my code runs on, including why it is shaped this way" — and the machine my code runs on is x86.

## Consequences

**Positive**

- Every learning resource in the hobby-OS canon applies directly; no translation or adaptation.
- QEMU works with no configuration; the iteration loop is fast from day one.
- The v86 browser emulator becomes available, making the browser-bootable demo achievable at zero hosting cost (see ADR-0002 for the constraint this imposes).
- The development laptop is x86, so real-hardware boot (v1.1) requires no cross-compilation and targets a machine already on the desk.
- Each legacy quirk becomes a teaching moment with a real origin story, satisfying the PRD's understanding goals rather than merely its artifact goals.

**Negative**

- The project inherits genuine architectural ugliness: irregular instruction encoding, mandatory-but-vestigial segmentation, and a three-stage mode climb.
- Knowledge is architecture-specific; ARM and RISC-V familiarity are not acquired.
- The CISC instruction set is more verbose and less orthogonal than the alternatives, making some assembly less pleasant to write.

**Follow-on decisions forced by this choice**

- **ADR-0002** must decide which x86 *mode* the kernel targets (real / protected / long), since x86 offers several and they are not interchangeable.
- **ADR-0003** must decide the firmware interface (legacy BIOS vs UEFI), a choice that exists only because x86 has two.
- Any future portability to another ISA would require a hardware abstraction layer and constitutes a new PRD, not an incremental change.
