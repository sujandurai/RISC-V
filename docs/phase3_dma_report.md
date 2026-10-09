# Phase 3 DMA Engine Verification Report

**Project:** RISC-V SoC with 8×8 Weight-Stationary Systolic Array Accelerator for Edge-AI Image Classification  
**Module:** Tile DMA Engine (`rtl/dma_engine.sv`)  
**Specification:** `RISC_V_SoC_8x8_WS_Implementation_Spec_v4_0.pdf`  
**Status:** ALL TESTS PASS (100% Bit-Exact)

---

## 1. DMA Engine Architecture & Capabilities

The Phase 3 DMA engine is a specialized tile data-movement unit designed strictly to interface between the 32 KB Data Memory (DMEM Port B) and the 8×8 Weight-Stationary Systolic Array accelerator.

### Supported Modes:
1. **ACT_LOAD (Mode 00):**
   - Source: DMEM (4-byte aligned, 0x0000_8000 to 0x0000_FFC0)
   - Destination: Accelerator Activation Storage (`matrix_select = 0`)
   - Length: Exactly 64 bytes (16 32-bit words)
   - Unpacking: 4 INT8 elements per 32-bit word in row-major order:
     - `byte0 [7:0]   -> element 4*i + 0`
     - `byte1 [15:8]  -> element 4*i + 1`
     - `byte2 [23:16] -> element 4*i + 2`
     - `byte3 [31:24] -> element 4*i + 3`
2. **WEIGHT_LOAD (Mode 01):**
   - Source: DMEM (4-byte aligned, 0x0000_8000 to 0x0000_FFC0)
   - Destination: Accelerator Weight Storage (`matrix_select = 1`)
   - Length: Exactly 64 bytes (16 32-bit words)
   - Unpacking: Identical row-major INT8 unpacking
3. **RESULT_STORE (Mode 10):**
   - Source: Accelerator Output Storage (`rd_addr = 0..63`)
   - Destination: DMEM (4-byte aligned, 0x0000_8000 to 0x0000_FF00)
   - Length: Exactly 256 bytes (64 32-bit INT32 results)
   - Drainage: Row-major order `result_index = 0..63`
   - Memory Write: Full-word write `wstrb = 4'b1111` to `DMA_DST_ADDR + 4*result_index`

---

## 2. Authoritative v4.0 Register Map (Base: 0x4000_0200)

| Offset | Register Name | Width | Type | Field Description |
|---|---|---|---|---|
| `0x00` | `DMA_CONTROL` | 32 | W/R | `[0]`: START<br>`[1]`: CLEAR_DONE<br>`[2]`: CLEAR_ERROR<br>`[5:4]`: MODE (`00`=ACT, `01`=WGT, `10`=RES) |
| `0x04` | `DMA_STATUS` | 32 | RO | `[0]`: BUSY<br>`[1]`: DONE<br>`[2]`: ERROR<br>`[3]`: TIMEOUT<br>`[4]`: CMD_REJECTED<br>`[15:8]`: Progress / Bytes Done<br>`[23:16]`: Error Code |
| `0x08` | `DMA_SRC_ADDR` | 32 | RW | Source byte address (DMEM only) |
| `0x0C` | `DMA_DST_ADDR` | 32 | RW | Destination byte address (DMEM only) |
| `0x10` | `DMA_LENGTH` | 32 | RW | Transfer length in bytes (64 or 256) |
| `0x14` | `DMA_OWNER` | 32 | RW | `[0]`: 0 = CPU owns data path, 1 = DMA owns |
| `0x18` | `DMA_TIMEOUT` | 32 | RW | Cycle timeout threshold (default: 1,000,000) |
| `0x1C` | `DMA_ERROR_CODE` | 32 | RO | `[7:0]`: Latched error code |

---

## 3. Strict Architectural Rules Verified

- **One Outstanding Read Rule:** The DMA issues at most one memory read request at any given time. The next read is only issued after the previous read data has been received and completely transferred into the accelerator buffer.
- **Dedicated Port B Memory Access:** DMA memory bus connects directly to Port B of `dmem_bram.sv`. IMEM and MMIO spaces are physically unreachable by DMA.
- **Pre-transfer Validation:** Source alignment/range, destination alignment/range, length, mode, and ownership are validated *before* any memory or accelerator activity. Illegal requests are rejected immediately with appropriate error codes.
- **No Auto-Start:** The DMA has no connection to accelerator START. Every accelerator computation is explicitly triggered by the CPU via `ACC_CONTROL.START`.
- **Bounded Timeout:** Programmable timeout counter automatically aborts stuck operations and enters a deterministic idle state with `ERR_TIMEOUT` (0x10).
- **Ownership Protocol:** CPU cannot modify accelerator datapath while DMA owns it (`dma_owner = 1`). DMA cannot start without ownership. Ownership cannot be changed while DMA is `BUSY`.

---

## 4. Standalone DMA Simulation Results (`sim/phase3_dma_tb.sv`)

### Test Suite Summary:
1. **Suite 1: Ownership Protocol Tests**
   - 1A: DMA START without ownership (`owner = 0`) -> **PASS** (rejected with `0x14` `ERR_OWNERSHIP_VIOLATION`)
   - 1B: CPU write to accelerator while DMA owns -> **PASS** (rejected by `acc_wrapper` with `0x05`)
2. **Suite 2: Illegal Configuration Tests**
   - 2A: Source address in IMEM (`0x1000`) -> **PASS** (rejected with `0x11` `ERR_ILLEGAL_SOURCE_ADDRESS`)
   - 2B: Source address in MMIO (`0x4000_0000`) -> **PASS** (rejected with `0x11` `ERR_ILLEGAL_SOURCE_ADDRESS`)
   - 2C: Destination address in IMEM (`0x0000`) -> **PASS** (rejected with `0x12` `ERR_ILLEGAL_DEST_ADDRESS`)
   - 2D: Misaligned source address (`0x8002`) -> **PASS** (rejected with `0x11` `ERR_ILLEGAL_SOURCE_ADDRESS`)
   - 2E: Illegal transfer length (100 bytes) -> **PASS** (rejected with `0x13` `ERR_ILLEGAL_LENGTH_OR_MODE`)
   - 2F: Illegal mode (Mode 3) -> **PASS** (rejected with `0x13` `ERR_ILLEGAL_LENGTH_OR_MODE`)
3. **Suite 3: Timeout & Recovery Tests**
   - 3A: Short timeout (5 cycles) on active transfer -> **PASS** (aborted cleanly, STATUS indicates TIMEOUT, code `0x10`)
   - 3B: Clear error & reset -> **PASS** (engine returned cleanly to IDLE)
4. **Suite 4: Boundary Value Matrix Tests (7 Matrices)**
   - B1: All Zeros -> **PASS** (64/64 matched)
   - B2: All +1 -> **PASS** (64/64 matched)
   - B3: All -1 -> **PASS** (64/64 matched)
   - B4: Max Positive +127 -> **PASS** (64/64 matched)
   - B5: Min Negative -128 -> **PASS** (64/64 matched)
   - B6: Alternating signs -> **PASS** (64/64 matched)
   - B7: Sparse diagonal -> **PASS** (64/64 matched)
5. **Suite 5: 100 Random Signed Matrices Regression**
   - 100 signed 8×8 matrices with uniform random inputs in `[-128, +127]`
   - Bit-exact software GEMM scoreboard comparison across all 6,400 result elements
   - **PASS: 100 / 100 matrices (100.00% pass rate)**

---

## 5. Measured Hardware Latencies (Single 8×8 Tile)

| Step | Operation | Measured Cycles | Time @ 100 MHz |
|---|---|---|---|
| 1 | DMA `ACT_LOAD` (64 bytes) | 128 cycles | 1.28 µs |
| 2 | DMA `WEIGHT_LOAD` (64 bytes) | 128 cycles | 1.28 µs |
| 3 | Accelerator Compute (`START` to `DONE`) | 160 cycles | 1.60 µs |
| 4 | DMA `RESULT_STORE` (256 bytes) | 400 cycles | 4.00 µs |
| **Total** | **Complete Single-Tile Flow** | **848 cycles** | **8.48 µs** |
