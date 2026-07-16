# ADR-0005: Use a Flat Memory Model (Three-Entry GDT)

> **In the context of** entering 32-bit protected mode on x86, where a Global Descriptor Table is mandatory (ADR-0002),
> **facing** the choice of how to configure that table,
> **we decided for** a flat model — a null descriptor plus overlapping code and data segments, each with base 0 and a 4 GB limit — **and against** a genuinely segmented model,
> **to achieve** the memory layout every modern operating system uses, compatibility with C and with future paging, and the property that a linear address simply *is* the offset,
> **accepting** that segmentation's protection features go entirely unused, and that FaradayOS therefore configures a mechanism largely in order to neutralize it.

**Status:** Accepted
**Date:** 2026-07-11
**Decider:** Devansh
**Related:** ADR-0002 (32-bit protected mode) · Milestone v0.4 (GDT) · Milestone v0.5 (mode switch) · Domain Tree OS-7.2 (Segmentation, Green)

---

## Context

**Segmentation** is x86's original memory-management mechanism, and understanding why it exists explains why this decision is strange.

On the 8086 (1978), registers were 16 bits wide, which addresses only 64 KB — but the chip had a 20-bit address bus and 1 MB to reach. The workaround: every memory access combines a **segment** register and an **offset**, computed as `segment × 16 + offset`. Segmentation was not a protection feature; it was an addressing hack to reach memory that 16-bit registers could not name.

The 80286 (1982) repurposed it. In protected mode, a segment register no longer holds an address — it holds a **selector**, an index into a **descriptor table**. Each **descriptor** in that table is an 8-byte record describing one segment: its **base** (where it starts in memory), its **limit** (how far it extends), and an **access byte** and **flags nibble** carrying its privilege level, its type (code or data), and whether it is readable, writable, or executable. Now segmentation *was* protection: the CPU could refuse an access that exceeded a segment's limit or violated its privilege.

The **Global Descriptor Table (GDT)** is the system-wide table of these descriptors. It is not optional: entering protected mode requires loading a valid GDT with `lgdt` first, because the moment `CR0.PE` is set, every memory access is resolved through it.

Three facts shape this decision:

- **The descriptor format is a fossil.** A descriptor's 32-bit base address is split across *three non-contiguous fields*, and its 20-bit limit across two — because the 386's 8-byte descriptor had to remain backward-compatible with the 286's layout. The ugliness is not arbitrary; it is a compatibility scar, and it must be assembled by hand.
- **Segmentation lost.** The 80386 added **paging** on top of segmentation, and paging proved strictly superior for protection: finer granularity, per-process address spaces, and the ability to swap. Every major OS — Linux, Windows NT — responded by configuring segmentation into irrelevance and using paging for everything. x86-64 completed the story: in long mode, segment bases and limits are *ignored* for most segments, forced flat by the hardware itself. Only FS and GS retain bases, used for thread-local storage.
- **FaradayOS Level 1 has no paging.** Per ADR-0002 and the Level Ladder, paging is Level 3. So Level 1 runs in protected mode with segmentation as the *only* address-translation mechanism active — which makes the choice of what to put in the GDT the entire memory model.

The forces from the PRD:

- Understanding is the goal, and Domain Tree node **OS-7.2 (Segmentation)** is one of only thirteen Green nodes — this mechanism is explicitly in scope to be understood, not merely passed through.
- Level 1's kernel is a stub with a single address space, no processes, and no privilege separation (ring 0 only).
- Level 3 will add paging, and Level 6 will add ring 3 — both of which the GDT must not obstruct.

## Considered Options

### 1. Flat model — null + 4 GB code + 4 GB data — *chosen*

Three descriptors. Entry 0 is the **null descriptor** (mandatory: the CPU requires index 0 to be null, and loading a null selector into a data register faults — a deliberate trap that catches uninitialized selectors). Entry 1 is a **code segment**: base `0x00000000`, limit `0xFFFFF` with granularity set so the limit counts 4 KB pages rather than bytes, yielding 4 GB; executable, readable, ring 0. Entry 2 is a **data segment**: identical base and limit, writable, ring 0.

Because both segments start at 0 and span everything, `base + offset` reduces to `offset`. Segmentation is still *active* — the CPU still performs the lookup on every access — but it has been configured to be an identity transformation.

**Pros:** This is what Linux and Windows NT do; it is the industry-standard answer, and matching it means the model ports forward to Level 3's paging and Level 6's ring 3 without redesign. C compilers assume a flat address space — a segmented model would require far pointers and DOS-era memory models (tiny/small/medium/large/huge), which is precisely the misery C escaped. It is forward-compatible with x86-64, where the hardware enforces flatness anyway. And it is simple enough that v0.4 stays about *understanding descriptor structure* rather than debugging segment arithmetic.

**Cons:** Segmentation's protection features go completely unused. The project configures an elaborate mechanism specifically in order to make it do nothing — which can feel like ceremony rather than engineering. The null descriptor's purpose is non-obvious until explained.

### 2. Genuinely segmented model — distinct code, data, and stack segments with real bases and limits

Use segmentation as the 286's designers intended: separate segments with distinct bases, limits enforcing real bounds, and protection derived from the descriptor system rather than from paging.

**Pros:** Provides memory protection *without* paging — genuinely relevant at Level 1, where paging does not exist. Historically faithful to the architecture's original intent. Arguably teaches segmentation more thoroughly, since the mechanism would actually be exercised rather than neutralized.

**Cons:** No modern OS does this, so the knowledge is a dead end — a design that ports nowhere and prepares nothing. It is actively hostile to C (far pointers, memory models) and thus to Level 2+ when the kernel language question returns (ADR-0004). It does not survive x86-64, where segment bases are ignored. And it would have to be *undone* at Level 3 when paging arrives, making it work whose only outcome is later removal.

The educational argument is weaker than it appears, and this deserves stating plainly: **the flat model does not skip learning segmentation.** Building it still requires assembling every descriptor field by hand — base split across three fields, limit across two, the access byte's P/DPL/S/E/DC/RW/A bits, the granularity flag that converts a 20-bit limit into 4 GB of reach. The mechanism is understood completely. What is *not* done is *relying* on it — and understanding *why not* (that paging won) is itself the historical lesson, and a more valuable one than exercising a mechanism the industry abandoned.

### 3. Minimal model — the smallest GDT that permits the mode switch, refined later

Load a bare-minimum table now, revisit when it matters.

**Pros:** Fastest to v0.5.

**Cons:** The flat model *is* already minimal — three entries, of which one is a mandatory null. There is nothing meaningful to cut, so this option collapses into option 1 with less thought behind it.

### 4. Flat model plus ring 3 descriptors now

Add user-mode code and data segments in anticipation of Level 6.

**Pros:** Avoids revisiting the GDT later.

**Cons:** Premature. Level 1 has no user space, no processes, and no privilege boundary; descriptors for a ring that nothing runs in are unexplained entries in a table whose every field is supposed to be justified. Adding two descriptors at Level 6 is trivial work; carrying two meaningless entries through five levels is not.

## Decision

**FaradayOS uses a flat memory model: a three-entry GDT containing a null descriptor, a ring-0 code segment (base 0, limit 4 GB), and a ring-0 data segment (base 0, limit 4 GB).**

The deciding argument is that segmentation is a mechanism the industry evaluated over two decades and abandoned in favor of paging — and the honest way to honor that history is to understand segmentation thoroughly, configure it correctly, and then decline to depend on it, exactly as Linux and Windows NT do. Building a segmented model would mean mastering a dead technique, producing a design that ports nowhere, and scheduling its own removal at Level 3.

## Consequences

**Positive**

- Linear address equals offset, which makes every subsequent memory concept — the kernel load address, VGA memory at `0xB8000`, and Level 3's page tables — reason about a single unambiguous address space.
- Matches Linux, Windows NT, and effectively every modern OS; the model ports forward to paging (L3) and ring 3 (L6) with no redesign.
- Compatible with C, which the kernel-language question at Level 2 will require (ADR-0004).
- Forward-compatible with x86-64, where flatness is hardware-enforced (ADR-0002's migration path).
- Small enough that milestone v0.4 remains about descriptor structure rather than segment arithmetic, and the structure can be verified by hexdump against hand-decoded expected bytes.

**Negative**

- Segmentation's protection features are unused; the GDT is configured largely to neutralize itself.
- The null descriptor requires explanation to avoid appearing as arbitrary ceremony.
- Level 1 therefore has *no memory protection at all* — with segmentation flat and paging absent, the kernel can write anywhere in the 4 GB space. This is accepted: protection arrives with paging at Level 3, and Level 1 runs exactly one thread of execution with nothing to protect it from.

**Follow-on**

- Level 3 (paging) will add page tables *above* this flat model without altering it — the standard arrangement, where segmentation is identity and paging does the real work.
- Level 6 (user space) will extend this GDT with ring-3 code and data descriptors plus a TSS, at which point a new ADR will record the privilege-separation design. This ADR is not superseded by that — the flat model persists; it merely gains entries.
