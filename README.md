# Edge-AI RISC-V SoC with 8×8 Weight-Stationary Systolic Array Accelerator

[![Target FPGA](https://img.shields.io/badge/FPGA-AMD%2F%20Xilinx%20Zynq--7000%20XC7Z020--CLG484--1-blue.svg)](#2-complete-system-specifications)
[![Board](https://img.shields.io/badge/Platform-Digilent%20ZedBoard%20(Rev%20D%2FE%2FF)-green.svg)](#2-complete-system-specifications)
[![ISA](https://img.shields.io/badge/ISA-RISC--V%20RV32IM%20(PicoRV32)-orange.svg)](#5-core-architecture-picorv32-rv32im)
[![Clock Domain](https://img.shields.io/badge/Clock-100.0%20MHz%20(Single%20PL%20Domain)-purple.svg)](#12-clock-distribution--reset-subsystem)
[![Static Timing](https://img.shields.io/badge/Static%20Timing-CLOSED%20(WNS%20%2B0.943%20ns)-success.svg)](#14-physical-implementation--timing-closure-sign-off)
[![Bit-Exact Match](https://img.shields.io/badge/Golden%20Model-100%25%20Bit--Exact%20Match-brightgreen.svg)](#11-edge-ai-quantized-cnn-inference-architecture)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

---

## Table of Contents
1. [Executive Summary & Architectural Scope](#1-executive-summary--architectural-scope)
2. [Complete System Specifications](#2-complete-system-specifications)
3. [Top-Level Hardware Architecture](#3-top-level-hardware-architecture)
   - 3.1 [PL-Only Integration Philosophy](#31-pl-only-integration-philosophy)
   - 3.2 [Interconnect Architecture & Native Bus Protocol](#32-interconnect-architecture--native-bus-protocol)
   - 3.3 [Address Decoder & Bus Error Generation](#33-address-decoder--bus-error-generation)
4. [Memory Subsystem Microarchitecture](#4-memory-subsystem-microarchitecture)
   - 4.1 [Instruction Memory (IMEM) - 32 KiB](#41-instruction-memory-imem---32-kib)
   - 4.2 [Dual-Port Data Memory (DMEM) - 224 KiB](#42-dual-port-data-memory-dmem---224-kib)
   - 4.3 [Dual-Port Arbitration & Conflict Avoidance](#43-dual-port-arbitration--conflict-avoidance)
   - 4.4 [Complete System Memory Map](#44-complete-system-memory-map)
5. [Core Architecture: PicoRV32 RV32IM](#5-core-architecture-picorv32-rv32im)
   - 5.1 [Core Configuration Parameters](#51-core-configuration-parameters)
   - 5.2 [Hardware Multiplication & Division Subsystem](#52-hardware-multiplication--division-subsystem)
   - 5.3 [Native Bus Interface Timing & Waveforms](#53-native-bus-interface-timing--waveforms)
   - 5.4 [Trap & Exception Handling](#54-trap--exception-handling)
6. [Fixed 8×8 Weight-Stationary Systolic Array IP](#6-fixed-88-weight-stationary-systolic-array-ip)
   - 6.1 [Fixed IP Contract & Cryptographic Integrity](#61-fixed-ip-contract--cryptographic-integrity)
   - 6.2 [Mathematical Dataflow: Weight-Stationary Matrix Multiplication](#62-mathematical-dataflow-weight-stationary-matrix-multiplication)
   - 6.3 [Processing Element (PE) Microarchitecture](#63-processing-element-pe-microarchitecture)
   - 6.4 [Systolic Skew Unit & Wavefront Alignment](#64-systolic-skew-unit--wavefront-alignment)
   - 6.5 [Deterministic 154-Cycle Execution Sequence](#65-deterministic-154-cycle-execution-sequence)
   - 6.6 [Output Buffer & Registered Read-Valid Latency](#66-output-buffer--registered-read-valid-latency)
7. [Accelerator Wrapper Subsystem (`acc_wrapper.sv`)](#7-accelerator-wrapper-subsystem-acc_wrappersv)
   - 7.1 [Wrapper Roles & Architectural Boundaries](#71-wrapper-roles--architectural-boundaries)
   - 7.2 [MMIO Register Specification (Base: `0x4000_0100`)](#72-mmio-register-specification-base-0x4000_0100)
   - 7.3 [DMA Bypass MUX & Mutual Exclusion Logic](#73-dma-bypass-mux--mutual-exclusion-logic)
   - 7.4 [Hardware Local Reset FSM](#74-hardware-local-reset-fsm)
   - 7.5 [Latency Matching & Canonical Handshake](#75-latency-matching--canonical-handshake)
8. [Tile DMA Engine Architecture (`dma_engine.sv`)](#8-tile-dma-engine-architecture-dma_enginesv)
   - 8.1 [Purpose & Autonomous Movement Principles](#81-purpose--autonomous-movement-principles)
   - 8.2 [7-State Microarchitectural Finite State Machine (FSM)](#82-7-state-microarchitectural-finite-state-machine-fsm)
   - 8.3 [Transfer Modes: Activation Load, Weight Load, Result Store](#83-transfer-modes-activation-load-weight-load-result-store)
   - 8.4 [Data Packing & Unpacking Engines](#84-data-packing--unpacking-engines)
   - 8.5 [Single-Outstanding Read Conformance (Assertion A1)](#85-single-outstanding-read-conformance-assertion-a1)
   - 8.6 [Pre-Transfer Validation & Watchdog Timer](#86-pre-transfer-validation--watchdog-timer)
   - 8.7 [DMA Register Specification (Base: `0x4000_0200`)](#87-dma-register-specification-base-0x4000_0200)
9. [Physical Layer UART Peripheral (`uart.sv`)](#9-physical-layer-uart-peripheral-uartsv)
   - 9.1 [Baud Rate Generation & 16× Oversampling](#91-baud-rate-generation--16-oversampling)
   - 9.2 [Clock Domain Crossing (CDC) & Majority-Vote Filter](#92-clock-domain-crossing-cdc--majority-vote-filter)
   - 9.3 [FIFO Subsystem (TX/RX)](#93-fifo-subsystem-txrx)
   - 9.4 [UART MMIO Register Map (Base: `0x4000_0300`)](#94-uart-mmio-register-map-base-0x4000_0300)
10. [Host Communication Protocol & Frame Grammar](#10-host-communication-protocol--frame-grammar)
    - 10.1 [Binary Frame Format](#101-binary-frame-format)
    - 10.2 [Command & Response Grammar](#102-command--response-grammar)
    - 10.3 [CRC-16-CCITT Verification](#103-crc-16-ccitt-verification)
11. [Edge-AI Quantized CNN Inference Architecture](#11-edge-ai-quantized-cnn-inference-architecture)
    - 11.1 [Neural Network Topology (MNIST Classifier)](#111-neural-network-topology-mnist-classifier)
    - 11.2 [Fixed-Point Arithmetic & Symmetric INT8 Quantization](#112-fixed-point-arithmetic--symmetric-int8-quantization)
    - 11.3 [Systolic Array Tile Mapping & Im2Col GEMM Decomposition](#113-systolic-array-tile-mapping--im2col-gemm-decomposition)
    - 11.4 [K-Dimension Splitting & Partial Sum Accumulation](#114-k-dimension-splitting--partial-sum-accumulation)
    - 11.5 [Memory Buffer Allocation & Ping-Pong Strategy](#115-memory-buffer-allocation--ping-pong-strategy)
12. [Clock Distribution & Reset Subsystem](#12-clock-distribution--reset-subsystem)
    - 12.1 [Single Clock Domain Constraints](#121-single-clock-domain-constraints)
    - 12.2 [Synchronous Reset Tree (`reset_ctrl.sv`)](#122-synchronous-reset-tree-reset_ctrlsv)
13. [System Control Registers (`sys_regs.sv`)](#13-system-control-registers-sys_regssv)
14. [Physical Implementation & Timing Closure Sign-Off](#14-physical-implementation--timing-closure-sign-off)
    - 14.1 [Static Timing Analysis (STA) Metrics](#141-static-timing-analysis-sta-metrics)
    - 14.2 [Comprehensive FPGA Resource Utilization](#142-comprehensive-fpga-resource-utilization)
    - 14.3 [Power Dissipation & Thermal Profiles](#143-power-dissipation--thermal-profiles)
    - 14.4 [Design Rule Check (DRC) Verification](#144-design-rule-check-drc-verification)
15. [Physical Pinout & ZedBoard Constraints](#15-physical-pinout--zedboard-constraints)
16. [Formal Verification & Acceptance Testing](#16-formal-verification--acceptance-testing)
    - 16.1 [Gates V1 through V11 Sign-Off Matrix](#161-gates-v1-through-v11-sign-off-matrix)
    - 16.2 [Hardware Assertions (A1 through A10)](#162-hardware-assertions-a1-through-a10)
    - 16.3 [Testbench Suites & Execution Instructions](#163-testbench-suites--execution-instructions)
17. [Firmware Architecture & Build Toolchain](#17-firmware-architecture--build-toolchain)
    - 17.1 [Firmware Layer Hierarchy](#171-firmware-layer-hierarchy)
    - 17.2 [Software Driver APIs](#172-software-driver-apis)
    - 17.3 [Bare-Metal Compilation Flow](#173-bare-metal-compilation-flow)
18. [Hardware Bring-Up & Validation Guide](#18-hardware-bring-up--validation-guide)
    - 18.1 [Equipment & Cable Connections](#181-equipment--cable-connections)
    - 18.2 [FPGA Programming Flow](#182-fpga-programming-flow)
    - 18.3 [Host Python Test Harness Execution](#183-host-python-test-harness-execution)
19. [Repository Directory Structure](#19-repository-directory-structure)
20. [Architectural Authorship & References](#20-architectural-authorship--references)

---

## 1. Executive Summary & Architectural Scope

This repository provides the complete, production-grade RTL, firmware, simulation harnesses, and physical implementation sign-off for an **Edge-AI System-on-Chip (SoC)** combining a 32-bit RISC-V CPU core with a hardware-accelerated **8×8 Weight-Stationary (WS) Systolic Array**. 

Targeted specifically at the **AMD/Xilinx Zynq-7000 XC7Z020-CLG484-1** device on the **Digilent ZedBoard**, the design represents an end-to-end hardware-software co-designed inferencing engine executing quantized convolutional neural networks (CNNs) with 100% bit-exact numerical parity against golden software models.

### Key Innovations and Architectural Highlights:
1. **Strictly PL-Only Implementation:** The entire system—CPU, instruction memory, multi-banked dual-port data memory, tile DMA engine, systolic accelerator, MMIO interconnect, and UART—operates exclusively in the Programmable Logic (PL) fabric. The Zynq Processing System (PS7 ARM Cortex-A9 MPCore) remains unmapped and powered down, eliminating external bus dependencies and non-deterministic cache arbitration.
2. **Single 100.0 MHz Clock Domain:** The entire digital architecture runs synchronously from a single 100.0 MHz oscillator. No derived clock dividers, PLLs, or MMCMs are used for logic clocks, eliminating multi-frequency clock domain crossings (CDC) and ensuring clean static timing closure (+0.943 ns WNS).
3. **PicoRV32 RV32IM Integration:** The CPU is configured with full RV32I integer instruction set plus the **M-extension** (hardware multiply and divide), utilizing 4 dedicated DSP48E1 slices for single-cycle multiplication steps and hardware-managed non-restoring division, eliminating all software division traps.
4. **Autonomous Tile DMA Engine:** A specialized 7-state hardware direct memory access (DMA) engine manages burst transfers between the 224 KiB dual-port data memory and the systolic accelerator. It performs hardware byte-unpacking (transforming 32-bit words into 8-bit streams) and word-repacking (transforming 32-bit outputs into memory words) with zero CPU intervention during tile streaming.
5. **Hardware Ownership Protocol:** Mutual exclusion between the CPU and the Tile DMA engine is enforced at the register level with zero bus contention. Dynamic ownership arbitration rejects invalid accesses with hardware-latched error codes, preventing race conditions.
6. **Bit-Exact Systolic Compute:** The core 8×8 systolic array contains 64 processing elements (PEs) executing INT8 × INT8 → INT32 multiply-accumulate operations in a canonical 154-cycle execution envelope. The design is cryptographically certified against original golden netlists.

---

## 2. Complete System Specifications

| Architectural Parameter | Technical Specification | Validation Verification |
|---|---|---|
| **Target FPGA Device** | AMD/Xilinx Zynq-7000 XC7Z020-CLG484-1 | Package: CLG484, Speed Grade: -1 |
| **Development Platform** | Digilent ZedBoard (Rev D, E, or F) | Standalone Bench Bring-Up |
| **Host System Interface** | USB-UART (Pmod JA1/JA2, Bank 13, LVCMOS33) | 115,200 Baud, 8N1, Binary Frame Protocol |
| **Primary System Clock** | 100.000 MHz Single Domain (Period = 10.000 ns) | Pin `Y9` (GCLK), Fully Constrained |
| **Reset Network** | Synchronous 2-FF tree, Active-Low (`sys_rst_n`) | Pin `F22` (`SW0`), Bank 35 |
| **Master Processor Core** | PicoRV32 RV32IM (32-bit RISC-V) | Native Bus Interface (Valid/Ready) |
| **CPU Extensions** | `ENABLE_COUNTERS=1`, `ENABLE_FAST_MUL=1`, `ENABLE_DIV=1` | 4 DSP48E1 Multipliers, Hardware Divider |
| **Instruction Memory (IMEM)** | 32 KiB Single-Port Synchronous BRAM (`0x0000_0000`–`0x0000_7FFF`) | 8× RAMB36E1 Tiles, 1-Cycle Latency |
| **Data Memory (DMEM)** | 224 KiB True Dual-Port Synchronous BRAM (`0x0000_8000`–`0x0003_FFFF`) | 56× RAMB36E1 Tiles, Port A=CPU, Port B=DMA |
| **Accelerator Core** | 8×8 Weight-Stationary Systolic Array (64 PEs) | Fixed IP (INT8 In, INT32 Out) |
| **Tile Execution Time** | Exactly 154 Clock Cycles ($1.54\ \mu	ext{s}$ at 100 MHz) | Deterministic Hardware State Machine |
| **Tile DMA Engine** | 7-State FSM, Dual Master (DMEM Port B + Accelerator) | Modes: `ACT_LOAD` (64B), `WEIGHT_LOAD` (64B), `RESULT_STORE` (256B) |
| **UART Transceiver** | Dedicated PL UART with 16-byte TX/RX FIFOs | 16× Oversampling, Divisor 53 @ 100 MHz |
| **Worst Negative Slack (WNS)** | **+0.943 ns** (Setup Timing Met) | Vivado 2021.2 Post-Route STA |
| **Worst Hold Slack (WHS)** | **+0.054 ns** (Hold Timing Met) | Vivado 2021.2 Post-Route STA |
| **Failing Endpoints** | **0 / 22,600** Endpoints | 100% Timing Closed |
| **Slice LUT Utilization** | 8,314 / 53,200 (15.63%) | Post-Implementation Sign-Off |
| **Block RAM Utilization** | 64.5 / 140 Tiles (46.07%) | 64× RAMB36E1 + 1× RAMB18E1 |
| **Total On-Chip Power** | 0.441 W (Dynamic: 0.327 W, Static: 0.115 W) | Commercial Grade Thermal Margin: 54.9°C |

---

## 3. Top-Level Hardware Architecture

### 3.1 PL-Only Integration Philosophy
Unlike hybrid Zynq architectures that instantiate the ARM Cortex-A9 hard processor and route transactions through AXI GP/HP interconnect bridges, this architecture is **100% contained within the FPGA programmable logic**. 

#### Engineering Rationale:
- **Zero Bus Contention:** In standard Zynq designs, the ARM core, Linux kernel interrupts, and DDR controller contend for DRAM bandwidth, causing non-deterministic memory access jitter.
- **Predictable Real-Time Latency:** Placing instruction code and data entirely within dedicated on-chip Block RAM guarantees single-cycle deterministic read latency.
- **Simplified Verification:** Without complex AXI protocol bridges, transactions follow clean single-cycle two-phase valid/ready handshakes.
- **Low Power Footprint:** By leaving the Zynq Processing System unpowered, total power dissipation remains at a minimal 0.441 W.

```
+--------------------------------------------------------------------------------------------------------+
|                                  AMD/Xilinx Zynq-7000 XC7Z020 (ZedBoard)                              |
|                                       PROGRAMMABLE LOGIC (PL-ONLY)                                     |
|                                                                                                        |
|   +-------------------+      +-------------------+      +------------------------------------------+   |
|   |   RESET_CTRL      |      |   PicoRV32 RV32IM |      |         PL UART PERIPHERAL               |   |
|   |  (reset_ctrl.sv)  |      |   (picorv32.v)    |      |            (uart.sv)                     |   |
|   |                   |      |                   |      |  115,200 Baud (Divisor 53 @ 100 MHz)     |   |
|   | 2-FF Sync Tree    |      | 4 DSP48E1 Multipl |      |  16-Byte TX FIFO / 16-Byte RX FIFO       |   |
|   | Active-Low Reset  |      | Hardware Div (M)  |      |  2-FF Synchronizer on uart_rx (Pin Y11)  |   |
|   +--------+----------+      +---------+---------+      +--------------------+---------------------+   |
|            |                           |                                     |                         |
|            |                           | CPU Native Bus                      | uart_mmio               |
|            |                           v                                     |                         |
|   +--------v-----------------------------------------------------------------v---------------------+   |
|   |                          NATIVE BUS INTERCONNECT & ADDRESS DECODER                              |   |
|   |                                    (native_interconnect.sv)                                     |   |
|   +-------+--------------------+---------------------+--------------------+--------------------+-----+   |
|           |                    |                     |                    |                    |       |
|           | imem_if            | Port A (CPU)        | sys_mmio           | acc_mmio           | dma   |
|           v                    v                     v                    v                    v mmio  |
|   +---------------+    +---------------+     +---------------+    +---------------+    +---------------+   |
|   |   IMEM BRAM   |    |   DMEM BRAM   |     |   SYS_REGS    |    |  ACC_WRAPPER  |    |  DMA_ENGINE   |   |
|   |   (32 KiB)    |    |   (224 KiB)   |     |  (sys_regs.sv)|    | (acc_wrapper) |    |(dma_engine.sv)|   |
|   | 8x RAMB36E1   |    | 56x RAMB36E1  |     |               |    |               |    |               |   |
|   | 0x0000_0000 - |    | 0x0000_8000 - |     | 0x4000_0000 - |    | 0x4000_0100 - |    | 0x4000_0200 - |   |
|   | 0x0000_7FFF   |    | 0x0003_FFFF   |     | 0x4000_00FF   |    | 0x4000_01FF   |    | 0x4000_02FF   |   |
|   +---------------+    +-------+-------+     +---------------+    +-------+-------+    +-------+-------+   |
|                                ^                                          ^                    |       |
|                                |                                          |                    |       |
|                                |         Port B (DMA Engine Master)       | DMA Bypass Port    |       |
|                                +------------------------------------------+--------------------+       |
|                                                                                                        |
|                                              +---------------------------------------+                 |
|                                              |   8x8 WS SYSTOLIC ARRAY ACCELERATOR   |                 |
|                                              |         (accelerator_top.v)           |                 |
|                                              |  64 Processing Elements (INT8 x INT8) |                 |
|                                              |  154 Cycles Fixed Compute Execution   |                 |
|                                              +---------------------------------------+                 |
+--------------------------------------------------------------------------------------------------------+
```

### 3.2 Interconnect Architecture & Native Bus Protocol
The system uses the PicoRV32 native bus interface—a synchronous, two-phase handshaking protocol:
- **`mem_valid`:** Asserted by the master when address and control lines are valid.
- **`mem_ready`:** Asserted by the slave when the data transfer is complete.
- **`mem_addr[31:0]`:** 32-bit memory byte address.
- **`mem_wdata[31:0]`:** 32-bit write data bus.
- **`mem_wstrb[3:0]`:** Byte write enable strobes (`4'b0000` = Read, `4'b1111` = 32-bit Word Write).
- **`mem_rdata[31:0]`:** 32-bit read data bus driven by the addressed slave.

### 3.3 Address Decoder & Bus Error Generation
The module `native_interconnect.sv` decodes the top-level 32-bit address bus into six physical chip-select domains:
1. `IMEM`: `0x0000_0000` to `0x0000_7FFF` (Read-only execution port)
2. `DMEM`: `0x0000_8000` to `0x0003_FFFF` (Read/Write CPU Port A)
3. `SYS_REGS`: `0x4000_0000` to `0x4000_00FF` (Control/Status registers)
4. `ACC_WRAPPER`: `0x4000_0100` to `0x4000_01FF` (Accelerator registers)
5. `DMA_ENGINE`: `0x4000_0200` to `0x4000_02FF` (DMA configuration registers)
6. `PL_UART`: `0x4000_0300` to `0x4000_03FF` (Serial FIFO registers)

#### Unmapped Address Protection:
If the CPU accesses an address outside the valid regions, the interconnect responds immediately:
- Asserts `mem_ready = 1` for exactly 1 cycle.
- Drives `mem_rdata = 32'hDEAD_BEEF`.
- Pulses `bus_error = 1` to `sys_regs.sv`, latching sticky bit `SYS_STATUS[1]`.

---

## 4. Memory Subsystem Microarchitecture

### 4.1 Instruction Memory (IMEM) - 32 KiB
- **Module:** `rtl/imem_bram.sv`
- **Memory Technology:** Synthesized into 8 dedicated Xilinx `RAMB36E1` primitive blocks configured as $8	ext{K} 	imes 32$-bit true dual-port RAMs.
- **Address Mapping:** `0x0000_0000` to `0x0000_7FFF` (8,192 words).
- **Reset Boot Vector:** The PicoRV32 begins instruction execution at `0x0000_0000`.
- **Initialization:** Memory content is loaded during FPGA configuration using `$readmemh` targeting `firmware/phase4_cnn.hex`.
- **Latency:** Synchronous 1-cycle registered read latency with registered `mem_ready` handshaking.

### 4.2 Dual-Port Data Memory (DMEM) - 224 KiB
- **Module:** `rtl/dmem_bram.sv`
- **Memory Technology:** Synthesized into 56 dedicated `RAMB36E1` primitive blocks arranged as $56	ext{K} 	imes 32$-bit dual-port synchronous memory.
- **Address Mapping:** `0x0000_8000` to `0x0003_FFFF` (57,344 words).
- **Physical Ports:**
  - **Port A (CPU Interconnect Slave):** Full byte-level write enables (`mem_wstrb[3:0]`), used by firmware for program stack, scratchpad variables, and layer parameters.
  - **Port B (Tile DMA Engine Master):** Dedicated 32-bit wide read/write port used exclusively by `dma_engine.sv` for high-throughput tile streaming.

### 4.3 Dual-Port Arbitration & Conflict Avoidance
Ports A and B can operate concurrently at full 100 MHz without degrading memory throughput. To ensure memory integrity:
- **Port Separation:** Port A (CPU) and Port B (DMA) operate independently.
- **Collision Detection:** Hardware monitors Port A and Port B addresses on every clock cycle. If Port A writes to the exact same word address Port B is reading or writing, `dmem_bram.sv` latches a collision alert flag (`collision_detected`).
- **Software Boundary Discipline:** Firmware allocates non-overlapping memory regions to CPU stack/workspace and DMA burst buffers, ensuring zero simultaneous read/write hazards.

### 4.4 Complete System Memory Map

| Address Range | Size | Region Name | Function / Subsystem Usage |
|---|---|---|---|
| `0x0000_0000 – 0x0000_7FFF` | 32 KiB | `IMEM` | Instruction BRAM (PicoRV32 Boot Vector @ 0x0) |
| `0x0000_8000 – 0x0000_8FFF` | 4 KiB | `SCRATCH` | Stack, UART buffers, frame queues, cycle counters, logits |
| `0x0000_9000 – 0x0000_FFFF` | 28 KiB | `WORKSPACE` | CPU runtime workspace & C runtime variables |
| `0x0001_0000 – 0x0001_3FFF` | 16 KiB | `INPUT_BUF` | 784-Byte Normalized Input Image ($28 	imes 28$) |
| `0x0001_4000 – 0x0002_BFFF` | 96 KiB | `WEIGHT_BUF` | CNN Layer Weights, Biases, and Quantization Scales |
| `0x0002_C000 – 0x0003_3FFF` | 32 KiB | `FEATURE_A` | Ping-Pong Buffer A (Conv1 Output, Pool2 Output) |
| `0x0003_4000 – 0x0003_BFFF` | 32 KiB | `FEATURE_B` | Ping-Pong Buffer B (Pool1 Output, Conv2 Output) |
| `0x0003_C000 – 0x0003_FFFF` | 16 KiB | `OUTPUT_BUF` | Accelerator Results Target (256B) & Final Logits |
| `0x4000_0000 – 0x4000_00FF` | 256 B | `SYS_REGS` | System ID (0xA5A50001), Status, Control, Timer |
| `0x4000_0100 – 0x4000_01FF` | 256 B | `ACC_WRAPPER`| Accelerator MMIO Control, Status, Matrix Data |
| `0x4000_0200 – 0x4000_02FF` | 256 B | `DMA_ENGINE` | Tile DMA Control, Addresses, Length, Owner, Status |
| `0x4000_0300 – 0x4000_03FF` | 256 B | `PL_UART` | Serial TX/RX FIFOs, Status, Divisor, Control |

---

## 5. Core Architecture: PicoRV32 RV32IM

### 5.1 Core Configuration Parameters
The system instantiates the open-source **PicoRV32** processor (`rtl/picorv32.v`) parameterized to provide a balance between resource efficiency and arithmetic performance:

```verilog
picorv32 #(
    .ENABLE_COUNTERS     (1),      // 64-bit cycle and instret performance counters
    .ENABLE_COUNTERS64   (1),      // Full 64-bit counter accessibility via RDCYCLE[H]
    .ENABLE_REGS_16_31   (1),      // Full 32 general-purpose registers (x0 - x31)
    .ENABLE_REGS_DUALPORT(1),      // Dual-read port register file
    .LATCHED_MEM_RDATA   (0),      // Direct synchronous data sampling
    .TWO_STAGE_SHIFT     (1),      // 2-stage shifter implementation
    .BARREL_SHIFTER      (0),      // Area-optimized multi-cycle shifter
    .TWO_CYCLE_COMPARE   (0),      // Single-cycle comparison
    .TWO_CYCLE_ALU       (0),      // Single-cycle ALU arithmetic
    .CATCH_MISALIGN      (1),      // Hardware trapping on misaligned word access
    .CATCH_ILLINSN       (1),      // Hardware trapping on illegal opcodes
    .ENABLE_PCPI         (0),      // Dedicated coprocessor interface disabled
    .ENABLE_MUL          (1),      // Hardware integer multiplication
    .ENABLE_FAST_MUL     (1),      // DSP48E1 accelerated multiplier
    .ENABLE_DIV          (1),      // Hardware integer non-restoring divider
    .ENABLE_IRQ          (0),      // External interrupt controller disabled
    .ENABLE_IRQ_QREGS    (0),      // Interrupt shadow registers disabled
    .ENABLE_IRQ_TIMER    (0),      // Internal timer disabled (uses sys_regs)
    .ENABLE_TRACE        (0),      // Execution trace port disabled
    .REGS_INIT_ZERO      (1),      // Register file zero-initialized at reset
    .MASKED_IRQ          (32'h0),  // IRQ mask
    .LATCHED_IRQ         (32'h0),  // IRQ latch
    .PROGADDR_RESET      (32'h0000_0000), // Boot execution vector (IMEM base)
    .PROGADDR_IRQ        (32'h0000_0010), // IRQ entry vector
    .STACKADDR           (32'h0000_FFF0)  // Initial stack pointer (top of scratchpad)
) cpu_inst ( ... );
```

### 5.2 Hardware Multiplication & Division Subsystem
- **Fast Multiplication (`ENABLE_FAST_MUL=1`):** Synthesizes directly into **4 dedicated DSP48E1** arithmetic blocks in the Zynq PL fabric. Multiplications execute in 3 to 4 clock cycles, enabling high-speed software fixed-point requantization and bias scaling.
- **Hardware Division (`ENABLE_DIV=1`):** Employs a non-restoring hardware division algorithm requiring 34 clock cycles. This eliminates division trap exceptions and software emulation runtime penalties during CNN normalization and coordinate arithmetic.

### 5.3 Native Bus Interface Timing & Waveforms
- **Read Transactions:** CPU drives `mem_valid = 1`, `mem_addr`, and `mem_wstrb = 4'b0000`. Memory decodes address and returns data with `mem_ready = 1` exactly 1 cycle later.
- **Write Transactions:** CPU drives `mem_valid = 1`, `mem_addr`, `mem_wdata`, and active `mem_wstrb` bits. Slave registers data on the clock edge where `mem_ready = 1` is returned.

### 5.4 Trap & Exception Handling
If an illegal instruction or unaligned access occurs, the CPU halts instruction fetch and asserts `cpu_trap = 1`. 
- `reset_ctrl.sv` and `sys_regs.sv` latch the trap condition into `SYS_STATUS[2]`.
- Sticky trap status can be polled over UART or cleared by writing to `SYS_CONTROL[2]`.

---

## 6. Fixed 8×8 Weight-Stationary Systolic Array IP

### 6.1 Fixed IP Contract & Cryptographic Integrity
The underlying matrix execution core (`rtl/accelerator_top.v`) is a certified IP core. Its microarchitecture, port lists, and SHA-256 hashes are strictly fixed and verified:

| File Name | SHA-256 Cryptographic Hash | Function |
|---|---|---|
| `accelerator_top.v` | `DBAB334DF1D5F792881A9F5D579AB686FB1B29B5BF904BB0E868185496D9D9A8` | Top-level IP wrapper & bus interface |
| `activation_buffer.v` | `00D29D02FA7A1177672BEB4126953A847258C9299E8821BF84E177D96E34983D` | 64-byte input activation memory |
| `weight_buffer.v` | `711EAA405E084442CF7E20E4DA1A678E5B426802F53E072E943BCF92428624EA` | 64-byte weight storage memory |
| `controller.v` | `660595E48FACD7116AFFD1F90C44D0D3212CE5CC8A7665E238D95CB8AC581719` | 154-cycle execution FSM |
| `data_path.v` | `DA2913ADF78772C3EC3F719074B5DDE18DC77C48E9B7F7CE2A07CA791A4E695B` | Inter-PE routing and buffer routing |
| `pe.v` | `61555AB09CB4311D4773DEDB43FCD1CCD8C77AD2DF0830FEAE5DF3657E2EB172` | Single processing element (INT8 MAC) |
| `skew.v` | `2D9FAA0899A7BD1F86EB0A1A5AE4D913F0988AA613C7A08DC35DF400F3C13C70` | Triangular skew shift registers |
| `systolic_8x8.v` | `CA9285BC673D01C88BFFB31836A4CF567B1A5BCB1691F6EB5A88735D6BBBA42E` | 8×8 2D Processing Element mesh |
| `output_buffer.v` | `7FBB95BFA4209FA20CC77E51F84FF0F85BCD09C2FBF51267D42CE6CE19C7950B` | 64×32-bit result accumulation buffer |

### 6.2 Mathematical Dataflow: Weight-Stationary Matrix Multiplication
The accelerator computes the general matrix multiplication:
$$C_{[8 	imes 8]} = A_{[8 	imes 8]} 	imes B_{[8 	imes 8]}$$

In **Weight-Stationary (WS)** dataflow:
1. Weight matrix $B$ is loaded into PE registers and remains stationary across computation.
2. Activation matrix $A$ streams horizontally from left to right through the array.
3. Partial sums accumulate vertically from top to bottom through each column of PEs.

$$C_{i,j} = \sum_{k=0}^{7} A_{i,k} \cdot B_{k,j} \quad 	ext{for } i \in [0,7], j \in [0,7]$$

### 6.3 Processing Element (PE) Microarchitecture
Each of the 64 Processing Elements (`rtl/pe.v`) contains:
- **`w_reg [7:0]`:** 8-bit stationary weight storage register, loaded via `load_weight`.
- **Signed Multiplier:** Multiplies 8-bit signed activation $A_{	ext{in}}$ by 8-bit stationary weight $W_{	ext{reg}}$, producing a 16-bit intermediate signed product:
  $$	ext{prod}[15:0] = A_{	ext{in}}[7:0] 	imes W_{	ext{reg}}[7:0]$$
- **Accumulator Adder:** Sign-extends the 16-bit product to 32 bits and adds it to the incoming vertical partial sum $P_{	ext{sum\_in}}$:
  $$	ext{sum}[31:0] = (	ext{clear\_psum} \ ? \ 0 : P_{	ext{sum\_in}}[31:0]) + 	ext{sign\_ext}(	ext{prod}[15:0])$$
- **`psum_reg [31:0]`:** Registers the accumulated result and drives $P_{	ext{sum\_out}}$ to the neighboring PE below.
- **Horizontal Forwarding:** Registers $A_{	ext{in}}$ and forwards $A_{	ext{out}}$ to the neighboring PE to the right.

### 6.4 Systolic Skew Unit & Wavefront Alignment
Because partial sums accumulate vertically, row inputs must enter the array in a staggered systolic wavefront:
- **Row 0:** Skew delay = 0 cycles (enters array immediately).
- **Row 1:** Skew delay = 1 cycle.
- **Row 2:** Skew delay = 2 cycles.
- **Row $i$:** Skew delay = $i$ cycles (implemented via triangular flip-flop shift chains in `rtl/skew.v`).

### 6.5 Deterministic 154-Cycle Execution Sequence
The central hardware controller (`rtl/controller.v`) executes a deterministic 154-cycle state sequence upon receipt of a `start` pulse:
1. **`READ_WEIGHT` (Cycles 0 to 63):** Reads 64 weight bytes sequentially from the weight buffer.
2. **`LOAD_WEIGHT` (Cycles 64 to 71):** Shifts weights column-by-column into PE local storage registers.
3. **`STREAM & COMPUTE` (Cycles 72 to 120):** Streams activations through the systolic skew unit; PEs perform concurrent MAC operations.
4. **`CAPTURE_OUTPUT` (Cycles 121 to 153):** Latches diagonal systolic wavefront outputs into the Output Buffer memory.
5. **`DONE` (Cycle 154):** Asserts a single-cycle `done` pulse to `acc_wrapper.sv` and returns to `IDLE`.

### 6.6 Output Buffer & Registered Read-Valid Latency
- **Organization:** 64 words × 32 bits (256 bytes total).
- **Address Mapping:** Standard row-major index: $	ext{rd\_addr}[5:0] = 8 	imes 	ext{row} + 	ext{col}$.
- **Read Timing:** The output buffer RAM utilizes synchronous output registers. When `rd_en` is asserted on clock cycle $N$, valid data `rd_data[31:0]` and the strobe `rd_valid` appear on cycle $N+1$.

---

## 7. Accelerator Wrapper Subsystem (`acc_wrapper.sv`)

### 7.1 Wrapper Roles & Architectural Boundaries
The `acc_wrapper` module isolates the fixed systolic array IP from the system bus and implements:
1. **PicoRV32 MMIO Slave Interface:** Maps IP control, status, and buffer memory into CPU address space (`0x4000_0100`–`0x4000_01FF`).
2. **DMA Native Bypass Interface:** Provides direct zero-wait-state ports for `dma_engine.sv`.
3. **Hardware Local Reset FSM:** Manages multi-cycle synchronous local reset sequences.
4. **Execution Cycle Counter:** Measures execution time between `start` and `done`.

### 7.2 MMIO Register Specification (Base: `0x4000_0100`)

| Offset | Register Name | Width | Access | Semantics & Bitfield Definitions |
|---|---|---|---|---|
| `0x00` | `ACC_CONTROL` | 32 | WO | `[0]`: `START`<br>`[1]`: `CLR_DONE`<br>`[2]`: `LOCAL_RESET` (5-cycle reset pulse)<br>`[3]`: `CLR_ERR` |
| `0x04` | `ACC_STATUS` | 32 | RO | `[0]`: `BUSY`<br>`[1]`: `DONE`<br>`[2]`: `RESULT_VALID`<br>`[3]`: `ERROR`<br>`[23:16]`: `ERROR_CODE` |
| `0x08` | `ACC_MATRIX_SEL` | 32 | RW | `[0]`: Matrix select (0 = Activation Buffer A, 1 = Weight Buffer B) |
| `0x0C` | `ACC_ROW` | 32 | RW | `[2:0]`: Target matrix row index ($0 \le 	ext{row} \le 7$) |
| `0x10` | `ACC_COL` | 32 | RW | `[2:0]`: Target matrix column index ($0 \le 	ext{col} \le 7$) |
| `0x14` | `ACC_WRITE_DATA` | 32 | WO | `[7:0]`: Signed INT8 data element to write into selected buffer |
| `0x18` | `ACC_READ_ADDR` | 32 | RW | `[5:0]`: Output buffer word address index ($0 \le 	ext{addr} \le 63$) |
| `0x1C` | `ACC_READ_CMD` | 32 | WO | Dummy write triggers 1-cycle registered read pipeline fetch |
| `0x20` | `ACC_READ_DATA` | 32 | RO | `[31:0]`: Signed INT32 result latched from Output Buffer |
| `0x24` | `ACC_CYCLES` | 32 | RO | `[31:0]`: Measured hardware execution cycles (154 cycles) |
| `0x28` | `ACC_ERROR_CODE` | 32 | RO | `[7:0]`: Latched error code (`0x01`–`0x08`) |

### 7.3 DMA Bypass MUX & Mutual Exclusion Logic
`acc_wrapper.sv` arbitrates control between CPU MMIO and the Tile DMA engine using the `dma_owner` control bit:
- While `dma_owner == 1`: DMA controls element write strobes and read strobes directly. CPU MMIO write attempts to operand buffers or `START` are rejected with error `0x05` (`ERR_OWNERSHIP_VIOL`).
- While `dma_owner == 0`: CPU controls accelerator registers. DMA requests are rejected with error `0x14` (`ERR_OWNERSHIP_VIOLATION`).

---

## 8. Tile DMA Engine Architecture (`dma_engine.sv`)

### 8.1 Purpose & Autonomous Movement Principles
The Tile DMA Engine is a specialized, hardware-bounded data mover designed to eliminate CPU overhead during tensor streaming. Moving an $8 	imes 8$ tile into the accelerator requires 64 element writes, and reading results requires 64 32-bit memory stores. The DMA engine completes these transfers autonomously via DMEM Port B and accelerator bypass ports.

### 8.2 7-State Microarchitectural Finite State Machine (FSM)
1. **`ST_IDLE`:** Validates configuration parameters when `DMA_CONTROL.START` is written. If valid, asserts `reg_busy = 1` and branches to load or drain path; if invalid, sets error flags and remains idle.
2. **`ST_LOAD_REQ`:** Asserts `mem_valid = 1`, `mem_wstrb = 4'b0000`, `mem_addr = cur_mem_addr[14:0]`, and asserts `outstanding_read = 1`.
3. **`ST_LOAD_WAIT`:** Waits for `mem_ready == 1` from DMEM Port B. Latches 32-bit `mem_rdata` into internal `word_buffer`, deasserts `mem_valid`, advances `cur_mem_addr += 4`, and sets `sub_byte_idx = 0`.
4. **`ST_LOAD_WRITE_BYTE`:** Drives `acc_wr_en = 1`, routes the current byte from `word_buffer` to `acc_wr_data`, and computes row/col indices:
   $$	ext{acc\_wr\_row} = 	ext{element\_idx}[5:3], \quad 	ext{acc\_wr\_col} = 	ext{element\_idx}[2:0]$$
   Advances `element_idx += 1`. If 4 bytes are written and $	ext{element\_idx} < 64$, loops back to `ST_LOAD_REQ`. If $	ext{element\_idx} == 64$, asserts `reg_done = 1` and returns to `ST_IDLE`.
5. **`ST_DRAIN_REQ`:** Asserts `acc_rd_en = 1` and `acc_rd_addr = element_idx[5:0]`.
6. **`ST_DRAIN_WAIT`:** Deasserts `acc_rd_en`. Waits for `acc_rd_valid == 1` (1-cycle IP latency). Latches 32-bit `acc_rd_data` into internal `drain_buffer`.
7. **`ST_DRAIN_WRITE_MEM`:** Asserts `mem_valid = 1`, `mem_wstrb = 4'b1111`, `mem_addr = cur_mem_addr[14:0]`, and `mem_wdata = drain_buffer`. When DMEM Port B returns `mem_ready == 1`, advances `cur_mem_addr += 4` and `element_idx += 1`. If $	ext{element\_idx} == 64$, asserts `reg_done = 1` and returns to `ST_IDLE`; otherwise loops back to `ST_DRAIN_REQ`.

### 8.3 Transfer Modes: Activation Load, Weight Load, Result Store
- **Mode 0 (`ACT_LOAD` - `2'b00`):** Transfers 64 contiguous bytes from DMEM to Accelerator Activation Buffer. Length must equal 64 bytes.
- **Mode 1 (`WEIGHT_LOAD` - `2'b01`):** Transfers 64 contiguous bytes from DMEM to Accelerator Weight Buffer. Length must equal 64 bytes.
- **Mode 2 (`RESULT_STORE` - `2'b10`):** Drains 64 32-bit result words (256 bytes) from Accelerator Output Buffer and writes them to contiguous DMEM addresses. Length must equal 256 bytes.

### 8.4 Data Packing & Unpacking Engines
- **Byte Unpacking:** Reading 16 32-bit words from DMEM produces 64 8-bit values for the accelerator buffers in little-endian order.
- **Word Repacking:** The 64 32-bit integer outputs from the accelerator are stored directly as aligned 32-bit words into DMEM with `mem_wstrb = 4'b1111`.

### 8.5 Single-Outstanding Read Conformance (Assertion A1)
The DMA registers an internal tracking flag `outstanding_read`. It is set to `1` when `mem_valid` is asserted and cleared when `mem_ready` is sampled. The DMA is architecturally blocked from issuing another read until `outstanding_read == 0`.

### 8.6 Pre-Transfer Validation & Watchdog Timer
The DMA validates ownership, 4-byte address alignment, legal transfer lengths, and address ranges before asserting `reg_busy = 1`. A 32-bit counter aborts the transaction if uncompleted after `DMA_TIMEOUT` cycles (default: 1,000,000 cycles).

### 8.7 DMA Register Specification (Base: `0x4000_0200`)

| Offset | Register Name | Width | Access | Semantics & Bitfield Definitions |
|---|---|---|---|---|
| `0x00` | `DMA_CONTROL` | 32 | RW | `[0]`: `START`, `[1]`: `CLEAR_DONE`, `[2]`: `CLEAR_ERROR`, `[5:4]`: `MODE` (`00`=ACT_LOAD, `01`=WEIGHT_LOAD, `10`=RESULT_STORE) |
| `0x04` | `DMA_STATUS` | 32 | RO | `[0]`: `BUSY`, `[1]`: `DONE`, `[2]`: `ERROR`, `[3]`: `TIMEOUT`, `[4]`: `CMD_REJECTED`, `[15:8]`: Progress Counter, `[23:16]`: Error Code |
| `0x08` | `DMA_SRC_ADDR` | 32 | RW | 32-bit Source byte address in DMEM |
| `0x0C` | `DMA_DST_ADDR` | 32 | RW | 32-bit Destination byte address in DMEM |
| `0x10` | `DMA_LENGTH` | 32 | RW | Transfer length in bytes (Legal: 64 or 256) |
| `0x14` | `DMA_OWNER` | 32 | RW | `[0]`: Ownership grant (0 = CPU owns datapath, 1 = DMA owns) |
| `0x18` | `DMA_TIMEOUT` | 32 | RW | 32-bit cycle watchdog threshold (Reset default: 1,000,000 cycles) |
| `0x1C` | `DMA_ERROR_CODE` | 32 | RO | `[7:0]`: Latched error code (`0x10`–`0x15`) |

---

## 9. Physical Layer UART Peripheral (`uart.sv`)

### 9.1 Baud Rate Generation & 16× Oversampling
Operates within the single 100 MHz clock domain:
- **Divider Formula:**
  $$	ext{DIVISOR} = 	ext{round}\left(rac{100,000,000}{16 	imes 115,200}ight) - 1 = 53 \quad (0	ext{x}0035)$$
- **Achieved Baud:** 115,740.74 baud (+0.47% error, well within standard ±2.0% tolerance).

### 9.2 Clock Domain Crossing (CDC) & Majority-Vote Filter
External `uart_rx` passes through a 2-stage flip-flop synchronizer chain (`rx_sync_1`, `rx_sync_2`) to prevent metastability, sampled at mid-bit index 7.

### 9.3 FIFO Subsystem (TX/RX)
- **TX FIFO:** 16-entry synchronous FIFO.
- **RX FIFO:** 16-entry synchronous FIFO with sticky overrun detection flag (`UART_STATUS.RX_OVERRUN`).

### 9.4 UART MMIO Register Map (Base: `0x4000_0300`)

| Offset | Register Name | Width | Access | Semantics & Bitfield Definitions |
|---|---|---|---|---|
| `0x00` | `UART_DATA` | 32 | RW | `[7:0]`: TX write data / RX read data |
| `0x04` | `UART_STATUS` | 32 | RO | `[0]`: `RX_VALID`, `[1]`: `TX_READY`, `[2]`: `RX_OVERRUN`, `[3]`: `TX_BUSY` |
| `0x08` | `UART_DIVISOR` | 32 | RW | `[15:0]`: Baud rate divider (Reset default: 53) |
| `0x0C` | `UART_CONTROL` | 32 | WO | `[0]`: `RX_FLUSH`, `[1]`: `TX_FLUSH` |

---

## 10. Host Communication Protocol & Frame Grammar

### 10.1 Binary Frame Format
```
+--------+--------+--------+---------------+---------------+--------------------+---------------+---------------+
| SYNC1  | SYNC2  |  TYPE  |    LEN_LO     |    LEN_HI     |  PAYLOAD (0..256B) |   CRC16_LO    |   CRC16_HI    |
| (0xA5) | (0x5A) | (1 B)  |     (1 B)     |     (1 B)     |      (0..256 B)    |     (1 B)     |     (1 B)     |
+--------+--------+--------+---------------+---------------+--------------------+---------------+---------------+
```

### 10.2 Command & Response Grammar
- `0x01` (`HELLO`): Host ping / discovery check.
- `0x02` (`INPUT_DATA`): Chunked image streaming (4 chunks × 196 B).
- `0x03` (`RUN`): Trigger full hardware CNN classification.
- `0x04` (`RESULT`): Return predicted class, cycles, and 10 logits.
- `0x7E` (`NACK`): Frame error response (`0x11`=Bad CRC, `0x12`=Bad Len).
- `0x7F` (`ACK`): Acknowledge valid frame.

### 10.3 CRC-16-CCITT Verification
Polynomial $x^{16} + x^{12} + x^5 + 1$ (`0x1021`) initialized to `0xFFFF`, computed across `TYPE || LEN_LO || LEN_HI || PAYLOAD`.

---

## 11. Edge-AI Quantized CNN Inference Architecture

### 11.1 Neural Network Topology (MNIST Classifier)
```
INPUT (28x28x1 Normalized INT8)
   |
   v
CONV1 (8 filters, 3x3 kernels, stride 1) -------> 26x26x8 Feature Map
   |
   v
RELU1 [ max(0, x) ]
   |
   v
MAXPOOL1 (2x2 kernel, stride 2) ----------------> 13x13x8 Feature Map
   |
   v
CONV2 (16 filters, 3x3 kernels, stride 1) ------> 11x11x16 Feature Map
   |
   v
RELU2 [ max(0, x) ]
   |
   v
MAXPOOL2 (2x2 kernel, stride 2) ----------------> 5x5x16 (400 elements)
   |
   v
FC1 (Dense GEMM: 400 inputs -> 32 neurons) -----> 32 Feature Elements
   |
   v
RELU3 [ max(0, x) ]
   |
   v
FC2 (Dense GEMM: 32 inputs -> 10 output logits)-> 10 Logits
   |
   v
ARGMAX (Find maximum logit index) --------------> Predicted Digit (0..9)
```

### 11.2 Fixed-Point Arithmetic & Symmetric INT8 Quantization
- **Weights & Activations:** Signed 8-bit integers (`int8_t`).
- **Accumulators:** Signed 32-bit integers (`int32_t`).
- **Requantization:**
  $$Y = 	ext{clip}\left(\left\lfloor rac{C_{	ext{acc}} + 	ext{bias} + 	ext{round}}{2^S} ightfloor, -128, 127ight)$$

### 11.3 Systolic Array Tile Mapping & Im2Col GEMM Decomposition
Convolutional layers are computed by transforming input receptive fields into unrolled matrices using **Im2Col**, evaluated in $8 	imes 8$ tile sub-blocks on the systolic array.

### 11.4 K-Dimension Splitting & Partial Sum Accumulation
When the reduction dimension $K > 8$:
- **FC1 ($K=400$):** Partitioned into 50 tiles of $K=8$. For each tile, DMA loads activations and weights, accelerator computes in 154 cycles, DMA drains 256 bytes, and software accumulates partial sums.
- **FC2 ($K=32$):** Partitioned into 4 tiles of $K=8$.

### 11.5 Memory Buffer Allocation & Ping-Pong Strategy
- **Ping-Pong Buffer A (`0x0002_C000`, 32 KiB):** Stores Conv1 output and MaxPool2 output.
- **Ping-Pong Buffer B (`0x0003_4000`, 32 KiB):** Stores MaxPool1 output and Conv2 output.

---

## 12. Clock Distribution & Reset Subsystem

### 12.1 Single Clock Domain Constraints
- **Clock Pin:** Pin `Y9` receives single-ended 100 MHz clock routed via `BUFGCTRL`.
- **Single Domain:** All logic runs synchronously on this clock. Static timing analysis reports **0 unconstrained endpoints** across all 22,600 analyzed paths.

### 12.2 Synchronous Reset Tree (`reset_ctrl.sv`)
- **Reset Pin:** `SW0` (Pin `F22`) with internal pull-up.
- **Synchronizer:** 2-stage flip-flop synchronizer distributes active-low `sys_rst_n` via a registered reset tree.

---

## 13. System Control Registers (`sys_regs.sv`)

Mapped to base address `0x4000_0000`:
- `0x00`: `SYS_ID` - Returns `0xA5A50001`.
- `0x04`: `SYS_STATUS` - `[0]`: Ready, `[1]`: Bus Error, `[2]`: CPU Trap.
- `0x08`: `SYS_CONTROL` - `[1]`: Clear Bus Error, `[2]`: Clear CPU Trap.
- `0x0C`: `CYCLE_COUNTER` - 32-bit free-running hardware counter @ 100 MHz.

---

## 14. Physical Implementation & Timing Closure Sign-Off

### 14.1 Static Timing Analysis (STA) Metrics (Vivado 2021.2)
- **Clock Frequency:** 100.000 MHz (Period = 10.000 ns)
- **Worst Negative Slack (WNS):** **+0.943 ns** (Setup Timing Met)
- **Total Negative Slack (TNS):** **0.000 ns**
- **Worst Hold Slack (WHS):** **+0.054 ns** (Hold Timing Met)
- **Total Hold Slack (THS):** **0.000 ns**
- **Failing Endpoints:** **0 / 22,600** Endpoints
- **Unconstrained Endpoints:** **0** across all 12 categories

### 14.2 Comprehensive FPGA Resource Utilization
Source: `reports/utilization.rpt`

| Resource | Used | Available | Utilization % |
|---|---|---|---|
| **Slice LUTs** | 8,314 | 53,200 | 15.63 % |
| **Slice Registers** | 7,090 | 106,400 | 6.66 % |
| **Block RAM Tile** | 64.5 | 140 | 46.07 % |
| - `RAMB36E1` | 64 | 140 | 45.71 % |
| - `RAMB18E1` | 1 | 280 | 0.36 % |
| **DSP48E1** | 4 | 220 | 1.82 % |
| **BUFGCTRL** | 1 | 32 | 3.13 % |
| **Bonded IOB** | 4 | 200 | 2.00 % |

### 14.3 Power Dissipation & Thermal Profiles
- **Total On-Chip Power:** **0.441 W** (Dynamic: 0.327 W, Static: 0.115 W)
- **Junction Temperature:** **30.1 °C** (Thermal margin: 54.9 °C below 85.0°C max)

### 14.4 Design Rule Check (DRC) Verification
- **DRC Violations:** 0 errors, 0 critical warnings.
- **Bitstream File:** `build/soc_top.bit` (1,649,065 bytes).

---

## 15. Physical Pinout & ZedBoard Constraints

Defined in `constraints/zedboard.xdc`:
- `clk_100m`: Pin `Y9` (Bank 13, LVCMOS33)
- `ext_reset_n`: Pin `F22` (Bank 35, LVCMOS33, Pullup)
- `uart_rx`: Pin `Y11` (Pmod JA1, Bank 13, LVCMOS33, Pullup)
- `uart_tx`: Pin `AA11` (Pmod JA2, Bank 13, LVCMOS33, Drive 8, Slew Slow)

---

## 16. Formal Verification & Acceptance Testing

### 16.1 Gates V1 through V11 Sign-Off Matrix

| Gate | Verification Target | Testbench / Proof | Status |
|---|---|---|---|
| **V1** | PicoRV32 RV32IM CPU Core Execution | `sim/phase1_tb.sv` | **PASS** |
| **V2** | Dual-Port DMEM Port A / Port B Concurrent Arbitration | `sim/phase3_dma_tb.sv` | **PASS** |
| **V3** | Fixed 8×8 Systolic Array Netlist Cryptographic Integrity | `docs/phase2_accelerator_audit.md` | **PASS** |
| **V4** | `acc_wrapper` Registered Output Latency & Control MUX | `sim/phase2_wrapper_tb.sv` | **PASS** |
| **V5** | Tile DMA Single-Outstanding Read Rule (Assertion A1) | `sim/phase3_dma_tb.sv` | **PASS** |
| **V6** | Tile DMA Byte-Unpacking & Word-Repacking Engines | `sim/phase3_dma_tb.sv` | **PASS** |
| **V7** | Mutual Exclusion Hardware Ownership Enforcement | `sim/phase3_dma_tb.sv` | **PASS** |
| **V8** | PL UART 115,200 Baud 8N1 Framing & 16-Byte FIFOs | `sim/phase4_uart_tb.sv` | **PASS** |
| **V9** | 100% Bit-Exact End-to-End CNN Inference Match | `sim/phase4_cnn_tb.sv` | **PASS** |
| **V10**| Vivado 2021.2 Static Timing Closure (+0.943 ns WNS @ 100 MHz)| `reports/timing_summary.rpt` | **PASS** |
| **V11**| ZedBoard Bitstream Generation & Hardware Sign-Off | `build/soc_top.bit` | **PASS** |

### 16.2 Hardware Assertions (A1 through A10)
- **A1:** DMA Single-Outstanding Read Rule (`mem_valid` never asserted while `outstanding_read == 1`).
- **A2:** 4-Byte Address Alignment check on DMA requests.
- **A3:** Memory Bounds Protection (`0x0000_8000`–`0x0003_FFFF`).
- **A4:** Legal Transfer Length check (exactly 64 or 256 bytes).
- **A5:** CPU access blocked when `DMA_OWNER == 1`.
- **A6:** DMA start blocked when `DMA_OWNER == 0`.
- **A7:** Accelerator output read valid arrives exactly 1 cycle after read enable.
- **A8:** Accelerator asserts `done` on cycle 154 after `start`.
- **A9:** Sticky FIFO overrun flag asserted on push to full UART RX FIFO.
- **A10:** Unmapped bus access returns `32'hDEAD_BEEF` with 1-cycle ready.

---

## 17. Firmware Architecture & Build Toolchain

### 17.1 Firmware Layer Hierarchy
1. **Hardware Access Layer (HAL):** Register definitions and volatile MMIO pointers in `firmware/phase4_cnn.c`.
2. **Peripheral Drivers:** Drivers for UART, Tile DMA Engine, and Accelerator Wrapper.
3. **GEMM & Layer Acceleration Library:** Im2Col matrix unpacking, K-dimension tile splitting, and accumulation loops.
4. **Application Pipeline:** Protocol receiver, inference scheduler, and argmax classification.

### 17.2 Bare-Metal Compilation Flow
Compiled using `firmware/build_phase4_fw.py` to produce `firmware/phase4_cnn.hex`, which initializes `imem_bram.sv`.

---

## 18. Hardware Bring-Up & Validation Guide

### 18.1 Equipment & Cable Connections
1. **Digilent ZedBoard** connected via 12V 3A DC power supply (`SW8`).
2. **Micro-USB Cable** connected between Host PC and ZedBoard JTAG port `J17`.
3. **USB-to-UART Adapter (3.3V)** connected to ZedBoard **Pmod JA** (Bank 13):
   - **JA1 (Pin `Y11`):** Connect to Adapter **TX** (Host → FPGA).
   - **JA2 (Pin `AA11`):** Connect to Adapter **RX** (FPGA → Host).
   - **JA5 (GND):** Connect to Adapter **GND**.

### 18.2 FPGA Programming Flow
```tcl
open_hw_manager
connect_hw_server
open_hw_target
set_property PROGRAM.FILE {build/soc_top.bit} [get_hw_devices xc7z020_1]
program_hw_devices [get_hw_devices xc7z020_1]
```
Switch **`SW0` UP** to release CPU reset.

### 18.3 Host Python Test Harness Execution
```bash
# 1. Ping / Discovery Handshake
python host/uart_host.py --port /dev/ttyUSB0 --baud 115200 --hello

# 2. Hardware Tile GEMM Smoke Test
python host/uart_host.py --port /dev/ttyUSB0 --baud 115200 --smoke

# 3. Classify Single Normalized MNIST Digit
python host/uart_host.py --port /dev/ttyUSB0 --baud 115200 --image model/sample_digit_7.bin

# 4. Batch Validation Suite (12 Test Vectors)
python host/uart_host.py --port /dev/ttyUSB0 --baud 115200 --dataset model/test_dataset.bin --manifest model/test_manifest.json
```

---

## 19. Repository Directory Structure

```
├── build/                           # Implementation checkpoints and bitstream
├── constraints/                     # ZedBoard pinout & timing XDC constraints
├── docs/                            # Implementation reports and specs
├── firmware/                        # Bare-metal C & assembly sources
├── host/                            # Host Python communication driver & golden model
├── model/                           # Validation dataset & test manifests
├── reports/                         # Vivado timing, utilization, power, and DRC reports
├── rtl/                             # SystemVerilog / Verilog hardware source files
├── scripts/                         # Synthesis & build automation scripts
├── sim/                             # Testbench verification test suites
└── weights/                         # Quantized CNN parameter weights & biases
```

---

## 20. Architectural Authorship & References

- **System Architecture & Design:** Sujan D.
- **Reference Specification:** *RISC-V SoC + 8×8 WS Systolic Accelerator Implementation Specification v4.0*
- **Target Platform:** Digilent ZedBoard (AMD Zynq-7000 XC7Z020-CLG484-1)
- **Primary Toolchain:** AMD/Xilinx Vivado 2021.2 Design Suite
- **Instruction Set:** RISC-V RV32IM User-Level ISA
