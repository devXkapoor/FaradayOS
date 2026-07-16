# ADR-0004: Write Level 1 in Pure NASM Assembly

> **In the context of** implementing FaradayOS Level 1 on x86 IA-32 booting via legacy BIOS (ADR-0001, 0002, 0003),
> **facing** the choice of implementation language and assembler,
> **we decided for** pure NASM assembly **and against** GAS, FASM, and against introducing C, Rust, or Zig at this level,
> **to achieve** total visibility of every executed instruction and a toolchain with zero setup cost,
> **accepting** that assembly does not scale, and recording that the C question returns at Level 2–3 — *not* Level 6–7 as the Level Ladder previously implied.

**Status:** Accepted
**Date:** 2026-07-11
**Decider:** Devansh
**Related:** ADR-0001 (x86) · ADR-0002 (32-bit) · ADR-0003 (BIOS) · PRD §4a · Level Ladder

---

## Context

Two questions hide inside "what language should this be written in," and they must be separated because one has no choice and the other does.

**The boot sector's language is not a decision — it is physics.** The BIOS contract (ADR-0003) demands exactly 512 bytes, with the signature `0x55 0xAA` at byte offsets 510–511, loaded raw to `0x7C00`, executing in 16-bit real mode with no runtime, no stack guarantees, and no loader. No higher-level language can express "this file is exactly 512 bytes and byte 510 is 0x55." Every operating system on Earth writes its boot sector in assembly. The only question here is *which assembler*.

**The kernel's language is a real decision.** Above the boot sector, the constraints relax: once code is loaded and running in protected mode, it may be written in anything that can be compiled to freestanding x86 machine code. The genuine question is whether Level 1's kernel is assembly or something higher.

The forces:

- **The primary goal is understanding** (PRD §1, §3), and Success Metric 1 requires that *every instruction in the Level-1 codebase can be explained — what it does, why it's there, what breaks without it.* A compiler generates instructions the author did not write and may not anticipate.
- **Level 1's kernel is a stub.** Per the PRD's milestones, it prints one character to VGA memory at `0xB8000` and halts. Its total size is on the order of tens of instructions.
- **A C toolchain is not free.** Compiling C for a freestanding target requires a cross-compiler (the host GCC targets Linux userland and will silently emit code assuming a C runtime, a stack, and syscalls that do not exist), plus a linker script, plus an understanding of calling conventions at the asm/C boundary. Building a GCC cross-compiler is a genuine multi-hour setup task.
- **The reference curriculum is Nick Blundell's**, which begins in assembly and introduces C once the kernel grows past what assembly comfortably expresses.
- **Intel's own manuals use Intel syntax**, and they are the primary reference for every instruction, register, and descriptor format encountered in this project.

## Considered Options

### 1. NASM, pure assembly — *chosen*

The Netwide Assembler. Intel syntax (`mov eax, 5` — destination first), and — decisively — it emits **flat binary** directly via `-f bin`: no object file, no linker, no headers, just the exact bytes in the exact order, which is precisely what the BIOS contract requires.

**Pros:** Flat-binary output means the boot sector needs no linker script — the `times 510-($-$$) db 0` / `dw 0xaa55` idiom expresses the BIOS contract in two lines. Intel syntax matches the Intel manuals being read alongside. It is the hobby-OS default: Blundell uses it, the OSDev wiki's beginner path assumes it, and thirty years of tutorials are written in it. Zero setup — one `apt install`. Clean macro system. And critically, **it does not preclude C later**: NASM also emits ELF objects (`-f elf32`) that link cleanly against GCC-compiled code, so choosing it now costs nothing later.

**Cons:** Assembly does not scale — it is the right tool for hundreds of lines and the wrong tool for thousands. Manual register and stack discipline. No type safety of any kind.

### 2. GAS (the GNU Assembler)

Part of binutils, already present with any GCC install; AT&T syntax by default (`movl $5, %eax` — source first, sigil-heavy), though Intel syntax is available via `.intel_syntax noprefix`.

**Pros:** Already installed. It is what GCC emits, so a future C kernel is natively in GAS-land, making mixed asm/C projects marginally simpler. Well-integrated with the standard toolchain.

**Cons:** AT&T syntax is genuinely harder to read against Intel's manuals — reversed operand order and sigils create constant friction precisely when cross-referencing the reference material most heavily. Producing a flat binary requires a linker script plus `objcopy`, adding two concepts and a failure mode to the very first milestone. And the resource base for beginner OS dev is overwhelmingly NASM.

### 3. FASM (the Flat Assembler)

Self-hosting, Intel syntax, very fast, powerful macros.

**Pros:** Elegant, capable, flat-binary output, some devoted OS-dev following.

**Cons:** Smaller community and a thinner tutorial base than NASM, for no benefit that matters at this scale. Choosing it would trade resource availability for nothing.

### 4. C with a cross-compiler (boot sector in asm, kernel in C)

The path Blundell eventually takes and most serious hobby OSes adopt.

**Pros:** How real kernels are written. Scales. Career-relevant, particularly for the embedded and systems roles under consideration. Blundell's curriculum arrives here.

**Cons for *Level 1 specifically*:** It costs a cross-compiler build, a linker script, and calling-convention plumbing — to write a kernel that prints one character. The setup exceeds the payload by an order of magnitude. Worse, it directly weakens Success Metric 1: a compiler emits prologue, epilogue, and register-allocation decisions the author did not write, so "every instruction can be explained" becomes "every instruction *I wrote* can be explained, and the rest is the compiler's business" — which is the precise abdication this project exists to refuse.

### 5. Rust (`no_std`)

A real and growing hobby-OS path (Redox OS; the well-known *Writing an OS in Rust* series).

**Pros:** Memory safety, modern tooling, genuine intellectual interest, strong cross-compilation story.

**Cons:** Still requires assembly for the boot sector, so it does not remove the asm question — it adds a second language on top of it. The BIOS/16-bit path is far less documented in Rust than the UEFI/64-bit path most Rust OS material targets. And its abstractions, even in `no_std`, place a layer between author and machine — valuable in production, counterproductive when the layer *is* the thing being studied.

### 6. Zig

**Surveyed and dismissed for now.** Excellent freestanding cross-compilation story and genuinely well-suited to OS work, but a thin resource base for this specific path and an ecosystem still in motion. Revisitable if C proves painful later.

## Decision

**FaradayOS Level 1 is written entirely in NASM assembly.**

Two facts decide it. First, the boot sector must be assembly regardless, so the only question is whether to introduce a *second* language for a kernel stub of a few dozen instructions — and the answer is plainly no; the toolchain cost exceeds the payload. Second, and more importantly, assembly is not a limitation at this level but the *point*: when every byte in the binary is a byte the author typed, Success Metric 1 is satisfied by construction rather than by hope.

NASM over GAS is decided by flat-binary output (`-f bin` expresses the BIOS contract with no linker in the loop) and Intel syntax (matching the manuals in constant use), with the resource base making it near-unanimous.

## Consequences

**Positive**

- Every instruction executed is an instruction typed by the author. Success Metric 1 holds by construction.
- Zero toolchain setup: `apt install nasm` and the first milestone is reachable the same evening.
- The BIOS contract is expressed directly and legibly — `times 510-($-$$) db 0` / `dw 0xaa55` — with no linker script obscuring it.
- Intel syntax matches Intel's manuals, removing constant translation friction while learning descriptor formats and instruction semantics.
- Every tutorial, forum answer, and reference in the curriculum applies verbatim.
- **No future language is foreclosed.** NASM emits ELF objects (`-f elf32`) that link against GCC output, so introducing C later requires no assembler change.

**Negative**

- Assembly does not scale; this decision has a natural expiry.
- No type safety, no abstraction, fully manual register and stack discipline.
- Cross-referencing between AT&T-syntax material (much Linux kernel documentation) requires mental translation.

**On when C arrives — a correction to the Level Ladder**

The Level Ladder lists *"C language and libc → Level 6–7."* Working this decision surfaced that this line **conflates two unrelated things**:

1. **Writing the kernel in C** — requires a cross-compiler and a linker script. Becomes correct as soon as code volume outgrows assembly, which realistically means **Level 2 (interrupts) or Level 3 (paging)**. Interrupt handlers are painful in pure assembly; page-table manipulation is worse.
2. **Providing a C standard library for user programs (libc)** — a userland concern that genuinely belongs at **Level 6–7**, since it presupposes user space and syscalls.

These are different decisions at different levels. This ADR therefore records: **the kernel-language question returns at Level 2**, and will be resolved by its own ADR at that time. The Level Ladder's "C at L6–7" should be amended to refer to *libc* only.
