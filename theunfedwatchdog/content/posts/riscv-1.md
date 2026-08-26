+++
date = '2026-05-19T00:51:05+05:30'
title = 'Bare-Metal "Hello World" on RISC-V - Part 1'
author = 'Akshat'

[cover]
    image = "/images/riscv/thumb.png"
    alt = "Bare-metal RISC-V setup"
    relative = true
    hidden = false
    hiddenInSingle = true
    
+++

Everything your OS hides from you, laid bare

<!--more-->

NOTE: This is not a tutorial. Just stuff I understood from watching videos and reading books/articles.

## What Does "Bare-Metal" Mean?

When you write a normal C program on your laptop, a surprising amount of invisible machinery is helping you out. Your operating system loads your binary into memory. The C runtime initializes global variables and sets up the stack before `main()` ever runs. The standard library (`libc`) provides `printf`, `malloc`, `strlen`, and hundreds of other functions. The OS handles keyboard input, screen output, file access, and process management.

Bare-metal programming throws away the training wheels. You are the first code that runs. There is no OS, no libc, no invisible helper. The CPU powers on (or in our case, QEMU resets), sets its program counter to a fixed address, and your code had better be there waiting. You are responsible for everything: setting up the stack, initialising memory, talking directly to hardware registers.

This project is the simplest possible bare-metal program: print a string to the serial port and halt. But understanding how it works requires understanding every layer of the toolchain.

---


## The RISC-V Architecture

RISC-V is an open, royalty-free instruction set architecture (ISA). Unlike ARM or x86, which are owned by companies that charge licensing fees, RISC-V is governed by a non-profit foundation and anyone can implement it. This has made it extremely popular in academia and increasingly in industry.

**`RISC`** stands for Reduced Instruction Set Computer. The philosophy is that a smaller, simpler set of instructions — each doing one clear thing — leads to hardware that is easier to design, easier to verify, and often more power-efficient than architectures with extremely dense and complex instructions.

One of the most interesting things about RISC-V is that the ISA is modular. The base instruction set is intentionally very small, and additional functionality is added through extensions. This means a tiny embedded microcontroller and a powerful Linux-capable CPU can both be "RISC-V" while supporting very different feature sets.

---

## About RV32I

This project targets **RV32I**, the simplest standard RISC-V configuration.

| Part | Meaning |
|------|---------|
| RV32 | 32-bit architecture |
| I | Base integer instruction set |

That is it.

No hardware multiplication.
No compressed instructions.
No floating point.
No atomics.

Just the core integer ISA.

This simplicity is actually one of the reasons RV32I is so useful for learning low-level systems programming. You can understand nearly the entire architecture without needing to deal with dozens of optional instruction formats or extensions.

The base RV32I ISA contains:

- Arithmetic instructions (`add`, `sub`, `addi`)
- Logic instructions (`and`, `or`, `xor`)
- Load/store instructions (`lw`, `sw`, `lb`, `sb`)
- Branch instructions (`beq`, `bne`, `blt`)
- Jump instructions (`jal`, `jalr`)
- Immediate operations
- Basic memory access primitives

Almost everything else in larger RISC-V systems builds on top of this foundation.

---

## Load-Store Architecture

RISC-V is a **load-store architecture**.

This means:

- arithmetic instructions only operate on registers
- memory cannot be manipulated directly by most instructions

For example:

```asm
lw t0, 0(sp)
addi t0, t0, 1
sw t0, 0(sp)
```

The CPU:

1. loads a value from memory into a register
2. modifies the register
3. stores it back into memory

This keeps instruction behavior simple and predictable.

---

## Registers

RV32I has 32 general-purpose integer registers:

```text
x0 - x31
```

Each register is 32 bits wide.

RISC-V also defines ABI aliases for them, which make assembly easier to read.

---

## Important Registers

| Register | ABI Name | Purpose |
|----------|-----------|----------|
| x0 | zero | Always reads as 0 |
| x1 | ra | Return address |
| x2 | sp | Stack pointer |
| x5-x7 | t0-t2 | Temporary registers |
| x8 | s0/fp | Saved register / frame pointer |
| x10-x17 | a0-a7 | Function arguments and return values |

---

## The Zero Register

One of the more elegant RISC-V design choices is that `x0` is hardwired to zero — reading it always returns `0`, and writing to it does nothing at all.

This sounds odd at first, but it turns out to be surprisingly useful. You can discard results you don't care about by writing them to `x0`. You can clear a register by adding zero to it. You can compare a value against zero without loading a constant first. Dozens of common patterns become simpler when you always have zero sitting in a register, ready to use — and the hardware pays essentially nothing to provide it.

---

## Program Counter (PC)

The **Program Counter** is the register that tells the CPU which instruction to execute next.

The execution cycle is conceptually:

1. Fetch instruction at PC
2. Decode instruction
3. Execute instruction
4. Advance PC

Normally, RV32I instructions are 4 bytes long, so the PC increments by 4 after each instruction.

Example:

```text
0x80000000
0x80000004
0x80000008
```

Branch and jump instructions modify the PC directly.

For example:

```asm
jal ra, main
```

stores the return address in `ra` and jumps to `main`.

Without the PC, the CPU would have no idea where the next instruction lives.

---

## Stack Pointer (sp) and the Stack

The stack pointer (`sp`) tracks the top of the stack — a region of RAM used for local variables, saved registers, return addresses, and function call state. Every time a function is called, it carves out a little space on the stack; when it returns, that space is given back.

In RISC-V the stack grows downward, so "carving out space" means subtracting from `sp`:

```asm
addi sp, sp, -16   ; allocate 16 bytes
...
addi sp, sp, 16    ; release them on the way out
```

Here is why this matters at startup: when the CPU resets, `sp` contains garbage — whatever bits happened to be in that register. If you call a C function before pointing `sp` at a real region of RAM, the very first local-variable write goes to a garbage address and you get silent memory corruption or an immediate crash.

This is the entire reason `start.S` must run before `main()`. Its job is to set `sp` to a known, valid address — the top of a reserved block of RAM — before any C code executes.

---

## Frame Pointer / Base Pointer

Register `x8` (`s0` or `fp`) is often used as a **frame pointer**.

The frame pointer gives a stable reference point inside a stack frame.

Why is this useful? Because the stack pointer changes constantly during execution. Example:

```asm
addi sp, sp, -32
mv fp, sp
```

Now local variables can be accessed relative to `fp`:

```asm
lw t0, -4(fp)
```

instead of relying on the constantly-changing stack pointer.

Modern optimized code often omits frame pointers entirely, but they are extremely useful for debugging, stack tracing, understanding function layouts, and operating system kernels.

---

## Return Address Register (`ra`)

When a function is called:

```asm
jal ra, func
```

the CPU:

1. stores the address of the next instruction into `ra`
2. jumps to `func`

Returning is usually done with:

```asm
ret
```

which is effectively:

```asm
jalr x0, 0(ra)
```

This jumps back to the saved return address.

---

## RV32I Instruction Encoding

| Format | 31-25 | 24-20 | 19-15 | 14-12 | 11-7 | 6-0 |
|---|---|---|---|---|---|---|
| R-Type | funct7 | rs2 | rs1 | funct3 | rd | opcode |
| I-Type | imm[11:0] | imm[11:0] | rs1 | funct3 | rd | opcode |
| S-Type | imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode |
| B-Type | imm[12\|10:5] | rs2 | rs1 | funct3 | imm[4:1\|11] | opcode |
| U-Type | imm[31:12] | imm[31:12] | imm[31:12] | imm[31:12] | rd | opcode |
| J-Type | imm[20\|10:1] | imm[10:1\|11] | imm[19:12] | imm[19:12] | rd | opcode |

The fields represent:

- `opcode` → operation type
- `rd` → destination register
- `rs1`, `rs2` → source registers
- `funct3`, `funct7` → additional operation selection bits
- `imm` → immediate constant value

One of the elegant aspects of RISC-V is that these formats are highly regular, which simplifies instruction decoding hardware significantly compared to older architectures like x86.

`NOTE: You can play around in the below website to get a better understanding of how the instruction encoding is done:`

https://luplab.gitlab.io/rvcodecjs/

---

## The Compilation Pipeline

It is tempting to describe compilation as "the compiler turns C into a program." That is true in the same way that "a kitchen turns ingredients into dinner" is true: technically correct, but hiding all the interesting steps in between.

A toolchain is really a small assembly line. Each stage takes one kind of file, does one job, and hands the result to the next stage:

```
source.c / start.S
        |
        v
[Preprocessor]  expands #include, #define, #ifdef
        |
        v
[Compiler]      turns C into target-specific assembly
        |
        v
[Assembler]     turns assembly into relocatable object files
        |
        v
[Linker]        combines objects and assigns final addresses
        |
        v
kernel.elf      the final executable image
```

A useful way to think about each stage: the compiler decides *what instructions should exist*, the assembler encodes those instructions into bytes, and the linker decides *where everything lives in memory*. That last part is not a boring detail — if your code is linked for the wrong address, the CPU may jump into empty memory, your stack may overlap your data, or your program may simply do nothing at all.

The output is an ELF file. ELF is not just a blob of instructions; it is a structured format that records sections, symbols, an entry point, and enough metadata for tools like `objdump` and QEMU to make sense of it. When you run the project, QEMU loads `kernel.elf`, reads the entry point, and starts executing at `_start`.

In practice, `gcc` acts as a friendly front desk for the whole pipeline. When the Makefile invokes `riscv64-unknown-elf-gcc` with `start.S`, `main.c`, and `linker.ld`, GCC quietly calls the preprocessor, compiler, assembler, and linker in the right order.

---

## Cross-Compilation

Your development machine almost certainly runs an x86-64 or ARM64 processor. The target machine (QEMU RISC-V) runs a completely different ISA. You cannot use the system compiler — the binaries it produces would not run on RISC-V hardware.

Instead, you use a **cross-compiler**: a compiler that runs on your host machine (x86-64 Linux, for example) but produces binaries for a different target architecture (RV32I bare-metal).

The tool prefix `riscv64-unknown-elf-` identifies the cross-compiler:

- `riscv64` — it can compile for both 32-bit and 64-bit RISC-V (with the right flags)
- `unknown` — the vendor is unspecified (not tied to a specific board or company)
- `elf` — the output format is bare-metal ELF, no OS ABI assumed

By passing `-march=rv32i -mabi=ilp32`, you tell the compiler you want 32-bit RISC-V code with the ILP32 calling convention, even though the toolchain binary itself contains "64" in its name.

---

## Memory Layout and Sections

A compiled program is not just one long stream of bytes. It is split into **sections** — named buckets that group bytes by purpose. This helps the linker place things correctly, helps the loader know what should be copied into memory, and helps the CPU and memory system enforce sensible permissions.

**`.text` — Code:** This is where executable machine instructions live. Functions like `main`, `putc`, and `puts` become bytes in this section. On systems with memory protection, this region is usually marked executable and read-only.

**`.rodata` — Read-only data:** Constants live here: string literals, lookup tables, constant arrays. A string like `"Hello RISC-V!\n"` is a classic example. Keeping constants separate from writable data is useful because they can often live in ROM or flash.

**`.data` — Initialised data:** Global or static variables that start with a specific non-zero value (e.g. `int counter = 5;`). The initial value is stored in the program image, but at runtime the variable must live in writable memory. On many embedded systems, startup code copies `.data` from flash into RAM before `main()` runs.

**`.bss` — Zero-initialised data:** Global or static variables that start as zero (e.g. `static int buffer[1024];`). The binary does not literally store thousands of zero bytes — it records the size of the region, and startup code clears it. This keeps the file smaller while still giving C the behaviour it promises.

**Stack:** Not a section full of pre-written bytes — a reserved area of RAM used at runtime for function calls, local variables, saved registers, and return addresses. On RISC-V it grows downward. In bare-metal programs, you must choose where the stack lives and initialise `sp` yourself.

**Heap:** The region used for dynamic allocation (`malloc`). Many tiny bare-metal projects skip it entirely, because avoiding dynamic allocation keeps life simpler.

A rough mental picture:

```
+----------------------+  <- code: functions and instructions
| .text                |
+----------------------+  <- constants: strings, lookup tables
| .rodata              |
+----------------------+  <- globals with initial values
| .data                |
+----------------------+  <- globals that start as zero
| .bss                 |
+----------------------+  <- dynamic allocation, if used
| heap                 |
|        ...           |
|        free RAM      |
|        ...           |
| stack                |  <- function calls and local variables
+----------------------+
```

In a desktop program, the OS and C runtime set most of this up for you. In bare-metal programming, there is no such babysitter — your linker script decides where these regions go, and your startup code is responsible for any runtime setup.

---

## What is a Linker Script?

The linker's job is to place sections from all your object files into the final binary. Without guidance, it has no idea where memory is, how much you have, or in what order things should appear. The **linker script** provides that guidance.

A linker script answers three questions:

1. **Where does RAM/ROM start, and how big is it?** (the `MEMORY` block)
2. **Which sections go into which memory region, and in what order?** (the `SECTIONS` block)
3. **What address is the very first instruction?** (the `ENTRY` directive)

For bare-metal code that boots from a fixed address, the linker script is not optional. It is the contract between your source code and the hardware.

---

## Memory-Mapped I/O and UART

QEMU's `virt` machine exposes a **16550A UART** through MMIO at address:

```text
0x10000000
```

The UART exposes multiple internal registers at offsets from this base address. Writing to the transmit holding register (THR) queues a byte for transmission, while other registers expose status flags, FIFO state, interrupt configuration, baud-rate divisors, and line-control settings.

A real UART driver would normally:

- configure the baud-rate divisor
- set frame format (8N1, parity, stop bits, etc.)
- enable and configure FIFOs
- poll or interrupt on transmit readiness
- read the Line Status Register (LSR) before writing data

Typical transmit logic looks conceptually like:

```c
while (!(UART_LSR & TX_READY)) {
}

UART_THR = 'A';
```

The 16550 then serializes the byte and shifts it out bit-by-bit through the TX line.

QEMU simplifies this process significantly. Its UART model is permissive enough that educational bare-metal programs can often skip initialization entirely and directly write bytes to the transmit register:

```c
*(volatile unsigned char*)0x10000000 = 'H';
```

which immediately appears in the terminal attached through `-nographic`. 
This is convenient for learning because it allows us to focus on the toolchain, linker script, startup code, and execution flow without first implementing a complete UART driver.

Docs: https://uart16550.readthedocs.io/en/latest/uart16550doc.html

---

## The `volatile` Keyword

In `main.c`, the UART pointer is declared as:

```c
volatile unsigned char *uart = (volatile unsigned char*) UART0;
```

The `volatile` qualifier is critical and easy to get wrong. It tells the compiler: **"do not optimise accesses through this pointer."**

Without `volatile`, the compiler might look at code like:

```c
*uart = 'H';
*uart = 'e';
```

...and think: "I'm writing to the same address twice. The second write overwrites the first. I can skip the first write as an optimisation." This is perfectly correct reasoning for a normal variable — but catastrophically wrong for a hardware register. The UART hardware *observes* every write and transmits each byte. The compiler must not eliminate any of them.

`volatile` forces the compiler to generate a real memory-store instruction for every access, in the order written. It is mandatory whenever you access hardware registers, shared memory between threads, or memory touched by interrupt handlers.

---

## QEMU and the `virt` Machine

QEMU (Quick EMUlator) is an open-source machine emulator. Rather than running on real RISC-V silicon, our kernel runs inside QEMU's `riscv32 virt` machine — a virtual board that does not correspond to any real chip but is designed to be convenient for software development.

The `virt` machine provides:

- A RISC-V CPU (RV32GC by default)
- RAM starting at `0x80000000`
- A 16550A UART at `0x10000000`
- Interrupt Controllers, virtio devices, and more (unused here)

Key flags used to run the project:

| Flag | Meaning |
|------|---------|
| `-machine virt` | Use the virtual board |
| `-nographic` | No graphical window; route the UART to your terminal's stdin/stdout |
| `-bios none` | Do not load OpenSBI firmware; boot our kernel directly |
| `-kernel kernel.elf` | Load this ELF at `0x80000000` and jump to its entry point |

The `-bios none` flag deserves a word of explanation. By default, QEMU boots RISC-V machines through **OpenSBI** — a small piece of firmware that sits between the hardware and your kernel, handling low-level machine setup and providing a standard interface for things like console output and timer access. It is roughly analogous to a BIOS or UEFI on a PC: software that runs before your OS and sets up the environment for it. For our bare-metal hello-world, we want none of that. We want to be the very first code that runs, with nothing underneath us — so we tell QEMU to skip it entirely.

Docs: https://www.qemu.org/docs/master/system/riscv/virt.html

---

*In the next part, we will look at the actual implementation.*
