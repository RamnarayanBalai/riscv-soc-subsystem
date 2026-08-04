# RISC-V SoC Subsystem Design & Verification

This repository contains the design, firmware, testbenches, and physical design configurations for a complete RISC-V System-on-Chip (SoC) based on the PicoRV32 core. It implements a 32-bit AXI4-Lite interconnect bridging the CPU to ROM, SRAM, and UART peripherals.

## System Architecture

The SoC is built around the **PicoRV32** processor core, implementing the RV32IMC instruction set. 

*   **Processor:** PicoRV32 (RV32IMC)
*   **Interconnect:** Custom AXI4-Lite Interconnect with 1 Master (Bridge) and 3 Slaves.
*   **Peripherals:**
    *   **ROM (8KB):** Boot ROM containing the startup code and firmware. Base Address: `0x00000000`
    *   **SRAM (256 Bytes):** Scratchpad memory for variables and stack. Base Address: `0x00010000`
    *   **UART:** Simple transmit/receive interface. Base Address: `0x10000000`

## Repository Layout

```text
riscv-soc-subsystem/
├── rtl/                   # Verilog source files (PicoRV32, AXI Bridge, Peripherals)
├── tb/                    # Testbenches for module-level and system-level verification
├── fw/                    # C/Assembly firmware and linker script
├── docs/                  # Architecture and memory map documentation
├── openlane_design/       # OpenLane configuration for ASIC implementation
├── Makefile               # Top-level makefile for compilation and simulation
└── README.md              # This file
```

## Prerequisites

To compile the firmware and simulate the RTL design, you need the following tools installed on your Linux environment:

1.  **RISC-V GNU Compiler Toolchain** (`riscv32-unknown-elf-gcc`)
2.  **Verilator** (for fast, cycle-accurate C++ simulation)
3.  **Yosys** (for RTL synthesis checks)
4.  **Python 3** (for hex file generation)
5.  *(Optional)* **OpenLane** (for physical design)

## Building and Running

The project includes a top-level `Makefile` to automate the build process.

### 1. Build the Firmware

Compile the C code (`fw/main.c`) and assembly startup (`fw/start.S`) into a bare-metal binary, then convert it to a `.hex` file for the ROM.

```bash
make fw
```
*The firmware greets the user with "Hello Ramnarayan" and echoes a "PING" message over UART.*

### 2. Simulate the SoC

Compile the Verilog RTL along with the PicoRV32 core using Verilator, and run the testbench (`tb/tb_top.v`). The testbench will load the `rom.hex` generated in the previous step and start execution.

```bash
make soc
```
*This command automatically builds the firmware first if it's outdated.*

### 3. Synthesis Check

Run a quick synthesis check using Yosys to verify that the RTL is synthesizable and contains no logic loops.

```bash
make synth
```

## Firmware Details

The firmware utilizes a custom linker script (`fw/link.ld`) to map `.text` sections to the ROM (starting at `0x0000_0000`) and `.data`/`.bss` sections to the SRAM (starting at `0x0001_0000`). The stack pointer is initialized to the top of the SRAM (`0x0001_00FC`).

## ASIC Physical Design

The `openlane_design/config.json` file contains the initial floorplanning and placement parameters required to run this design through the OpenLane flow (target: SkyWater 130nm PDK).
