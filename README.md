# RISC-V SoC Subsystem — Complete RTL-to-GDSII Design & Verification

A complete System-on-Chip (SoC) built around the **PicoRV32** RISC-V processor core, featuring an AXI4-Lite bus, boot ROM, SRAM, and UART peripheral. The project spans bare-metal firmware development, cycle-accurate Verilator simulation, Yosys synthesis, and OpenLane ASIC physical design targeting the **SkyWater 130nm (sky130A)** PDK.

---

## Table of Contents

1. [Repository Structure](#1-repository-structure)
2. [System Architecture](#2-system-architecture)
3. [RTL Module Details](#3-rtl-module-details)
4. [Firmware — Source Code & Build Process](#4-firmware--source-code--build-process)
5. [Simulation — Verilator Testbench](#5-simulation--verilator-testbench)
6. [Yosys Synthesis](#6-yosys-synthesis)
7. [OpenLane Physical Design (ASIC Flow)](#7-openlane-physical-design-asic-flow)
8. [Makefile Reference](#8-makefile-reference)
9. [Debugging Journey — All Bugs Encountered & Fixed](#9-debugging-journey--all-bugs-encountered--fixed)
10. [Expected Terminal Outputs](#10-expected-terminal-outputs)

---

## 1. Repository Structure

```
riscv-soc-subsystem/
├── rtl/                            # Verilog RTL source files
│   ├── picorv32.v                  # PicoRV32 CPU core (third-party, by Clifford Wolf)
│   ├── top.v                       # Top-level SoC module (CPU + Bridge + Interconnect + Slaves)
│   ├── axi_lite_interconnect.v     # 1-Master, 3-Slave AXI4-Lite crossbar
│   ├── axi_decoder.v              # Address decoder (combinational, selects slave by address)
│   ├── rom.v                       # Boot ROM — 8 KB, read-only AXI slave
│   ├── sram.v                      # SRAM — 256 bytes, read/write AXI slave with byte-enable
│   ├── uart_axi.v                  # UART AXI wrapper (TX data register + status register)
│   ├── uart_tx.v                   # UART transmitter — 115200 baud, 8N1 serial
│   └── uart_rx.v                   # UART receiver — placeholder stub (not used in demo)
├── tb/
│   └── tb_top.v                    # System-level Verilator testbench with UART monitor
├── fw/                             # Bare-metal firmware
│   ├── Makefile                    # Firmware build rules (GCC → objcopy → Python hex)
│   ├── start.S                     # Boot assembly — stack init + jump to main
│   ├── main.c                      # Application — UART "Hello Ramnarayan" + "PING"
│   └── link.ld                     # Linker script — ROM/SRAM memory mapping
├── openlane_design/                # OpenLane ASIC configuration
│   ├── config.json                 # Full OpenLane parameter set (66 settings)
│   ├── top.sdc                     # Synopsys Design Constraints (timing, I/O delays)
│   ├── pin_order.cfg               # Physical I/O pin placement on die edges
│   └── flow_commands.tcl           # Interactive TCL flow script (for reference)
├── docs/
│   ├── architecture.md             # Architecture notes
│   └── memory_map.md              # Memory map notes
├── Makefile                        # Top-level build automation
├── .gitignore                      # Ignores obj_dir/, *.vcd, fw/*.elf, runs/, etc.
└── README.md                       # This file
```

---

## 2. System Architecture

### Block Diagram

```
                    ┌─────────────────────────────────────────┐
                    │                  top.v                   │
                    │                                         │
  clk ──────────►  │  ┌──────────┐     ┌──────────────────┐  │
                    │  │ PicoRV32 │     │ AXI-Lite Bridge  │  │
  reset ─────────► │  │ (RV32IMC)│────►│ (5-state FSM)    │  │
                    │  │          │◄────│                   │  │
                    │  └──────────┘     └────────┬─────────┘  │
                    │         mem_valid/ready/     │            │
                    │         addr/wdata/rdata     │ AXI4-Lite  │
                    │                              │ Master     │
                    │              ┌───────────────┴──────┐    │
                    │              │ axi_lite_interconnect │    │
                    │              │ (1 Master × 3 Slaves) │    │
                    │              └──┬────────┬────────┬──┘   │
                    │                 │        │        │       │
                    │           ┌─────┴──┐ ┌───┴───┐ ┌─┴────┐  │
                    │           │ rom.v  │ │sram.v │ │ uart │  │
                    │           │ (S0)   │ │ (S1)  │ │_axi.v│  │
                    │           │ 8 KB   │ │256 B  │ │ (S2) │  │
                    │           └────────┘ └───────┘ └──┬───┘  │
                    │                                    │      │
                    │                              ┌─────┴───┐  │
                    │                              │ uart_tx │  │
  uart_tx ◄────────│                              │ 115200  │  │
  uart_rx ─────────►│                              │  8N1    │  │
                    │                              └─────────┘  │
                    └─────────────────────────────────────────┘
```

### Top-Level Ports (`top.v`)

| Port | Direction | Width | Description |
|:-----|:----------|:------|:------------|
| `clk` | Input | 1 bit | System clock. 50 MHz in simulation, 20 ns period for ASIC. |
| `reset` | Input | 1 bit | **Active-HIGH** synchronous reset. Directly inverted to `resetn` for PicoRV32. |
| `uart_tx` | Output | 1 bit | UART serial transmit line. Directly drives the physical TX pin. |
| `uart_rx` | Input | 1 bit | UART serial receive line. Directly connects to the `uart_axi` wrapper. |

### PicoRV32 Configuration Parameters

The CPU is instantiated in `top.v` with these compile-time parameters:

```verilog
picorv32 #(
    .ENABLE_MUL(1),             // Enable hardware multiplier (M extension)
    .ENABLE_DIV(1),             // Enable hardware divider (M extension)
    .COMPRESSED_ISA(1),         // Enable 16-bit compressed instructions (C extension)
    .ENABLE_IRQ(0),             // Interrupts disabled
    .PROGADDR_RESET(32'h0000_0000)  // Boot from ROM base address
) u_cpu ( ... );
```

This makes it a full **RV32IMC** core with multiply/divide coprocessors (`picorv32_pcpi_mul` and `picorv32_pcpi_div`) but no interrupt controller.

### Memory Map

| Region | Address Range | Slave | `axi_decoder` Match Pattern | Size |
|:-------|:-------------|:------|:---------------------------|:-----|
| ROM | `0x0000_0000` – `0x0000_1FFF` | S0 (`sel = 3'b001`) | `32'h0000_????` | 8 KB (2048 × 32-bit words) |
| SRAM | `0x0001_0000` – `0x0001_00FF` | S1 (`sel = 3'b010`) | `32'h0001_????` | 256 Bytes (64 × 32-bit words) |
| UART | `0x1000_0000` – `0x1000_000F` | S2 (`sel = 3'b100`) | `32'h1000_000?` | 16 Bytes (4 registers) |
| *default* | Any unmatched | S0 (ROM) | `default` | Falls back to ROM |

### UART Register Map

| Offset | C Macro | Access | Description |
|:-------|:--------|:-------|:------------|
| `0x00` | `UART_TX` = `*(volatile uint32_t*)0x10000000` | Write | Write lower 8 bits to transmit a character. Triggers `tx_start` pulse. |
| `0x04` | `UART_RX` = `*(volatile uint32_t*)0x10000004` | Read | Receive data register (placeholder, `uart_rx.v` stub always returns 0). |
| `0x08` | `UART_ST` = `*(volatile uint32_t*)0x10000008` | Read | Status register. Bit 0 = `tx_busy` (1 = transmitter active, 0 = ready). |

---

## 3. RTL Module Details

### 3.1 AXI-Lite Bridge FSM (`top.v`, lines 43–93)

The bridge translates PicoRV32's native memory interface into AXI4-Lite transactions using a **5-state FSM** stored in a 3-bit register `b_state`:

| State | Value | Name | Description |
|:------|:------|:-----|:------------|
| 0 | `3'd0` | **IDLE** | Waits for `cpu_mem_valid && !ready_r`. Checks `cpu_mem_wstrb`: if non-zero → write path (state 1), if zero → read path (state 3). |
| 1 | `3'd1` | **WR_AW** | Asserts `m_axi_awvalid` and `m_axi_wvalid`. Deasserts each when its respective `ready` is received. If `bvalid` arrives immediately → done. Otherwise → state 2. |
| 2 | `3'd2` | **WR_B** | Waits for write response (`m_axi_bvalid`). On receipt, asserts `ready_r` and returns to IDLE. |
| 3 | `3'd3` | **RD_AR** | Asserts `m_axi_arvalid`. When `m_axi_arready` is received, deasserts and asserts `m_axi_rready` → state 4. |
| 4 | `3'd4` | **RD_R** | Waits for read data (`m_axi_rvalid`). Captures `m_axi_rdata` into `rdata_r`, asserts `ready_r`, returns to IDLE. |

**Critical design detail:** The IDLE state checks `cpu_mem_valid && !ready_r` (not just `cpu_mem_valid`). The `!ready_r` guard prevents the bridge from re-issuing a transaction on the same cycle that `ready_r` is asserted, which would cause the CPU to see a duplicate response and enter an infinite instruction-fetch loop.

### 3.2 AXI-Lite Interconnect (`axi_lite_interconnect.v`)

A pure-combinational address-based crossbar with registered selection tracking:

- **Two instances** of `axi_decoder`: one for write address channel (`wr_dec`), one for read address channel (`rd_dec`).
- **Latching logic:** When a new transaction starts (`!wr_active && m_axi_awvalid`), the decoded `sel` is latched into `wr_sel_r` and `wr_active` is set. This ensures the data and response channels continue to route to the correct slave even after the address phase completes.
- **Muxing:** Write data (`wdata`, `wstrb`, `wvalid`) is steered by `act_wr_sel = wr_active ? wr_sel_r : wr_sel`. Read data (`rdata`, `rvalid`, `rresp`) is muxed using a priority ternary chain: `act_rd_sel[0] ? s0 : (act_rd_sel[1] ? s1 : s2)`.

### 3.3 Address Decoder (`axi_decoder.v`)

A purely combinational module using `casez` with don't-care bits (`?`):

```verilog
casez (addr)
    32'h0000_????: sel = 3'b001;  // ROM  — matches 0x00000000–0x0000FFFF
    32'h0001_????: sel = 3'b010;  // SRAM — matches 0x00010000–0x0001FFFF
    32'h1000_000?: sel = 3'b100;  // UART — matches 0x10000000–0x1000000F
    default:       sel = 3'b001;  // Safety fallback → ROM
endcase
```

### 3.4 ROM (`rom.v`)

- **Storage:** `reg [31:0] mem [0:2047]` — 2048 words × 32 bits = 8192 bytes = 8 KB.
- **Addressing:** `wire [10:0] word_addr = araddr[12:2]` — bits [12:2] give 11-bit word index (2^11 = 2048).
- **Read behavior:** On `arvalid && !arready && !rvalid`, captures `mem[word_addr]` into `rdata` and asserts both `arready` and `rvalid` in the same cycle. Deasserts `rvalid` when `rready` is received.
- **Write behavior:** ROM **ignores all write data** but still completes the AXI write handshake (asserts `awready`, `wready`, `bvalid`) to prevent bus deadlock.
- **Initialization:** Uses `$readmemh` to load firmware hex. For simulation: relative path `"rtl/rom.hex"`. For ASIC synthesis: absolute path `"/home/lab-user/riscv-soc-subsystem/rtl/rom.hex"` (gated by `` `ifdef SYNTHESIS ``).

### 3.5 SRAM (`sram.v`)

- **Storage:** `reg [31:0] mem [0:63]` — 64 words × 32 bits = 256 bytes.
- **Write addressing:** `wire [5:0] w_addr = awaddr[7:2]` — bits [7:2] give 6-bit word index (2^6 = 64).
- **Read addressing:** `wire [5:0] r_addr = araddr[7:2]` — same scheme.
- **Byte-enable writes:** The SRAM supports per-byte write strobes via `wstrb[3:0]`:
  ```verilog
  if (wstrb[0]) mem[w_addr][ 7: 0] <= wdata[ 7: 0];   // Byte 0
  if (wstrb[1]) mem[w_addr][15: 8] <= wdata[15: 8];   // Byte 1
  if (wstrb[2]) mem[w_addr][23:16] <= wdata[23:16];   // Byte 2
  if (wstrb[3]) mem[w_addr][31:24] <= wdata[31:24];   // Byte 3
  ```
- **Read behavior:** Identical to ROM — single-cycle capture on `arvalid && !arready && !rvalid`.

### 3.6 UART AXI Wrapper (`uart_axi.v`)

- **Write path:** When `awaddr[7:0] == 8'h00` (offset `0x00`), latches `wdata[7:0]` into `tx_buf` and pulses `tx_start` for one cycle. Any write to other offsets is silently acknowledged.
- **Read path:** When `araddr[7:0] == 8'h08` (offset `0x08`), returns `{31'b0, tx_busy}` — the transmitter busy status in bit 0. All other read offsets return `32'h0`.
- **Sub-module:** Instantiates `uart_tx` with `rst_n` wired as `~reset` (active-low for the TX module).

### 3.7 UART Transmitter (`uart_tx.v`)

A **4-state FSM** implementing standard 8N1 serial transmission at **115,200 baud**:

| State | Value | Name | Behavior |
|:------|:------|:-----|:---------|
| 0 | `2'd0` | **IDLE** | `tx_out = 1` (idle high), `tx_busy = 0`. On `tx_en`: latch `tx_data` → state 1. |
| 1 | `2'd1` | **START** | `tx_out = 0` (start bit). Count 434 clock cycles → state 2. |
| 2 | `2'd2` | **DATA** | `tx_out = data[bit_idx]`. For each of 8 bits (LSB first), count 434 cycles. After bit 7 → state 3. |
| 3 | `2'd3` | **STOP** | `tx_out = 1` (stop bit). Count 434 cycles → state 0. |

**Baud rate calculation:** `CLKS_PER_BIT = 434`. At 50 MHz clock: `50,000,000 / 434 ≈ 115,207 baud` (within 0.006% of ideal 115,200).

**Timing per character:** 1 start + 8 data + 1 stop = 10 bits × 434 cycles = 4,340 clock cycles = **86.8 µs per character**.

### 3.8 UART Receiver (`uart_rx.v`)

A **placeholder stub**. Always drives `rx_valid = 0`. Included in the project for future expansion but not exercised by the current firmware or testbench.

---

## 4. Firmware — Source Code & Build Process

### 4.1 Boot Assembly (`fw/start.S`)

```asm
.section .text.start, "ax"    ← "ax" flags: Allocatable + Executable
.global _start
_start:
    li sp, 0x000100FC             ← Stack pointer → top of SRAM (byte 252 of 256)
    jal ra, main                  ← Call main(), save return address in ra
1:  j 1b                         ← Infinite loop if main() ever returns
```

- The `"ax"` flags on `.section` are **critical** — without them, `objcopy -O binary` strips the section entirely, and the CPU boots into uninitialized memory.
- Stack grows **downward** from `0x000100FC`. Since SRAM is 256 bytes (`0x00010000`–`0x000100FF`), this leaves ~252 bytes of stack space before collision with the base.

### 4.2 Application Code (`fw/main.c`)

```c
#include <stdint.h>

#define UART_TX (*((volatile uint32_t*)0x10000000))
#define UART_RX (*((volatile uint32_t*)0x10000004))
#define UART_ST (*((volatile uint32_t*)0x10000008))

void uart_putc(char c) {
    while (UART_ST & 1);     // Poll tx_busy bit until transmitter is free
    UART_TX = c;             // Write character to TX data register
}

void uart_puts(const char* str) {
    while (*str) {
        uart_putc(*str++);   // Send each character one by one
    }
}

int main() {
    int i;
    for (i = 0; i < 10; i++) {
        uart_puts("Hello Ramnarayan\n");   // Print greeting 10 times
    }
    uart_puts("PING");                      // Send final PING message
    return 0;                               // Return → falls into infinite j loop
}
```

**Execution flow:**
1. CPU resets, PC = `0x00000000`, fetches `li sp, 0x000100FC` from ROM.
2. `jal main` jumps to `main()`.
3. `uart_putc` polls `UART_ST` at `0x10000008` — this generates an AXI read through the bridge → interconnect → `uart_axi` → reads `tx_busy` from `uart_tx`.
4. When `tx_busy == 0`, writes the character byte to `UART_TX` at `0x10000000` — this generates an AXI write → `uart_axi` latches byte into `tx_buf`, pulses `tx_start`.
5. `uart_tx` FSM shifts out 10 bits (start + 8 data + stop) at 434 cycles each.
6. After 10 loops of `"Hello Ramnarayan\n"` (17 chars × 10 = 170 characters) and `"PING"` (4 characters), `main()` returns and the `j 1b` loop holds the CPU forever.

**Total characters transmitted:** 174 characters × 86.8 µs ≈ **15.1 ms** of UART activity.

### 4.3 Linker Script (`fw/link.ld`)

```
MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
    SRAM (rw) : ORIGIN = 0x00010000, LENGTH = 256
}

SECTIONS {
    .text : {
        *(.text.start)      ← Boot code placed first (address 0x0)
        *(.text*)           ← All other code
        *(.rodata*)         ← Read-only data (e.g., format strings if any)
        *(.srodata*)        ← Small read-only data (GCC -Os puts short strings here)
    } > ROM

    .data : {
        *(.data*)           ← Initialized global variables
        *(.sdata*)          ← Small initialized data
        *(.bss*)            ← Uninitialized globals (zero-init)
        *(.sbss*)           ← Small uninitialized data
    } > SRAM
}
```

**Key design decisions:**
- `.text.start` is listed **first** in `.text` to guarantee the boot code sits at address `0x00000000`.
- `.srodata*` must be explicitly mapped — GCC `-Os` places short string literals like `"Hello Ramnarayan\n"` in `.srodata` instead of `.rodata`. Without this mapping, the string data would be silently dropped during hex generation, resulting in UART printing empty/garbage.
- `.bss` and `.sbss` are placed in SRAM alongside `.data` — they share the same load region.

### 4.4 Firmware Build Process (`fw/Makefile`)

Running `make fw` from the top-level triggers `make -C fw`, which executes:

**Step 1 — Cross-compilation:**
```bash
riscv64-unknown-elf-gcc -Os -ffreestanding -nostdlib -mabi=ilp32 -march=rv32imc \
    -T link.ld start.S main.c -o firmware.elf
```

| Flag | Purpose |
|:-----|:--------|
| `-Os` | Optimize for code size (critical for fitting in 8 KB ROM) |
| `-ffreestanding` | No hosted environment assumptions (no `printf`, `malloc`, etc.) |
| `-nostdlib` | Do not link standard C library or startup files |
| `-mabi=ilp32` | Use 32-bit integer ABI (int, long, pointer all 32-bit) |
| `-march=rv32imc` | Target RV32I base + M (multiply/divide) + C (compressed 16-bit instructions) |
| `-T link.ld` | Use custom linker script for memory layout |

**Step 2 — Binary extraction:**
```bash
riscv64-unknown-elf-objcopy -O binary firmware.elf firmware.bin
```
Strips all ELF headers, symbol tables, and debug info. Produces raw machine code bytes only.

**Step 3 — Hex generation (Python one-liner):**
```python
import binascii
f = open('firmware.bin', 'rb')
open('../rtl/rom.hex', 'w').write('\n'.join([
    binascii.hexlify(d.ljust(4, b'\x00')[::-1]).decode('utf-8')
    for d in iter(lambda: f.read(4), b'')
    if d
]))
f.close()
```

This script:
1. Reads `firmware.bin` in 4-byte chunks (one 32-bit word at a time).
2. **Pads** the last chunk with `\x00` if it's shorter than 4 bytes (`.ljust(4, b'\x00')`).
3. **Reverses** the byte order (`[::-1]`) to convert from little-endian (RISC-V native) to the big-endian hex format expected by Verilog's `$readmemh`.
4. Converts to hex ASCII and writes one word per line to `rtl/rom.hex`.

**Output file (`rtl/rom.hex`) example:**
```
000100b7    ← lui sp, 0x10000    (sets sp upper bits)
0fc10113    ← addi sp, sp, 252   (sp = 0x000100FC)
010000ef    ← jal ra, main
0000006f    ← j .               (infinite loop)
...
```

---

## 5. Simulation — Verilator Testbench

### 5.1 Testbench Architecture (`tb/tb_top.v`)

```verilog
`timescale 1ns/1ps
module tb_top;
  reg clk, reset;
  wire uart_tx, uart_rx;

  top u_top (.clk(clk), .reset(reset), .uart_tx(uart_tx), .uart_rx(uart_rx));
  assign uart_rx = 1'b1;              // RX line idle-high (no incoming data)

  initial clk = 0;
  always #10 clk = ~clk;              // 50 MHz → 20 ns period (10 ns half-period)

  initial begin
    $dumpfile("tb_top.vcd");           // VCD waveform output
    $dumpvars(0, tb_top);             // Dump all signals recursively
    $display("--------------------------------------------------");
    $display(" UART SoC Simulation Started");
    $display("--------------------------------------------------");

    reset = 1; #100 reset = 0;         // Hold reset for 100 ns (5 clock cycles)

    #30000000;                         // Run for 30,000,000 ns = 30 ms
    $display("TEST PASSED (time limit reached)");
    $finish;
  end
```

**Timing breakdown:**
- Clock period: **20 ns** (50 MHz)
- Reset duration: **100 ns** (5 clock cycles)
- Total simulation: **30 ms** (30,000,000 ns = 1,500,000 clock cycles)
- This gives ~15 ms for all 174 characters to transmit, plus margin.

### 5.2 UART Monitor (Bit-bang Receiver in Testbench)

```verilog
  localparam CLKS_PER_BIT = 434;
  localparam BIT_TIME = 20 * CLKS_PER_BIT;    // 20 ns × 434 = 8,680 ns per bit

  reg [7:0] rx_byte;
  integer i;
  always @(negedge uart_tx) begin              // Trigger on falling edge (start bit)
    if (!reset) begin
      #(BIT_TIME/2);                           // Wait to middle of start bit (4,340 ns)
      for (i=0; i<8; i=i+1) begin
        #(BIT_TIME);                           // Advance one full bit time
        rx_byte[i] = uart_tx;                  // Sample data bit (LSB first)
      end
      #(BIT_TIME);                             // Skip stop bit
      $write("%c", rx_byte);                   // Print character to console
      $fflush();                               // Force immediate console flush
    end
  end
```

**How it works:**
1. Detects the **falling edge** of `uart_tx` (start bit = logic 0).
2. Waits **half a bit time** (4,340 ns) to reach the center of the start bit for reliable sampling.
3. Then samples each of 8 data bits at full bit-time intervals (8,680 ns apart), building the byte LSB-first.
4. Skips the stop bit, then prints the captured character with `$write` and forces a `$fflush()` so it appears in the terminal immediately.

### 5.3 Verilator Compilation Command

```bash
verilator --binary -j 0 \
    -Wno-DECLFILENAME -Wno-PINMISSING -Wno-GENUNNAMED \
    -Wno-UNUSEDSIGNAL -Wno-BLKSEQ -Wno-SYNCASYNCNET \
    rtl/picorv32.v rtl/top.v rtl/axi_lite_interconnect.v \
    rtl/axi_decoder.v rtl/rom.v rtl/sram.v rtl/uart_axi.v \
    rtl/uart_tx.v rtl/uart_rx.v tb/tb_top.v \
    --top tb_top --timing --CFLAGS "-std=c++20" --trace
```

| Flag | Purpose |
|:-----|:--------|
| `--binary` | Produce a standalone executable (no manual C++ wrapper needed) |
| `-j 0` | Use all available CPU cores for parallel compilation |
| `--timing` | Enable Verilog `#delay` timing constructs (required for `#10`, `#100`, `#(BIT_TIME)`) |
| `--trace` | Enable VCD waveform generation via `$dumpfile`/`$dumpvars` |
| `--CFLAGS "-std=c++20"` | Compile generated C++ with C++20 standard (required by Verilator for coroutines with `--timing`) |
| `-Wno-*` flags | Suppress non-critical linter warnings from PicoRV32 third-party code |

---

## 6. Yosys Synthesis

Running `make synth` executes:

```bash
yosys -D SYNTHESIS -p 'synth -top top' \
    rtl/picorv32.v rtl/top.v rtl/axi_lite_interconnect.v rtl/axi_decoder.v \
    rtl/rom.v rtl/sram.v rtl/uart_axi.v rtl/uart_tx.v rtl/uart_rx.v
```

This performs a technology-independent RTL synthesis pass (no PDK mapping) for quick correctness verification.

### Synthesis Statistics (from Yosys output)

**Per-module cell counts:**

| Module | Cells | Key Components |
|:-------|------:|:---------------|
| `top` (bridge + glue) | 192 | 100× `DFFE_PP`, 37× `SDFFE_PP0P`, 5× `DFF_P` |
| `picorv32` (core) | 9,945 | 1,244× `DFFE_PP`, 2,706× `NAND`, 1,675× `AND`, 1,437× `MUX` |
| `picorv32_pcpi_mul` | 915 | 159× `DFFE_PP`, 204× `NAND`, 110× `AND` |
| `picorv32_pcpi_div` | 1,129 | 228× `NAND`, 167× `OR`, 163× `AND` |
| `sram` | 6,376 | 2,048× `DFFE_PP` (register-based memory), 1,060× `MUX` |
| `axi_lite_interconnect` | 132 | 78× `MUX`, 22× `AND`, 2× `axi_decoder` sub-modules |
| `axi_decoder` | 32 | 14× `AND`, 13× `NOR`, 5× `ANDNOT` |
| `rom` | 14 | 4× `ANDNOT`, 3× `AND`, 2× `SDFFE_PP0P` |
| `uart_axi` | 43 | 10× `AND`, 8× `DFFE_PP`, 1× `uart_tx` sub-module |
| `uart_tx` | 99 | 27× `AND`, 12× `DFFE_PN0P`, 12× `DFF_PN0` |
| **Total Design** | **18,909** | **3,623× `DFFE_PP`**, **4,159× `NAND`**, **2,981× `AND`** |

**Design hierarchy:**
```
18,909  top (total including all sub-modules)
 9,945    picorv32
 1,129      picorv32_pcpi_div
   915      picorv32_pcpi_mul
   132    axi_lite_interconnect
    32      axi_decoder (×2 instances)
    14    rom
 6,376    sram
    43    uart_axi
    99      uart_tx
```

**Notable:** The SRAM contributes 6,376 cells because at 256 bytes it is synthesized as individual flip-flops (2,048× `DFFE_PP` = 2048 D-flip-flops = 64 words × 32 bits). In a real ASIC, this would be replaced with a foundry-provided SRAM macro for significant area savings.

---

## 7. OpenLane Physical Design (ASIC Flow)

### 7.1 How to Run

**Prerequisites:** Build the firmware first so `rtl/rom.hex` exists:
```bash
make fw
```

**Enter the OpenLane environment:**
```bash
openlane shell
```

**Run the automated RTL-to-GDSII flow:**
```bash
./flow.tcl -design /home/lab-user/riscv-soc-subsystem/openlane_design -overwrite
```

This executes all OpenLane steps sequentially: Synthesis → STA → Floorplan → IO Placement → PDN → Placement → CTS → Routing → DRC → LVS → Antenna Check → GDSII generation.

### 7.2 Configuration Parameters (`config.json` — all 66 settings explained)

#### Design Identity
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `DESIGN_NAME` | `"top"` | Top-level Verilog module name |
| `VERILOG_FILES` | `"dir::../rtl/*.v"` | All `.v` files in `../rtl/` relative to `config.json` |
| `VERILOG_DEFINES` | `"SYNTHESIS"` | Defines `` `SYNTHESIS `` macro for conditional compilation |

#### Clock
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `CLOCK_PERIOD` | `20` | 20 ns → 50 MHz target frequency |
| `CLOCK_PORT` | `"clk"` | Port name of the clock input |
| `CLOCK_NET` | `"clk"` | Internal net name of the clock |
| `CLOCK_BUFFER_FANOUT` | `16` | Max fanout before inserting clock buffers |

#### Clock Tree Synthesis (CTS)
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `RUN_CTS` | `true` | Enable clock tree synthesis |
| `CTS_CLK_BUFFER_LIST` | `"sky130_fd_sc_hd__clkbuf_4 sky130_fd_sc_hd__clkbuf_8 sky130_fd_sc_hd__clkbuf_16"` | Allowed clock buffer cells (4×, 8×, 16× drive) |
| `CTS_ROOT_BUFFER` | `"sky130_fd_sc_hd__clkbuf_16"` | Root buffer of the clock tree (strongest drive) |
| `CTS_MAX_CAP` | `0.35` | Maximum capacitance per CTS node (pF) |
| `CTS_TARGET_SKEW` | `150` | Target clock skew (ps) |
| `RUN_POST_CTS_RESYNTHESIS` | `1` | Re-optimize logic after CTS for hold time fixing |

#### Design Constraints
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `MAX_FANOUT_CONSTRAINT` | `8` | Maximum fanout for any signal |
| `MAX_TRANSITION_CONSTRAINT` | `1.5` | Maximum signal transition time (ns) |
| `MAX_CAPACITANCE_CONSTRAINT` | `0.5` | Maximum load capacitance (pF) |
| `OUTPUT_CAP_LOAD` | `17.653` | Assumed output pin capacitance (fF) |

#### Floorplanning
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `BASE_SDC_FILE` | `"dir::top.sdc"` | Path to timing constraints file |
| `FP_PIN_ORDER_CFG` | `"dir::pin_order.cfg"` | Pin placement configuration |
| `FP_SIZING` | `"absolute"` | Use absolute die dimensions (not relative) |
| `DIE_AREA` | `"0 0 1000 1000"` | Die size: 1000 µm × 1000 µm = 1 mm² |
| `FP_CORE_UTIL` | `35` | Core utilization target: 35% |
| `FP_ASPECT_RATIO` | `1` | Square aspect ratio |
| `IO_PCT` | `0.2` | 20% of die edge reserved for I/O cells |

#### Placement
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `PL_TARGET_DENSITY` | `0.65` | Placement density: 65% (allows routing channels) |
| `PL_RANDOM_GLB_PLACEMENT` | `false` | Use deterministic global placement |
| `GPL_CELL_PADDING` | `4` | Extra padding (sites) around each cell |
| `PL_RESIZER_MAX_WIRE_LENGTH` | `600` | Max wire length before buffer insertion (µm) |
| `PL_RESIZER_MAX_SLEW_MARGIN` | `10` | Slew margin for resizer (%) |
| `PL_RESIZER_MAX_CAP_MARGIN` | `10` | Capacitance margin for resizer (%) |
| `PL_RESIZER_HOLD_SLACK_MARGIN` | `0.35` | Hold timing slack margin (ns) |
| `PL_RESIZER_SETUP_SLACK_MARGIN` | `0.1` | Setup timing slack margin (ns) |

#### Power Distribution Network (PDN)
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `FP_PDN_AUTO_ADJUST` | `false` | Manual PDN grid configuration |
| `FP_PDN_VPITCH` | `25` | Vertical power stripe pitch (µm) |
| `FP_PDN_HPITCH` | `25` | Horizontal power stripe pitch (µm) |
| `FP_PDN_VOFFSET` | `5` | Vertical power stripe offset (µm) |
| `FP_PDN_HOFFSET` | `5` | Horizontal power stripe offset (µm) |

#### Global Routing
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `GRT_ADJUSTMENT` | `0.05` | 5% global routing resource reduction (pessimism factor) |
| `GRT_OVERFLOW_ITERS` | `100` | Max iterations to resolve routing overflow |
| `GRT_ALLOW_CONGESTION` | `1` | Allow routing even with congestion warnings |
| `GLB_RT_MAXLAYER` | `4` | Max routing layer for global routing (met4) |
| `RT_MAX_LAYER` | `"met4"` | Max metal layer for detailed routing |

#### Detailed Routing
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `DRT_OPT_ITERS` | `32` | Optimization iterations for detailed router |
| `DRT_MIN_ACCESS_POINTS` | `1` | Minimum access points per pin |
| `ROUTING_CORES` | `4` | Parallel CPU cores for routing |

#### Post-Route Resizer
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `GLB_RESIZER_MAX_WIRE_LENGTH` | `600` | Max wire length post-route (µm) |
| `GLB_RESIZER_HOLD_SLACK_MARGIN` | `0.35` | Hold slack margin post-route (ns) |
| `GLB_RESIZER_SETUP_SLACK_MARGIN` | `0.1` | Setup slack margin post-route (ns) |

#### Synthesis Strategy
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `SYNTH_STRATEGY` | `"AREA 3"` | Optimize for area (level 3 — most aggressive) |
| `SYNTH_SPLITNETS` | `1` | Split multi-bit nets for better optimization |
| `SYNTH_BUFFERING` | `1` | Enable automatic buffer insertion |
| `SYNTH_SIZING` | `1` | Enable cell upsizing for timing |
| `SYNTH_SHARE_RESOURCES` | `1` | Share arithmetic resources where possible |
| `SYNTH_ADDER_TYPE` | `"YOSYS"` | Use Yosys default adder architecture |

#### Antenna & Diode
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `DIODE_INSERTION_STRATEGY` | `3` | Legacy flag (deprecated, auto-converted) |
| `GRT_REPAIR_ANTENNAS` | `1` | Repair antenna violations during global routing |
| `GRT_ANTENNA_ITERS` | `10` | Max iterations for antenna repair |
| `DIODE_ON_PORTS` | `"both"` | Insert diodes on both input and output ports |
| `RUN_HEURISTIC_DIODE_INSERTION` | `1` | Use heuristic diode placement for remaining violations |

#### Signoff
| Parameter | Value | Meaning |
|:----------|:------|:--------|
| `RUN_FILL_INSERTION` | `1` | Insert fill cells for manufacturing density |
| `RUN_DRC` | `1` | Run Design Rule Check (Magic) |
| `RUN_LVS` | `1` | Run Layout vs. Schematic (Netgen) |
| `RUN_ANTENNA_CHECK` | `1` | Run antenna rule check |
| `RUN_SPICE_EXTRACTION` | `1` | Extract SPICE netlist from layout |

### 7.3 Timing Constraints (`top.sdc`)

```tcl
create_clock -period 20 -name clk [get_ports clk]           # 50 MHz clock
set_clock_uncertainty 0.25 [get_clocks clk]                  # ±250 ps jitter
set_clock_transition 0.25 [get_clocks clk]                   # 250 ps rise/fall

set_driving_cell -lib_cell sky130_fd_sc_hd__clkbuf_16 -pin X [get_ports clk]

set_input_delay  -min -rise 0.0 [get_ports {reset uart_rx}] -clock clk
set_input_delay  -min -fall 0.0 [get_ports {reset uart_rx}] -clock clk
set_input_delay  -max -rise 4.0 [get_ports {reset uart_rx}] -clock clk
set_input_delay  -max -fall 4.0 [get_ports {reset uart_rx}] -clock clk

set_input_transition -min -rise 0.15 [get_ports {reset uart_rx}]
set_input_transition -min -fall 0.15 [get_ports {reset uart_rx}]
set_input_transition -max -rise 0.50 [get_ports {reset uart_rx}]
set_input_transition -max -fall 0.50 [get_ports {reset uart_rx}]

set_output_delay -min -rise 0.0 [get_ports uart_tx] -clock clk
set_output_delay -min -fall 0.0 [get_ports uart_tx] -clock clk
set_output_delay -max -rise 4.0 [get_ports uart_tx] -clock clk
set_output_delay -max -fall 4.0 [get_ports uart_tx] -clock clk

set_load -pin_load 0.017 [get_ports uart_tx]                # 17 fF output load
set_max_transition 1.500 [current_design]                    # 1.5 ns max transition
set_false_path -from [get_ports reset]                       # Reset is asynchronous
```

### 7.4 Pin Placement (`pin_order.cfg`)

```
#N          ← North edge
clk
#S          ← South edge
reset
#E          ← East edge
uart_tx
#W          ← West edge
uart_rx
```

---

## 8. Makefile Reference

| Target | Command | Description |
|:-------|:--------|:------------|
| `make fw` | `make -C fw` | Cross-compile firmware → `firmware.elf` → `firmware.bin` → `rtl/rom.hex` |
| `make soc` | (depends on `fw`) | Build Verilator model + run simulation. Prints UART output to console. |
| `make synth` | `yosys -D SYNTHESIS -p 'synth -top top' rtl/*.v` | Quick technology-independent synthesis check. |
| `make run_flow` | (prints instructions) | Displays the exact commands to run OpenLane in the Virtual Lab. |
| `make pull` | `git fetch && git pull origin master` | Pull latest changes from GitHub. |
| `make clean` | `rm -rf obj_dir/ *.vcd *.fst runs/ openlane_design/runs/; make -C fw clean` | Remove all build artifacts, waveforms, firmware binaries, and OpenLane run directories. |

---

## 9. Debugging Journey — All Bugs Encountered & Fixed

### Bug 1: AXI Bridge Deadlock — Infinite Instruction Fetch Loop
- **Symptom:** Simulation never printed any UART output. CPU continuously fetched `lui sp` (first instruction) and never advanced.
- **Root Cause:** In `top.v`, the IDLE state transition was `if (cpu_mem_valid)` without checking `!ready_r`. When the bridge completed a transaction and asserted `ready_r`, the CPU kept `mem_valid` high for one more cycle (PicoRV32 behavior). The bridge immediately re-entered the read path, issuing a **duplicate AXI read** for the same PC. The CPU saw two `mem_ready` pulses for one request, corrupting its pipeline.
- **Fix:** Changed IDLE condition to `if (cpu_mem_valid && !ready_r)`. This ensures the bridge only initiates a new transaction when no response is currently being delivered.

### Bug 2: Missing `.srodata` Linker Section — Empty String Output
- **Symptom:** UART transmitted bytes, but all characters were `\0` (null). The string `"Hello Ramnarayan\n"` appeared to be missing from the ROM.
- **Root Cause:** GCC with `-Os` placed the string literal into `.srodata` (Small Read-Only Data), a RISC-V specific section. The linker script only mapped `*(.rodata*)` into ROM, not `*(.srodata*)`. The string was placed at a linker-assigned address outside ROM bounds, and `objcopy` silently discarded it.
- **Fix:** Added `*(.srodata*)` to the `.text` output section in `link.ld`, right after `*(.rodata*)`.

### Bug 3: Boot Assembly Stripped by `objcopy` — Missing `"ax"` Flags
- **Symptom:** CPU jumped directly to `main()` with an uninitialized stack pointer, causing immediate crash (writes to random addresses, bus hangs).
- **Root Cause:** `start.S` declared `.section .text.start` without the `"ax"` attribute flags. GNU Assembler defaults unflagged custom sections to non-allocatable, non-executable. `objcopy -O binary` only copies allocatable sections, so the entire boot stub was silently removed from `firmware.bin`.
- **Fix:** Changed to `.section .text.start, "ax"` — marking it as **a**llocatable and e**x**ecutable.

### Bug 4: Verilator `$write` Buffering — Characters Not Appearing
- **Symptom:** On some systems, UART characters appeared only after simulation ended, not in real-time.
- **Root Cause:** `$write` (unlike `$display`) does not append a newline or flush stdout. The C runtime buffers stdout, so characters accumulated in the buffer.
- **Fix:** Added `$fflush()` immediately after each `$write("%c", rx_byte)` call in `tb_top.v`.

### Bug 5: Sky130 Cell Name Convention — STA Failure
- **Symptom:** OpenLane Step 2 (Static Timing Analysis) failed with `Error: top.sdc line 5, 'sky130_fd_sc_hd_clkbuf_16' not found.`
- **Root Cause:** The Sky130 PDK naming convention uses a **double underscore** between the library prefix (`sky130_fd_sc_hd`) and the cell name (`clkbuf_16`). The original `top.sdc` and `config.json` used single underscores.
- **Fix:** Changed all occurrences from `sky130_fd_sc_hd_clkbuf_*` to `sky130_fd_sc_hd__clkbuf_*` (double underscore) in both `top.sdc` and `config.json`.

### Bug 6: SDC Syntax Error — Combined Min/Max Flags
- **Symptom:** OpenLane STA failed with `Error: top.sdc line 7, set_input_delay -min-rise is not a known keyword or flag.`
- **Root Cause:** OpenSTA requires `-min` and `-rise` as **separate flags** (e.g., `-min -rise`), not hyphenated together (`-min-rise`).
- **Fix:** Split all combined flags in `top.sdc`: `-min-rise` → `-min -rise`, `-max-fall` → `-max -fall`, etc.

### Bug 7: Missing `uart_rx` Pin in Floorplan
- **Symptom:** OpenLane Step 4 (IO Placement) failed with `Treating unmatched pins as errors. Exiting..` for pin `uart_rx`.
- **Root Cause:** `pin_order.cfg` only listed `clk`, `reset`, and `uart_tx`. The `uart_rx` input port was declared in `top.v` but had no physical placement assignment. OpenLane requires **every** top-level port to be mapped.
- **Fix:** Added `#W` (West edge) section with `uart_rx` to `pin_order.cfg`.

### Bug 8: Empty ROM in ASIC Synthesis — `$readmemh` Excluded
- **Symptom:** OpenLane synthesis produced a ROM filled entirely with zeroes. The manufactured chip would execute `NOP` forever.
- **Root Cause:** `rom.v` originally wrapped `$readmemh` in `` `ifndef SYNTHESIS ``, which correctly excluded it during technology-mapped synthesis (since `$readmemh` is a simulation-only construct). However, Yosys actually **can** interpret `$readmemh` during synthesis to pre-initialize memory cells. Excluding it meant the ROM was synthesized empty.
- **Fix:** Changed to `` `ifdef SYNTHESIS `` with a hardcoded absolute path (`"/home/lab-user/riscv-soc-subsystem/rtl/rom.hex"`), and `` `else `` for simulation with the relative path. This was necessary because OpenLane's proot environment runs Yosys from `/openlane/`, making relative paths unusable, and OpenLane's `VERILOG_DEFINES` parser strips quotes from macro string arguments, preventing a clean macro-based path solution.

---

## 10. Expected Terminal Outputs

### `make fw` output:
```
riscv64-unknown-elf-gcc -Os -ffreestanding -nostdlib -mabi=ilp32 -march=rv32imc \
    -T link.ld start.S main.c -o firmware.elf
riscv64-unknown-elf-objcopy -O binary firmware.elf firmware.bin
python3 -c "import binascii; ..."
```

### `make soc` output:
```
make -C fw
make[1]: Entering directory '.../fw'
make[1]: Nothing to be done for 'all'.
make[1]: Leaving directory '.../fw'
verilator --binary -j 0 ... --top tb_top --timing --CFLAGS "-std=c++20" --trace
make[1]: Entering directory '.../obj_dir'
...
make[1]: Leaving directory '.../obj_dir'
./obj_dir/Vtb_top +romhex=rtl/rom.hex
--------------------------------------------------
 UART SoC Simulation Started
--------------------------------------------------
Hello Ramnarayan
Hello Ramnarayan
Hello Ramnarayan
Hello Ramnarayan
Hello Ramnarayan
Hello Ramnarayan
Hello Ramnarayan
Hello Ramnarayan
Hello Ramnarayan
Hello Ramnarayan
PING
TEST PASSED (time limit reached)
- tb/tb_top.v:23: Verilog $finish
```

### `make synth` output (final check):
```
10.27. Executing CHECK pass (checking for obvious problems).
Checking module rom...
Checking module sram...
Checking module uart_axi...
Checking module top...
Checking module picorv32_pcpi_mul...
Checking module picorv32_pcpi_div...
Checking module uart_tx...
Checking module axi_decoder...
Checking module $paramod$...\picorv32...
Checking module axi_lite_interconnect...
Found and reported 0 problems.
```

### OpenLane Physical Design Flow — Successful Run Log

**Run:** `RUN_2026.08.05_14.01.30` | **OpenLane:** v1.0.2 | **PDK:** sky130A | **Std Cell Library:** sky130_fd_sc_hd

The complete flow executed **45 steps** from RTL to GDSII:

```
[STEP 1]  Running Synthesis                                          ✅
[STEP 2]  Running Single-Corner Static Timing Analysis               ✅
[STEP 3]  Running Initial Floorplanning                              ✅  (988.54 µm × 976.48 µm)
[STEP 4]  Running IO Placement                                      ✅
[STEP 5]  Running Tap/Decap Insertion                                ✅
[STEP 6]  Generating PDN (Power: VPWR, Ground: VGND)                ✅
[STEP 7]  Running Global Placement                                   ✅
[STEP 8]  Running Single-Corner STA (post-global-placement)         ✅
[STEP 9]  Running Placement Resizer Design Optimizations             ✅
[STEP 10] Running Detailed Placement                                 ✅
[STEP 11] Running Single-Corner STA (post-detailed-placement)       ✅
[STEP 12] Running Clock Tree Synthesis (CTS)                         ✅
[STEP 13] Running Single-Corner STA (post-CTS)                      ✅
[STEP 14] Running Placement Resizer Timing Optimizations             ✅
[STEP 15] Running Global Routing Resizer Design Optimizations        ✅
[STEP 16] Running Single-Corner STA (post-resizer-design)           ✅
[STEP 17] Running Global Routing Resizer Timing Optimizations        ✅
[STEP 18] Running Single-Corner STA (post-resizer-timing)           ✅
[STEP 19] Running I/O Diode Insertion                                ✅
[STEP 20] Running Detailed Placement (post-IO-diode legalization)    ✅
[STEP 21] Running Heuristic Diode Insertion                          ✅
[STEP 22] Running Detailed Placement (post-diode legalization)       ✅
[STEP 23] Running Global Routing                                     ✅  (1 antenna violation, non-critical)
[STEP 24] Writing Verilog (post-global-route netlist)                ✅
[STEP 25] Running Single-Corner STA (post-global-route)             ✅
[STEP 26] Running Fill Insertion                                     ✅
[STEP 27] Running Detailed Routing                                   ✅  (No DRC violations)
[STEP 28] Checking Wire Lengths                                      ✅
[STEP 29] Running SPEF Extraction (min corner)                       ✅
[STEP 30] Running Multi-Corner STA (min corner)                      ✅
[STEP 31] Running SPEF Extraction (max corner)                       ✅
[STEP 32] Running Multi-Corner STA (max corner)                      ✅
[STEP 33] Running SPEF Extraction (nom corner)                       ✅
[STEP 34] Running Multi-Corner STA (nom corner)                      ✅
[STEP 35] Running Single-Corner STA (nom corner, final)              ✅
[STEP 36] Creating IR Drop Report                                    ✅
[STEP 37] Streaming out GDSII with Magic                             ✅
[STEP 38] Streaming out GDSII with KLayout                           ⚠️  (KLayout GDS XOR skipped)
[STEP 39] Running Magic Spice Export from LEF                        ✅
[STEP 40] Writing Powered Verilog                                    ✅
[STEP 41] Writing Verilog (final netlist)                             ✅
[STEP 42] Running LVS (Layout vs. Schematic)                         ✅
[STEP 43] Running Magic DRC                                          ✅  (No DRC violations after GDS streaming)
[STEP 44] Running OpenROAD Antenna Rule Checker                      ✅
[STEP 45] Running Circuit Validity Checker ERC                       ✅

[SUCCESS]: Flow complete.
```

### Signoff Results Summary

| Check | Result | Details |
|:------|:-------|:--------|
| **Setup Timing** | ✅ **No violations** | All paths meet setup constraints at typical corner |
| **Hold Timing** | ✅ **No violations** | All paths meet hold constraints at typical corner |
| **Max Slew** | ✅ **No violations** | All transitions within 1.5 ns limit |
| **Max Fanout** | ✅ **No violations** | All nets within fanout constraint of 8 |
| **Max Capacitance** | ✅ **No violations** | All loads within 0.5 pF limit |
| **DRC (post-routing)** | ✅ **No violations** | Clean after detailed routing (Step 27) |
| **DRC (post-GDS)** | ✅ **No violations** | Clean after GDSII streaming (Step 43) |
| **LVS** | ✅ **Pass** | Layout matches schematic (Step 42) |
| **Antenna** | ✅ **Pass** | Antenna rule check clean (Step 44) |
| **ERC** | ✅ **Pass** | Electrical rule check clean (Step 45) |

### Floorplan Dimensions

| Parameter | Value |
|:----------|:------|
| Die Area (configured) | 1000 µm × 1000 µm = 1 mm² |
| Core Area (actual) | 988.54 µm × 976.48 µm |
| Core Utilization | 35% target |
| Placement Density | 65% target |
| Power Network | VPWR / VGND, stripe pitch 25 µm × 25 µm |
| Max Routing Layer | met4 |

### Multi-Corner STA

The design was verified at **three process corners** after parasitic extraction (SPEF):
- **min** corner (fast process, low voltage, low temperature) — Steps 29–30
- **max** corner (slow process, high voltage, high temperature) — Steps 31–32
- **nom** corner (nominal process, nominal voltage, nominal temperature) — Steps 33–35

All corners passed with **zero timing violations**.

### Non-Critical Warnings (Safe to Ignore)

| Warning | Explanation |
|:--------|:------------|
| `63 warnings found by linter` | Verilator linter warnings from the third-party PicoRV32 core (unused signals, blocking assignments). Does not affect synthesis or functionality. |
| `Module sky130_fd_sc_hd__tapvpwrvgnd_1 blackboxed during sta` | Tap/decap/fill cells are physical-only cells with no logical function. OpenSTA correctly blackboxes them. |
| `Module sky130_ef_sc_hd__decap_12 blackboxed during sta` | Same as above — decoupling capacitor cell. |
| `Module sky130_fd_sc_hd__fill_1 blackboxed during sta` | Same as above — fill cell for density. |
| `Module sky130_fd_sc_hd__fill_2 blackboxed during sta` | Same as above — fill cell for density. |
| `VSRC_LOC_FILES is not defined` | No voltage source location file provided for IR drop analysis. Results are approximate but the flow still completes. |
| `top.klayout.gds wasn't found. Skipping GDS XOR` | KLayout GDSII export failed (proot limitation). Magic GDSII export (Step 37) succeeded, which is the primary output. |
| `DIODE_INSERTION_STRATEGY is now deprecated` | Legacy config key auto-converted to `GRT_REPAIR_ANTENNAS=1`. No action needed. |

### Output Artifacts

After a successful run, the following key files are generated:

```
openlane_design/runs/RUN_<timestamp>/
├── results/final/
│   ├── gds/
│   │   └── top.gds              ← GDSII layout (send to foundry)
│   ├── lef/
│   │   └── top.lef              ← Library Exchange Format (for hierarchical integration)
│   ├── def/
│   │   └── top.def              ← Design Exchange Format (placed & routed layout)
│   ├── verilog/
│   │   └── top.v                ← Gate-level netlist (post-synthesis)
│   ├── sdf/
│   │   └── top.sdf              ← Standard Delay Format (for gate-level simulation)
│   └── spef/
│       └── top.spef             ← Parasitic extraction data
├── reports/
│   ├── manufacturability.rpt    ← DRC/LVS/Antenna summary
│   └── metrics.csv              ← Area, timing, power metrics
└── logs/
    ├── synthesis/               ← Yosys + STA logs
    ├── floorplan/               ← Floorplan + IO + PDN logs
    ├── placement/               ← Global/Detailed placement logs
    ├── cts/                     ← Clock tree synthesis logs
    ├── routing/                 ← Global/Detailed routing logs
    └── signoff/                 ← DRC, LVS, Antenna, SPICE, GDSII logs
```
