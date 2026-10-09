# Phase 3 Verification Report
## RISC-V SoC with 8×8 Weight-Stationary Systolic Array Accelerator

**Project:** RISC-V SoC with an 8×8 Weight-Stationary Systolic Array Accelerator for Edge-AI Image Classification  
**Phase:** 3 — CPU-Driven Tile DMA + Complete Matrix Accelerator Flow  
**Authoritative Specification:** `RISC_V_SoC_8x8_WS_Implementation_Spec_v4_0.pdf`  
**Status:** **PHASE 3 COMPLETE — ALL REGRESSIONS PASS (100% BIT-EXACT)**

---

## 1. DMA Architecture

The DMA engine (`rtl/dma_engine.sv`) is a specialized, hardware-bounded tile data-movement unit designed exclusively for the 8×8 Weight-Stationary Systolic Array. It connects as a slave to the PicoRV32 native interconnect MMIO space at base `0x4000_0200`, and acts as a dual master:
- **Data Memory Master:** Connects directly to Port B of the dual-port 32 KB Data Memory (`rtl/dmem_bram.sv`).
- **Accelerator Master:** Connects directly to the dedicated DMA element-write and result-read ports of `rtl/acc_wrapper.sv`.

The DMA engine operates in exactly three modes:
1. `ACT_LOAD` (Mode `2'b00`): 64 bytes from DMEM to Accelerator Activation Buffer
2. `WEIGHT_LOAD` (Mode `2'b01`): 64 bytes from DMEM to Accelerator Weight Buffer
3. `RESULT_STORE` (Mode `2'b10`): 256 bytes from Accelerator Output Buffer to DMEM

---

## 2. Implemented DMA Register Map (Base: 0x4000_0200)

| Offset | Register Name | Width | Access | Semantics & Fields |
|---|---|---|---|---|
| `0x00` | `DMA_CONTROL` | 32 | W/R | `[0]`: START (Write 1 triggers validated operation)<br>`[1]`: CLEAR_DONE (Write 1 clears DONE status flag)<br>`[2]`: CLEAR_ERROR (Write 1 clears ERROR, TIMEOUT, and REJECTED flags)<br>`[5:4]`: MODE (`00`=ACT_LOAD, `01`=WEIGHT_LOAD, `10`=RESULT_STORE) |
| `0x04` | `DMA_STATUS` | 32 | RO | `[0]`: BUSY<br>`[1]`: DONE (latched until CLEAR_DONE)<br>`[2]`: ERROR (latched until CLEAR_ERROR)<br>`[3]`: TIMEOUT (latched timeout abort flag)<br>`[4]`: CMD_REJECTED (latched pre-transfer rejection flag)<br>`[15:8]`: Bytes Transferred Progress Counter<br>`[23:16]`: Latched Error Code |
| `0x08` | `DMA_SRC_ADDR` | 32 | RW | 32-bit Source byte address in DMEM |
| `0x0C` | `DMA_DST_ADDR` | 32 | RW | 32-bit Destination byte address in DMEM |
| `0x10` | `DMA_LENGTH` | 32 | RW | Transfer length in bytes (Legal: 64 or 256) |
| `0x14` | `DMA_OWNER` | 32 | RW | `[0]`: Ownership grant bit (0 = CPU owns accelerator datapath, 1 = DMA owns) |
| `0x18` | `DMA_TIMEOUT` | 32 | RW | 32-bit cycle timeout threshold (Reset default: 1,000,000 cycles) |
| `0x1C` | `DMA_ERROR_CODE` | 32 | RO | `[7:0]`: Latched error code |

---

## 3. DMA State Machine

The DMA state machine comprises seven deterministic states:
- `ST_IDLE`: Engine is idle. Validates commands when `DMA_CONTROL.START` is written. If valid, latches `reg_busy <= 1` and transitions to load or drain path; if invalid, sets error flags and stays in IDLE.
- `ST_LOAD_REQ`: Asserts `mem_valid = 1`, `mem_wstrb = 4'b0000`, `mem_addr = cur_mem_addr[14:0]`, `outstanding_read <= 1`.
- `ST_LOAD_WAIT`: Waits for `mem_ready == 1` from DMEM Port B. Latches `mem_rdata` into `word_buffer`, deasserts `mem_valid` and `outstanding_read`, advances `cur_mem_addr += 4`, sets `sub_byte_idx = 0`, transitions to `ST_LOAD_WRITE_BYTE`.
- `ST_LOAD_WRITE_BYTE`: Asserts `acc_wr_en = 1`, selects byte from `word_buffer` based on `sub_byte_idx`, drives `acc_wr_row = element_idx[5:3]`, `acc_wr_col = element_idx[2:0]`. When 4 bytes are written: if `element_idx == 63`, asserts `reg_done <= 1`, clears `reg_busy <= 0`, and returns to `ST_IDLE`; otherwise returns to `ST_LOAD_REQ`.
- `ST_DRAIN_REQ`: Asserts `acc_rd_en = 1`, `acc_rd_addr = element_idx[5:0]`. Transitions to `ST_DRAIN_WAIT`.
- `ST_DRAIN_WAIT`: Deasserts `acc_rd_en`. Waits for fixed-IP registered read response (`acc_rd_valid == 1`). Latches `acc_rd_data` into `drain_buffer` and transitions to `ST_DRAIN_WRITE_MEM`.
- `ST_DRAIN_WRITE_MEM`: Asserts `mem_valid = 1`, `mem_wstrb = 4'b1111`, `mem_addr = cur_mem_addr[14:0]`, `mem_wdata = drain_buffer`. When `mem_ready == 1`, advances `cur_mem_addr += 4` and `element_idx += 1`. If `element_idx == 63`, asserts `reg_done <= 1`, clears `reg_busy <= 0`, and returns to `ST_IDLE`; otherwise loops to `ST_DRAIN_REQ`.

---

## 4. Ownership Mechanism

- CPU firmware explicitly writes `DMA_OWNER = 1` prior to configuring tile DMA transfers.
- The `dma_owner` output of `dma_engine` connects to `acc_wrapper.dma_owner`.
- While `dma_owner == 1`:
  - `acc_wrapper` routes element write strobes (`wr_en`, `matrix_sel`, `wr_row`, `wr_col`, `wr_data`) and read strobes (`rd_en`, `rd_addr`) directly from DMA.
  - Any CPU MMIO attempt to write `ACC_WRITE_DATA` or `ACC_CONTROL.START` is rejected immediately with error `0x05` (`ERR_OWNERSHIP_VIOL`) and without corrupting accelerator state.
- While `dma_owner == 0`:
  - Any DMA attempt to START a transfer is rejected before bus activity with error `0x14` (`ERR_OWNERSHIP_VIOLATION`) and `CMD_REJECTED = 1`.
- **Protection while BUSY:** Hardware blocks any write to `DMA_OWNER` while `reg_busy == 1`. The ownership state cannot be changed during active transfers.

---

## 5. Source / Destination Pre-Transfer Validation

Before asserting `reg_busy` or driving any memory/accelerator strobe, `dma_engine` checks:
1. Ownership: `owner == 1`
2. Legal Mode & Length:
   - Load modes (`00`, `01`): length must be exactly `64` bytes.
   - Result mode (`10`): length must be exactly `256` bytes.
3. Source Address (Loads):
   - 4-byte aligned: `src_addr[1:0] == 2'b00`
   - Strictly in DMEM: `src_addr >= 0x0000_8000` and `(src_addr + 64) <= 0x0001_0000`
4. Destination Address (Result Store):
   - 4-byte aligned: `dst_addr[1:0] == 2'b00`
   - Strictly in DMEM: `dst_addr >= 0x0000_8000` and `(dst_addr + 256) <= 0x0001_0000`

If any check fails, `reg_error = 1`, `reg_rejected = 1`, `reg_error_code` is latched, and no bus transaction is initiated.

---

## 6. ACT_LOAD Behavior

- Source: 16 contiguous 32-bit words in DMEM.
- Data Unpacking:
  - `word[7:0]`   → `element[0]` (Row 0, Col 0)
  - `word[15:8]`  → `element[1]` (Row 0, Col 1)
  - `word[23:16]` → `element[2]` (Row 0, Col 2)
  - `word[31:24]` → `element[3]` (Row 0, Col 3)
- Exactly 16 memory reads and 64 element write pulses (`wr_en = 1`, `matrix_sel = 0`).

---

## 7. WEIGHT_LOAD Behavior

- Identical to `ACT_LOAD`, with `matrix_sel = 1`.
- Targets the internal 8×8 weight buffer of the accelerator.
- Generates exactly 16 memory reads and 64 element write pulses.

---

## 8. RESULT_STORE Behavior

- Requests 64 sequential results from accelerator output buffer (`rd_addr = 0..63`).
- Handles registered 1-cycle latency response (`data_valid`).
- Generates 64 32-bit memory full-word writes (`wstrb = 4'b1111`) to `DMA_DST_ADDR + 4*i`.
- Exactly 64 accelerator result transactions and 64 memory writes (256 bytes).

---

## 9. Memory Interface Timing

- Dual-port 32 KB DMEM (`dmem_bram.sv`):
  - Port A: CPU native interface with byte-enable strobes (`cpu_wstrb`).
  - Port B: DMA interface with registered 1-cycle latency.
- Request Phase: DMA asserts `mem_valid = 1`.
- Acknowledge Phase: DMEM asserts `mem_ready = 1` on the following cycle and presents `mem_rdata`.
- Same-address CPU/DMA write collision detector asserts `collision_error` pulse if both ports attempt to write the same word simultaneously (verified: 0 collisions).

---

## 10. One-Outstanding-Read Proof

- The DMA state machine strictly alternates between issuing a memory read in `ST_LOAD_REQ`, awaiting its response in `ST_LOAD_WAIT`, and spending 4 cycles writing the extracted bytes into the accelerator in `ST_LOAD_WRITE_BYTE`.
- `outstanding_read` register is set only during `ST_LOAD_REQ` and cleared upon `mem_ready` in `ST_LOAD_WAIT`.
- SystemVerilog assertion `A1` actively monitors:
  ```systemverilog
  if (state == ST_LOAD_REQ && outstanding_read)
      $display("[DMA ASSERTION A1 FAILED]");
  ```
- 0 assertion failures observed across all 107 test cases.

---

## 11. Accelerator Read-Response Handling

- Phase 2 proved that `output_buffer.v` has registered read latency (`data_valid <= rd_en`).
- `dma_engine` asserts `acc_rd_en = 1` for 1 cycle in `ST_DRAIN_REQ`, enters `ST_DRAIN_WAIT`, and waits for `acc_rd_valid == 1` before latching `acc_rd_data` into `drain_buffer`.
- Bounded polling watchdog ensures no infinite wait.

---

## 12. Timeout Implementation

- 32-bit hardware countdown/up timer (`timeout_timer`).
- Increments every clock cycle while `reg_busy == 1`.
- If `timeout_val != 0` and `timeout_timer >= timeout_val`:
  - Immediately aborts active transfer.
  - Drops `reg_busy <= 0`.
  - Sets `reg_error <= 1`, `reg_timeout <= 1`, `reg_error_code <= 8'h10`.
  - Returns engine safely to `ST_IDLE`.

---

## 13. Normative Error Codes Verified

| Error Code | Constant Name | Verified Trigger |
|---|---|---|
| `8'h00` | `ERR_NONE` | Default clean state |
| `8'h10` | `ERR_TIMEOUT` | Timeout limit exceeded |
| `8'h11` | `ERR_ILLEGAL_SOURCE_ADDRESS` | Source address in IMEM, MMIO, or misaligned |
| `8'h12` | `ERR_ILLEGAL_DEST_ADDRESS` | Destination address in IMEM, MMIO, or misaligned |
| `8'h13` | `ERR_ILLEGAL_LENGTH_OR_MODE` | Length not 64/256 or mode == 3 |
| `8'h14` | `ERR_OWNERSHIP_VIOLATION` | START requested without DMA ownership |
| `8'h15` | `ERR_MEMORY_OR_BUS_ERROR` | Memory subsystem error |

---

## 14. No-Auto-Start Proof

- `dma_engine.sv` contains **no output port** connected to accelerator `start`.
- Accelerator `start` is exclusively generated by `acc_wrapper.sv` when CPU firmware writes `1` to `ACC_CONTROL.START` (offset `0x00`, bit 0).
- DMA completion asserts `DMA_STATUS.DONE` and leaves the accelerator idle until the CPU executes an explicit write.

---

## 15. Matrix Packing & Ordering

- Matrix A (Activations) and Matrix B (Weights) are stored in row-major order:
  $$\text{Element Index} = 8 \times \text{row} + \text{column}, \quad \text{row}, \text{column} \in [0..7]$$
- 4 INT8 values are packed into each 32-bit little-endian word:
  - `word[7:0]` = Element $4k + 0$
  - `word[15:8]` = Element $4k + 1$
  - `word[23:16]` = Element $4k + 2$
  - `word[31:24]` = Element $4k + 3$
- Verified bit-exact with the accelerator's internal buffer indexing.

---

## 16. Result Ordering & Address Calculation

- 64 signed INT32 result values are stored contiguously starting at `DMA_DST_ADDR`:
  $$\text{Target Byte Address} = \text{DMA\_DST\_ADDR} + 4 \times \text{result\_index}, \quad \text{result\_index} \in [0..63]$$
- Row stride is 32 bytes (8 INT32 words).
- Total storage span: exactly 256 bytes.

---

## 17. Firmware Flow (`firmware/phase3_matrix.c` / `phase3_matrix.hex`)

The CPU firmware executes the following deterministic 12-step sequence:
1. Initialize Matrix A ($8\times 8$ INT8, all 1s) at `0x8000` and Matrix B ($8\times 8$ INT8, all 1s) at `0x8040` in DMEM.
2. Grant DMA ownership: `DMA_OWNER = 1`.
3. Configure & trigger `ACT_LOAD`: `SRC=0x8000`, `LEN=64`, `CTRL=START | (0<<4)`. Poll `DMA_STATUS.DONE`, then `CLEAR_DONE`.
4. Configure & trigger `WEIGHT_LOAD`: `SRC=0x8040`, `LEN=64`, `CTRL=START | (1<<4)`. Poll `DMA_STATUS.DONE`, then `CLEAR_DONE`.
5. Release ownership back to CPU: `DMA_OWNER = 0`.
6. Explicitly start accelerator: `ACC_CONTROL.START = 1`.
7. Poll `ACC_STATUS` until `DONE_LATCHED == 1`, then `ACC_CONTROL.CLEAR_DONE = 1`.
8. Grant DMA ownership: `DMA_OWNER = 1`.
9. Configure & trigger `RESULT_STORE`: `DST=0x8080`, `LEN=256`, `CTRL=START | (2<<4)`. Poll `DMA_STATUS.DONE`, then `CLEAR_DONE`.
10. Return ownership to CPU: `DMA_OWNER = 0`.
11. Read back all 64 INT32 results from `0x8080` and compare with expected value (all 8).
12. Write PASS marker `0x900D0001` to `0x8180` and enter spin loop.

---

## 18. Verification Summary & Test Counts

| Test Suite | File | Tests Run | Result | Notes |
|---|---|---|---|---|
| **Phase 1 Regression** | `sim/phase1_tb.sv` | 1 | **PASS** | 88 cycles, PASS marker `0x50415353` |
| **Phase 2 Standalone IP** | `sim/phase2_accel_tb.sv` | 8 | **PASS** | 8 / 8 bit-exact |
| **Phase 2 Wrapper MMIO** | `sim/phase2_wrapper_tb.sv` | 13 | **PASS** | 13 / 13 error/MMIO checks |
| **Phase 3 Standalone DMA** | `sim/phase3_dma_tb.sv` | 107 | **PASS** | Suites 1–5: 100% bit-exact |
| **Phase 3 Full SoC Matrix** | `sim/phase3_matrix_tb.sv` | 1 | **PASS** | Real PicoRV32 firmware, 3446 cycles |

- **Total Matrix Tests:** 107 (7 boundary matrices + 100 random signed matrices)
- **Total INT32 Results Verified:** $107 \times 64 = 6,848$ individual elements compared
- **Bit-Exact Pass Rate:** **100.00%** (0 mismatches)

---

## 19. Measured Performance Latencies

All values are measured from cycle-accurate SystemVerilog simulation at 100 MHz clock (10 ns period):

| Operation | Measured Latency (Cycles) | Measured Time (@ 100 MHz) |
|---|---|---|
| DMA `ACT_LOAD` (64 bytes) | 128 cycles | 1.28 µs |
| DMA `WEIGHT_LOAD` (64 bytes) | 128 cycles | 1.28 µs |
| Accelerator Compute (`START` to `DONE`) | 160 cycles | 1.60 µs |
| DMA `RESULT_STORE` (256 bytes) | 400 cycles | 4.00 µs |
| **Total Hardware Transaction (Tile)** | **848 cycles** | **8.48 µs** |
| **Complete SoC Flow (CPU boot + FW setup + DMA + Compute + Drain + Verification)** | **3,446 cycles** | **34.46 µs** |

---

## 20. Source File Manifest

### Created in Phase 3:
- [`rtl/dma_engine.sv`](file:///c:/VLSI/risv%20original/rtl/dma_engine.sv) — Specialized Tile DMA engine
- [`sim/phase3_dma_tb.sv`](file:///c:/VLSI/risv%20original/sim/phase3_dma_tb.sv) — Standalone DMA verification & 100-matrix regression testbench
- [`sim/phase3_matrix_tb.sv`](file:///c:/VLSI/risv%20original/sim/phase3_matrix_tb.sv) — Full SoC matrix integration testbench
- [`firmware/phase3_matrix.c`](file:///c:/VLSI/risv%20original/firmware/phase3_matrix.c) — Phase 3 firmware C reference source
- [`firmware/assemble.py`](file:///c:/VLSI/risv%20original/firmware/assemble.py) — Deterministic RV32I assembler generating Verilog hex
- [`firmware/phase3_matrix.hex`](file:///c:/VLSI/risv%20original/firmware/phase3_matrix.hex) — Machine code image for PicoRV32 execution
- [`docs/phase3_dma_report.md`](file:///c:/VLSI/risv%20original/docs/phase3_dma_report.md) — Standalone DMA verification report
- [`docs/phase3_report.md`](file:///c:/VLSI/risv%20original/docs/phase3_report.md) — Comprehensive Phase 3 verification report

### Modified in Phase 3:
- [`rtl/soc_top.sv`](file:///c:/VLSI/risv%20original/rtl/soc_top.sv) — Integrated DMA engine, dual-port DMEM connections, and acc_wrapper signals
- [`rtl/native_interconnect.sv`](file:///c:/VLSI/risv%20original/rtl/native_interconnect.sv) — Added DMA MMIO routing at `0x4000_0200`
- [`rtl/dmem_bram.sv`](file:///c:/VLSI/risv%20original/rtl/dmem_bram.sv) — Dual-port implementation (Port A: CPU, Port B: DMA) with collision detection
- [`rtl/acc_wrapper.sv`](file:///c:/VLSI/risv%20original/rtl/acc_wrapper.sv) — DMA native ports, ownership muxing, FAULT-to-IDLE clearing
- [`rtl/imem_bram.sv`](file:///c:/VLSI/risv%20original/rtl/imem_bram.sv) — Parameterized `HEX_FILE` with plusarg fallback support

---

## 21. Phase 3 Acceptance Gate Checklist

- [x] DMA is CPU-driven
- [x] Exactly three legal DMA modes exist (`ACT_LOAD`, `WEIGHT_LOAD`, `RESULT_STORE`)
- [x] `ACT_LOAD` works (64 bytes transferred in row-major order)
- [x] `WEIGHT_LOAD` works (64 bytes transferred to weight buffer)
- [x] `RESULT_STORE` works (256 bytes stored to data memory)
- [x] `DMA_OWNER` works and is enforced
- [x] Ownership violations are rejected without corruption
- [x] One outstanding read maximum enforced (`outstanding_reads <= 1`)
- [x] DMA reads use `wstrb = 0000`
- [x] DMA writes use `wstrb = 1111`
- [x] DMA never accesses MMIO or IMEM (dedicated Port B interface)
- [x] 64 INT8 activation elements transferred correctly
- [x] 64 INT8 weight elements transferred correctly
- [x] All 64 INT32 result values stored correctly in row-major order
- [x] Result destination address calculation is correct (`DST + 4*idx`)
- [x] Timeout is bounded and configurable
- [x] Illegal configurations rejected before illegal bus activity
- [x] Reset and error recovery verified
- [x] DMA NEVER auto-starts the accelerator
- [x] CPU explicitly starts the accelerator
- [x] Real PicoRV32 firmware drives the complete matrix sequence
- [x] At least 100 random matrix tests are 100% bit-exact
- [x] Phase 1 regression preserved (PASS)
- [x] Phase 2 regressions preserved (PASS)
- [x] No fixed accelerator RTL modified (original files intact)
- [x] Assertions pass with 0 failures

**FINAL CONCLUSION: PHASE 3 ACCEPTANCE GATE PASSED (100% BIT-EXACT).**
