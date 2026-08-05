# RISC-V SoC Subsystem Design, Verification, and Physical Design (RTL-to-GDSII)

This repository contains the complete design, firmware, testbenches, and physical design configurations for a System-on-Chip (SoC) based on the PicoRV32 core. It implements a 32-bit AXI4-Lite interconnect bridging the CPU to ROM, SRAM, and UART peripherals, and is fully configured for the OpenLane ASIC physical design flow targeting the SkyWater 130nm (sky130A) PDK.

---

## 1. System Architecture & Memory Map

The SoC is built around the **PicoRV32** processor core, implementing the RV32IMC instruction set (Integer, Multiply/Divide, and Compressed instructions).

### Memory Map Overview
| Peripheral | Base Address | Size/Width | Description |
| :--- | :--- | :--- | :--- |
| **Boot ROM** | `0x0000_0000` | 8 KB (2048 x 32-bit) | Contains startup code (`start.S`) and main firmware (`main.c`). Ignored on write. |
| **SRAM** | `0x0001_0000` | 256 Bytes (64 x 32-bit)| Scratchpad memory for variables and the stack. Stack initialized at `0x0001_00FC`. |
| **UART (TX)** | `0x1000_0000` | 8-bit Write | Writing to offset `0x00` queues a character into the UART Transmit buffer. |
| **UART (Status)**| `0x1000_0008` | 1-bit Read | Reading from offset `0x08` returns the `tx_busy` flag (1 = Busy, 0 = Ready). |

### Interconnect
The system utilizes a **Custom AXI4-Lite Interconnect** with a Single Master (the CPU AXI Bridge) and 3 Slaves (ROM, SRAM, UART). The CPU bridge implements an FSM to translate native PicoRV32 memory interface signals (`mem_valid`, `mem_ready`, `mem_wstrb`) into standard AXI4-Lite read/write channels (`AW`, `W`, `B`, `AR`, `R`).

---

## 2. Firmware Build Process (`make fw`)

The firmware is bare-metal C and Assembly. Running `make fw` triggers the following internal operations:

1. **Compilation:** The RISC-V GCC cross-compiler (`riscv64-unknown-elf-gcc` or `riscv32-unknown-elf-gcc`) compiles `main.c` and `start.S`.
   * **Flags Used:** `-Os` (optimize for size), `-ffreestanding` (no standard OS environment), `-nostdlib` (do not link C standard library), `-mabi=ilp32 -march=rv32imc` (target 32-bit RISC-V with IMC extensions).
2. **Linking:** The custom linker script (`link.ld`) is invoked via `-T link.ld`. It places `.text.start` exactly at `0x0000_0000` so the CPU fetches the boot code on reset. It maps standard sections (`.text`, `.rodata`, `.srodata`) into the ROM block, and maps read-write sections (`.data`, `.sdata`, `.bss`) into the SRAM block starting at `0x0001_0000`.
3. **Binary Extraction:** `riscv64-unknown-elf-objcopy -O binary` strips out ELF metadata, leaving raw machine code (`firmware.bin`).
4. **Hex Generation:** A Python script reads the raw binary and formats it into a hexadecimal string array (`rtl/rom.hex`), padding bytes to match the 32-bit width of the Verilog `$readmemh` instruction.

---

## 3. RTL Simulation (`make soc`)

To verify the logic, the SoC is simulated using **Verilator**. Running `make soc` executes the following:

1. **Dependency Check:** Make automatically calls `make fw` to ensure `rtl/rom.hex` is up-to-date.
2. **Verilation:** The Verilator compiler parses the Verilog files, optimizing them into a high-performance C++ cycle-accurate model.
   * **Flags Used:** `--timing` (enables Verilog delay support), `--trace` (enables VCD waveform dumping), and various `-Wno-*` flags to suppress generic linter warnings on the PicoRV32 core.
3. **Compilation:** `g++` compiles the Verilated C++ model into an executable binary (`Vtb_top`).
4. **Execution:** The executable is launched with `./obj_dir/Vtb_top +romhex=rtl/rom.hex`. The testbench (`tb/tb_top.v`) loads the hex file into the ROM array and pulses the reset line.
5. **Expected Result:** The CPU boots, initializes the stack, and executes `main()`. A Verilog monitor block captures UART TX toggles and prints "Hello Ramnarayan" continuously to the terminal.

---

## 4. ASIC Physical Design (OpenLane)

The design is fully prepared for tape-out using the OpenLane physical design flow targeting the **SkyWater 130nm** PDK. 

### Running the Flow
Inside an OpenLane environment, you can generate the GDSII layout by executing:
```bash
./flow.tcl -design /path/to/riscv-soc-subsystem/openlane_design -overwrite
```

### Important Configuration Numbers (`config.json`)
* **Clock Constraints:** The target `CLOCK_PERIOD` is **20 ns (50 MHz)** on the `clk` port.
* **Die Area:** Fixed absolute sizing `DIE_AREA` of **1000 µm x 1000 µm** (1 sq. mm).
* **Utilization:** `FP_CORE_UTIL` is set to **35%**, and `PL_TARGET_DENSITY` is **0.65** (65%), providing breathing room for the moderately large PicoRV32 core to route without severe congestion.
* **CTS (Clock Tree Synthesis):** Max Fanout is **8**, Max Transition is **1.5 ns**, Max Capacitance is **0.5 pF**. Clock buffers used are standard Sky130 cells (`sky130_fd_sc_hd__clkbuf_4`, `8`, and `16`).
* **I/O Pin Placement:** Handled by `pin_order.cfg` which assigns pins to specific macro edges (North: `clk`, South: `reset`, East: `uart_tx`, West: `uart_rx`).

### Synthesis Results (`make synth` or OpenLane Step 1)
When Yosys synthesizes the design (`yosys -D SYNTHESIS`), the approximate gate count is:
* Total SoC Cells: **~18,909**
* PicoRV32 Core Cells: **~9,945** (incorporating the heavy DIV and MUL coprocessor blocks)
* SRAM Array Cells: **~6,376** (Synthesized as an array of D Flip-Flops since it's only 256 bytes)

---

## 5. Debugging Journey & Fixes

During the development and integration of this SoC, several deeply nested bugs spanning software, RTL, and Physical Design were encountered and resolved. These are documented here for educational purposes:

### 1. Custom AXI Bridge Deadlock (`top.v`)
* **Bug:** The custom AXI Bridge state machine was originally issuing duplicate read transactions for the same address if the CPU held `cpu_mem_valid` high while waiting for `ready_r`. This trapped the CPU in an infinite loop, constantly fetching the first instruction (`lui sp`) and never advancing the program counter. 
* **Fix:** A check (`!ready_r`) was added to the `IDLE` state transition to ensure it only issues a new AXI request if a previous one isn't currently finishing.

### 2. Missing Linker Sections (`.srodata`)
* **Bug:** RISC-V GCC compiled the string literal `"Hello Ramnarayan\n"` into the `.srodata` (Small Read-Only Data) section due to `-Os` optimizations. Because `link.ld` did not explicitly map `*(.srodata*)` into the `ROM`, the linker placed it outside of ROM bounds. It was silently skipped during hex generation, resulting in an empty string over UART. 
* **Fix:** The linker script was updated to properly map all standard RISC-V data sections.

### 3. Missing `"ax"` Flags in Boot Assembly
* **Bug:** The boot code (`start.S`) was defined with a custom section `.section .text.start`. Without explicitly passing the `"ax"` (Allocatable, Executable) flags, `GNU Assembler` treated it as non-allocatable data, and `objcopy` stripped it from the final binary. The CPU booted directly into `main()`, which immediately crashed on an uninitialized stack.
* **Fix:** Added `"ax"` flags to the assembly section directive.

### 4. Empty ROM during OpenLane Synthesis
* **Bug:** In `rom.v`, the `$readmemh` instruction was wrapped in an `` `ifndef SYNTHESIS `` block. During OpenLane execution, Yosys completely ignored the firmware, synthesizing a completely empty 8KB ROM filled with zeroes. This would result in a manufactured chip that did nothing.
* **Fix:** The `ifndef SYNTHESIS` block was replaced. To bypass a bug in OpenLane's `VERILOG_DEFINES` parsing (which stripped string quotes from macro arguments), the absolute path to the hex file was strictly hardcoded into the Verilog using an `` `ifdef SYNTHESIS `` block specifically for the physical design run.

### 5. Sky130 Standard Cell Naming Convensions (STA Error)
* **Bug:** OpenLane failed during Step 2 (Static Timing Analysis) complaining that cell `sky130_fd_sc_hd_clkbuf_16` could not be found.
* **Fix:** Corrected the original cell definitions in `top.sdc` and `config.json`. The Sky130 PDK strictly requires a **double underscore** between the library prefix and the cell name (e.g., `sky130_fd_sc_hd__clkbuf_16`). 

### 6. Missing I/O Pin in Floorplanning
* **Bug:** OpenLane failed during Step 4 (Floorplanning: `io_place.py`) because `uart_rx` was declared as an input port in Verilog but was missing from `pin_order.cfg`. OpenLane enforces that every top-level port must be placed.
* **Fix:** Appended `uart_rx` to the West (`#W`) side of the chip in `pin_order.cfg`.
