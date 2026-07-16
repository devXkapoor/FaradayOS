# ADR-0007: QEMU as the Primary Development Target

> **In the context of** developing a bare-metal OS that cannot be run as a normal program (ADR-0001, 0003),
> **facing** the choice of where FaradayOS executes during development,
> **we decided for** QEMU **and against** Bochs, VirtualBox/VMware, and real hardware as the primary loop,
> **to achieve** a seconds-long edit-build-boot cycle, a GDB remote stub for automated CPU-state assertions, and headless operation in CI,
> **accepting** that QEMU is more forgiving than real hardware, and recording Bochs as the designated fallback when its stricter emulation or richer debugger is needed.

**Status:** Accepted
**Date:** 2026-07-11
**Decider:** Devansh
**Related:** ADR-0003 (BIOS) · PRD §4a/§4b (as amended) · Milestone v0.7 (GDB assertions) · Milestone v1.1 (real hardware) · Domain Tree OS-17.1 (Hypervisors, Red-touched) · OS-18.3 (Kernel debugging, Green)

---

## Context

Kernel code cannot be run like a program. It owns the machine, so testing it means booting a machine — and booting a *physical* machine to test a code change costs minutes and yields no debugger, no output beyond what the code itself prints, and a reboot as the only response to a mistake. The development loop's cost determines how much can be learned per evening, which makes this a decision about learning velocity rather than mere convenience.

The forces:

- **Iteration speed is a learning multiplier.** The PRD's comprehension gate (Success Metric 4) includes *break-and-predict* — deliberately breaking a component, predicting the failure, then observing it. That method requires dozens of boots per session; anything slower than seconds makes it impractical.
- **Milestone v0.7 requires automated assertions on CPU state** — specifically that `CR0.PE = 1` and `CS` points into the GDT after the switch. That demands programmatic introspection of a running machine's registers.
- **Success Metric 7 requires the test suite to run in CI** — meaning headless, scriptable, exit-coded.
- **Milestone v1.1 requires real hardware**, and the LOQ's CSM is confirmed absent (ADR-0003 notes), so the metal path runs through a pre-2020 machine.

## Considered Options

### 1. QEMU — *chosen*

**Pros:** Boots in under a second; the edit-build-boot loop is `make run`. Provides a **GDB remote stub** (`-s -S`) so standard `gdb` attaches to the emulated CPU and can break, inspect registers, and assert — which is exactly what v0.7 needs and is the mechanism behind Domain Tree node OS-18.3 being Green. Runs **headless** (`-display none`) with scriptable exit codes, making CI possible. Ubiquitous, well-documented, and the default in every resource in the curriculum. Boots legacy BIOS (via SeaBIOS) with no configuration.

**Cons:** **QEMU is forgiving.** It emulates an idealized PC and tolerates mistakes real firmware punishes — lenient A20 handling, predictable drive numbers, tidy register state at `0x7C00`. Code that runs perfectly here can fail on metal, which is the entire reason v1.1 exists as a distinct milestone.

### 2. Bochs

The other classic OS-development emulator, and a genuine competitor rather than a straw man.

**Pros:** A **superior built-in debugger** for OS work — magic breakpoints, instruction tracing, direct descriptor-table and register inspection without an external tool. Historically more pedantically accurate in emulating awkward hardware behaviour, which means it can catch classes of bug QEMU forgives.

**Cons:** Substantially slower, which directly taxes the break-and-predict loop. Its debugger is interactive rather than scriptable-first, making CI integration awkward compared with QEMU's GDB stub. Smaller share of the tutorial base.

**This option is not discarded.** Bochs is recorded as the designated fallback for two situations: when a bug resists QEMU's GDB stub and would yield to Bochs' descriptor-level inspection, and when a v1.1 metal failure needs reproducing under stricter emulation before touching hardware.

### 3. VirtualBox / VMware

**Pros:** Full virtualization, closer to real hardware behaviour than emulation.

**Cons:** No GDB stub of comparable quality, poor scriptability, awkward headless operation, and a slow image-attach loop. Optimized for running finished operating systems, not for developing one.

### 4. Real hardware as the primary loop

**Pros:** Truth. No emulator lies.

**Cons:** Minutes per iteration, no debugger, no output channel beyond what the code prints, and a reboot as the only diagnostic. Legitimate as a *verification* target, disqualifying as a *development* target.

### 5. v86 as the development target

**Pros:** It is already the demo platform (ADR-0002).

**Cons:** Built for demonstration, not development — no GDB stub, no scripting, no CI story. It is an output, not a workshop.

## Decision

**QEMU is FaradayOS's primary development target. Bochs is the designated fallback. Real hardware is the v1.1 verification target. v86 is the demo platform.**

Each tool does the job it is best at, and the division is deliberate: QEMU for the fast loop and automated assertions, Bochs when strictness or a better debugger is needed, real hardware to find what QEMU hid, v86 to show the world.

## Consequences

**Positive**

- `make run` boots in about a second; the break-and-predict gate is practical rather than theoretical.
- The GDB stub makes v0.7's automated CPU-state assertions achievable — arguably the single most distinctive test in the project, since asserting on register state after a mode switch is not something most portfolios contain.
- Headless operation makes CI real (Success Metric 7), and the CI story ("my pipeline boots an OS in an emulator and asserts on CR0") is itself unusual.
- Zero configuration: QEMU's BIOS default matches ADR-0003 exactly.

**Negative**

- **QEMU's forgiveness is a hidden liability**, and it is deliberately deferred rather than solved: A20, drive numbers, and register-state assumptions will all be validated only at v1.1. Some Level-1 code will be wrong in ways QEMU never reveals.
- FaradayOS runs, throughout Level 1, inside a hypervisor (Domain Tree OS-17.1) — a branch marked Red as a build target while being consumed daily as a tool.

**Recorded honestly**

The PRD once made QEMU the *sole* supported target. That was amended (§4a) after real-hardware boot became milestone v1.1. This ADR reflects the amended position: QEMU is *primary*, not sole. The distinction matters, because "primary" carries the obligation to eventually check what the primary tool was hiding — which is what v1.1 is for.
