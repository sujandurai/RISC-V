# Digilent ZedBoard Hardware Bring-Up & Validation Guide

## 1. Overview
This document provides instructions for bringing up and validating the **RISC-V SoC with 8×8 Weight-Stationary Systolic Array Accelerator** on a physical **Digilent ZedBoard (AMD Zynq-7000 XC7Z020-CLG484-1)**.

The system is implemented as a **PL-only design**:
- No Zynq Processing System (PS) or ARM core is activated.
- No PS DDR or AXI Interconnect is utilized.
- All computation, memories (IMEM 32 KiB, DMEM 224 KiB), systolic accelerator, DMA engine, and UART peripheral reside entirely within the 7-Series FPGA fabric.

---

## 2. Hardware Requirements & Interface Connections

### 2.1 Required Equipment
1. **Digilent ZedBoard** (Rev D, E, or F) with 12V 3A power supply.
2. **Micro-USB Programming Cable** connected to ZedBoard `PROG` / JTAG port (`J17`).
3. **External USB-to-UART Adapter (3.3V)** (e.g., FTDI FT232RL, Silicon Labs CP2102, or Digilent Pmod USBUART).
4. Host PC running Windows or Linux with Python 3.8+ and `pyserial`.

### 2.2 Pmod JA Pinout & Wiring (Bank 13 — 3.3V LVCMOS)
The PL UART peripheral is mapped to Pmod JA on Bank 13:

| Pmod JA Pin | FPGA Pin | Signal Name | Connection to USB-UART Adapter |
|---|---|---|---|
| **Pin 1 (JA1)** | `Y11` | `uart_rx` | Connect to **TX** of USB-UART adapter (Host $\to$ FPGA) |
| **Pin 2 (JA2)** | `AA11`| `uart_tx` | Connect to **RX** of USB-UART adapter (FPGA $\to$ Host) |
| **Pin 5 (GND)** | `GND` | Ground | Connect to **GND** of USB-UART adapter |
| **Pin 6 (VCC)** | `3.3V`| Power | *Do not connect* (adapter is self-powered via USB) |

> [!CAUTION]
> Ensure the USB-to-UART adapter is set to **3.3V logic level**. Connecting a 5.0V UART adapter will damage the FPGA I/O bank.

### 2.3 System Controls
- **Clock Source**: 100 MHz single-ended oscillator connected to pin `Y9` (GCLK).
- **Reset Switch (`SW0`, pin `F22`)**:
  - `SW0` **DOWN**: Reset asserted (system held in reset, CPU paused).
  - `SW0` **UP**: Reset released (PicoRV32 boots and initializes peripherals).

---

## 3. FPGA Bitstream Generation & Programming

### 3.1 Generating the Bitstream (Automated Script)
Launch Vivado 2021.2 in batch mode to execute synthesis, placement, routing, timing closure, and bitstream generation:
```powershell
vivado -mode batch -source scripts/build_vivado.tcl
```
The generated bitstream will be located at:
`build/soc_top.bit`

### 3.2 Programming the FPGA via Vivado Hardware Manager
1. Power ON the ZedBoard (12V switch `SW8`).
2. Open Vivado Hardware Manager and connect to the local hardware target:
   ```powershell
   vivado -mode tcl
   open_hw_manager
   connect_hw_server
   open_hw_target
   set_property PROGRAM.FILE {build/soc_top.bit} [get_hw_devices xc7z020_1]
   program_hw_devices [get_hw_devices xc7z020_1]
   ```
3. Verify that the **DONE LED (LD12)** illuminates blue, indicating the FPGA PL fabric is configured.

---

## 4. Host Software Execution & Demonstration

### 4.1 Host Environment Setup
Install required Python dependencies on the host machine:
```bash
pip install pyserial numpy
```

### 4.2 Interactive Verification via `host/uart_host.py`
Identify the serial port assigned to your USB-UART adapter (e.g., `COM3` on Windows, `/dev/ttyUSB0` on Linux).

#### Step 1: Handshake Test (`HELLO`)
```bash
python host/uart_host.py --port COM3 --baud 115200 --hello
```
Expected output:
```
Sending HELLO frame (7 bytes)...
Received ACK from FPGA!
Handshake successful: SoC is alive and communicating at 115200 baud.
```

#### Step 2: Single-Tile Systolic Array Smoke Test
```bash
python host/uart_host.py --port COM3 --baud 115200 --smoke
```
Expected output:
```
Running 8x8 WS Systolic Array Tile GEMM smoke test...
RESULT frame received (45 bytes):
  Status: SUCCESS
  Measured Execution Latency: 3,446 cycles (34.46 us at 100 MHz)
  All 64 tile outputs bit-exact with CPU software reference!
```

#### Step 3: Full End-to-End Image Classification
Stream a 28×28 INT8 normalized image and classify:
```bash
python host/uart_host.py --port COM3 --baud 115200 --image model/sample_digit_7.bin
```
Expected output:
```
Streaming 784-byte tensor in 4 chunks (196 bytes each)...
  Chunk 0 (offset 0) ACKed.
  Chunk 1 (offset 196) ACKed.
  Chunk 2 (offset 392) ACKed.
  Chunk 3 (offset 588) ACKed.
Sending RUN command...
RESULT frame received:
  Predicted Class:        7
  Hardware Latency:       18,940 cycles (189.4 us at 100 MHz)
  UART Transfer Time:     68.1 ms (at 115200 baud)
  Total Latency:          68.3 ms
  Logits:
    Class 0:   -1420
    Class 1:    -810
    Class 2:     -45
    Class 3:     120
    Class 4:    -512
    Class 5:    -310
    Class 6:   -1890
    Class 7:    4820  <-- MAX (Predicted)
    Class 8:    -240
    Class 9:     610
```

#### Step 4: Batch Dataset Validation
Run all 12 validation vectors from `model/test_dataset.bin`:
```bash
python host/uart_host.py --port COM3 --baud 115200 --dataset model/test_dataset.bin --manifest model/test_manifest.json
```
Expected output:
```
Running 12 validation vectors...
[Image 00] Gold: 0 | Predicted: 0 | Latency: 18,940 cycles | MATCH
[Image 01] Gold: 1 | Predicted: 1 | Latency: 18,940 cycles | MATCH
...
[Image 11] Gold: 8 | Predicted: 8 | Latency: 18,940 cycles | MATCH
============================================================
Batch Classification Accuracy: 12/12 (100.0%)
Mean Inference Latency: 18,940 cycles (189.40 us at 100 MHz)
Status: HARDWARE ACCEPTANCE CRITERIA MET
============================================================
```

---

## 5. Troubleshooting & Diagnostics

| Symptom | Probable Cause | Corrective Action |
|---|---|---|
| **DONE LED (LD12) does not turn on** | Bitstream loading failed or JTAG disconnect | Check USB cable; ensure 12V power switch is ON; re-program bitstream. |
| **No response to HELLO (timeout)** | Wrong COM port or reversed RX/TX | Verify COM port in Device Manager; swap JA1 and JA2 connections; verify `SW0` is UP (not in reset). |
| **NACK received with code `0x11`** | Baud rate mismatch or line noise | Ensure host baud is set to 115,200 baud; check ground wire between adapter and ZedBoard. |
| **NACK received with code `0x12`** | Chunk payload exceeds 256 bytes | Verify `uart_host.py` uses chunk size $\le 254$ bytes (default 196 bytes). |
