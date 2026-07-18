# LLD — Boot Sector (v0.1)

**Status:** Approved
**Component:** Boot sector (Stage 1, at its v0.1 identity)
**Milestone:** v0.1 — "Boot sector prints a single character via BIOS int 0x10; binary is exactly 512 bytes ending in 0x55AA"
**Source:** `src/boot.asm` → `boot.bin`
**References:** ADR-0003 (legacy BIOS) · ADR-0004 (NASM) · ADR-0006 (raw floppy image) · ADR-0007 (QEMU) · HLD §2–§5 · predecessor: signature-only sector (`sign.asm`)

---

## 1. Purpose

Close the gap the signature-only sector exposed: **acceptance is not proof of execution.** `sign.asm` proved the BIOS will load and jump to any 512-byte sector ending in `0x55 0xAA` — and then executed garbage. This component adds the minimum instruction sequence that emits *observable evidence* that our instructions, specifically, ran: a single character printed through the BIOS video service.

## 2. Scope

**In scope:** one character printed via BIOS `int 0x10` teletype; a deliberate halt; the 512-byte contract (padding + signature).

**Out of scope:** string printing (v0.2), stack establishment (v0.2), segment-register initialization (v0.2), disk loading (v0.3), deliberate `DL` handling (v0.3). Each exclusion is chained to the milestone that resolves it in §9.

## 3. Byte Layout

The artifact is 512 bytes. Every byte is committed here, **before assembly** — §8 verifies NASM produces exactly this.

| Offset (hex) | Length | Bytes (hex) | Source line | Meaning |
|---|---|---|---|---|
| `0x000`–`0x001` | 2 | `B4 0E` | `mov ah, 0x0e` | Select BIOS video function 0x0E (teletype output) |
| `0x002`–`0x003` | 2 | `B0 48` | `mov al, 'H'` | Character to print — `0x48` is ASCII `H` |
| `0x004`–`0x005` | 2 | `CD 10` | `int 0x10` | Invoke BIOS video service via IVT entry 0x10 |
| `0x006`–`0x007` | 2 | `EB FE` | `jmp $` | Relative short jump, displacement −2: jump to self |
| `0x008`–`0x1FD` | 502 | `00` × 502 | `times 510-($-$$) db 0` | Padding to byte 510 |
| `0x1FE`–`0x1FF` | 2 | `55 AA` | `dw 0xaa55` | Boot signature (word `0xAA55`, little-endian on disk) |

**Total: 512 bytes. Code: 8. Padding: 502. Signature: 2.**

Encoding notes, so the table is derivable rather than memorized:

- `mov r8, imm8` encodes as `B0+register` followed by the immediate. `AL` is register 0 (`B0`), `AH` is register 4 (`B4`).
- `int imm8` encodes as `CD` followed by the vector number.
- `jmp $` assembles to the *short relative* form `EB disp8`, where the displacement is measured **from the end of the instruction**. The instruction ends at `$+2`; the target is `$`; displacement = −2 = `0xFE`. This two-byte pair — `EB FE` — is the canonical x86 "hang here forever" idiom, recognizable in hexdumps across four decades of low-level software.
- The `times` count is `510-($-$$)` where `$-$$` = 8 (bytes emitted so far), giving 502 — self-adjusting if code grows.

## 4. Memory Map (runtime)

| Address | Contents | Owner |
|---|---|---|
| `0x00000`–`0x003FF` | Interrupt Vector Table — entry 0x10 (4 bytes at `0x00040`) points at the BIOS video handler `int 0x10` reaches | BIOS |
| `0x00400`–`0x004FF` | BIOS Data Area | BIOS |
| `0x07C00`–`0x07DFF` | **This sector** — code at `0x7C00`–`0x7C07`, padding, signature at `0x7DFE` | us |
| *(unspecified)* | Stack — wherever the BIOS left `SS:SP`; **not established by us** (see §9) | BIOS |

Load address `0x7C00` is the BIOS contract, not a choice (HLD §4).

## 5. Register Usage

| Register | Value | Dictated by |
|---|---|---|
| `AH` | `0x0E` | BIOS `int 0x10` interface: `AH` selects the video sub-function; `0x0E` = teletype output (print `AL`, advance cursor) |
| `AL` | `0x48` (`'H'`) | BIOS teletype contract: `AL` carries the character |
| `BH` | *not set* | Teletype uses `BH` as display page; BIOS default page 0 is assumed (see §9) |
| `DL` | *untouched* | BIOS provides the boot drive number here; this component neither uses nor clobbers it, so it survives **incidentally**. From v0.3 it must survive **deliberately** (ADR-0006) |
| `SS:SP` | *inherited* | No stack is established; `int 0x10` itself pushes FLAGS, CS, IP to whatever stack the BIOS left (see §9) |

## 6. Control Flow

```
entry (BIOS jumps to 0x7C00, 16-bit real mode)
  → AH ← 0x0E              ; select teletype
  → AL ← 'H'               ; load character
  → int 0x10               ; BIOS prints AL at cursor
  → jmp $                  ; ── intentional infinite loop ──
```

Linear, three operations, then a deliberate hang. The hang is `jmp $` rather than `hlt` for a mechanism-level reason: `hlt` stops the CPU only *until the next interrupt*, and hardware interrupts (the timer, ~18.2 Hz in real mode) are still enabled — so a lone `hlt` wakes repeatedly and execution falls through into the padding. The interrupt-safe halt idioms (`cli; hlt` or a `hlt` loop) touch interrupt state this milestone has no reason to touch. `jmp $` is the minimal guaranteed stop.

There is no error path because nothing here can fail detectably: `int 0x10` teletype reports no errors.

## 7. Source Structure

```nasm
[org 0x7c00]        ; assemble-time promise: addresses computed as if loaded at 0x7C00

mov ah, 0x0e        ; BIOS video: select teletype output function
mov al, 'H'         ; the character to print
int 0x10            ; call BIOS video service

jmp $               ; hang forever — nothing to return to

times 510-($-$$) db 0   ; pad with zeros to byte 510
dw 0xaa55               ; boot signature: bytes 55 AA at offsets 510-511
```

Two notes on honesty of construction:

- **`[org 0x7c00]` is present but not yet load-bearing.** Nothing in this file references an absolute address — the `mov`s use immediates, `int` goes through the IVT, and `jmp $` is relative. Remove the directive and the identical binary is produced. It is included because (a) v0.2's label dereferences will require it, and (b) omitting it would make the file lie about where it runs. This is a stated fact, verifiable by the break-and-predict gate.
- Lines 1, 6, 7 are NASM directives (assembly-time); lines 2–5 are x86 instructions (runtime). The directives shape the file; the instructions shape the machine.

## 8. Verification

| # | Check | Command | Expected |
|---|---|---|---|
| 1 | Size is exactly 512 | `ls -l boot.bin` | `512` |
| 2 | **Bytes match §3's commitment** | `xxd boot.bin \| head -1` | `00000000: b40e b048 cd10 ebfe 0000 ...` — note the `H` visible in the ASCII column at position 4 |
| 3 | Signature in place | `xxd boot.bin \| tail -1` | line `000001f0` ending `55aa` |
| 4 | Boots and prints | `make run` | SeaBIOS: `Booting from Floppy...` then **`H`**, then a stable hang |
| 5 | Negative control (already proven) | signature `dw 0x1234` variant | `No bootable device` |

Check 2 is the one this document exists for: §3 predicted the bytes before NASM computed them. If the hexdump matches the table, the construction was understood, not hoped.

## 9. Known Limitations

- **No stack established.** `int 0x10` pushes 6 bytes (FLAGS, CS, IP) onto whatever `SS:SP` the BIOS happened to leave. Benign under QEMU and in practice on real BIOSes, but formally unguaranteed — a QEMU-forgiveness item (ADR-0007). **Resolved at v0.2**, whose `call`/`ret` routine requires a stack we own.
- **Segment registers uninitialized.** Irrelevant here (no memory dereferences), fatal at v0.2 when `[label]` reads require a correct `DS`. **Resolved at v0.2.**
- **`BH` (display page) not set.** BIOS default page 0 assumed; works under any default text mode.
- **One hardcoded character.** Strings are v0.2's print routine.
- **`DL` survives only by accident.** Deliberate preservation begins at v0.3 (ADR-0006 mandate).
- **`org` untested by consequence.** Its correctness is asserted, not exercised, until v0.2 gives it something to compute.
