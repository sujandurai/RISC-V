# Phase 1 Implementation Report: RISC-V SoC Foundation

## 1. Files Created/Modified
**RTL:**
- `rtl/soc_top.sv` (Top-level integration)
- `rtl/native_interconnect.sv` (Address decoder and bus router)
- `rtl/reset_ctrl.sv` (Synchronous reset generator)
- `rtl/imem_bram.sv` (32 KiB Instruction Memory)
- `rtl/dmem_bram.sv` (32 KiB Data Memory)
- `rtl/sys_regs.sv` (System MMIO registers and error latching)
- `rtl/picorv32.v` (Official PicoRV32 IP)

**Firmware:**
- `firmware/phase1.hex` (Directly assembled RV32I bare-metal firmware)

**Simulation:**
- `sim/phase1_tb.sv` (Testbench orchestrating execution and assertions)

## 2. Architecture Summary
A minimal PL-only SoC was implemented for the Zynq-7020 (ZedBoard). PicoRV32 uses its native valid/ready memory interface to communicate with a strictly compliant `native_interconnect`. 
The interconnect routes to IMEM, DMEM, and SYS MMIO, raising `bus_error` for unmapped, unimplemented, unaligned, or partial MMIO writes without stalling the CPU. 
All clocks are derived directly from a single 100 MHz source, and the active-low external reset is synchronized natively via `reset_ctrl`. 

## 3. Exact Memory/Address Map Implemented
| Region | Address Range | Status |
|--------|---------------|--------|
| IMEM | `0x0000_0000` - `0x0000_7FFF` | Implemented (32 KiB) |
| DMEM | `0x0000_8000` - `0x0000_FFFF` | Implemented (32 KiB) |
| INPUT | `0x0001_0000` - `0x0001_3FFF` | Reserved (Triggers Fault) |
| WEIGHTS | `0x0001_4000` - `0x0002_BFFF` | Reserved (Triggers Fault) |
| FEATURE_A | `0x0002_C000` - `0x0003_3FFF` | Reserved (Triggers Fault) |
| FEATURE_B | `0x0003_4000` - `0x0003_BFFF` | Reserved (Triggers Fault) |
| OUTPUT | `0x0003_C000` - `0x0003_FFFF` | Reserved (Triggers Fault) |
| SYS MMIO | `0x4000_0000` - `0x4000_00FF` | Implemented |
| ACC MMIO | `0x4000_0100` - `0x4000_01FF` | Reserved (Triggers Fault) |
| DMA MMIO | `0x4000_0200` - `0x4000_02FF` | Reserved (Triggers Fault) |
| UART MMIO | `0x4000_0300` - `0x4000_03FF` | Reserved (Triggers Fault) |

## 4. PicoRV32 Configuration
The official PicoRV32 parameter set is used to lock in the required capabilities:
- `ENABLE_DIV` = 1
- `ENABLE_FAST_MUL` = 1
- `PROGADDR_RESET` = `32'h0000_0000`
- `STACKADDR` = `32'h0000_FFF0`
- All other parameters conform to the `soc_top.sv` instantiation matching v4.0.

## 5. Firmware Build Method
Since a RISC-V toolchain was not found on the local environment, the `phase1.hex` image was directly hand-assembled using verified RV32I opcodes to prevent blocking. 
The image exercises:
1. IMEM boot and fetch
2. DMEM read/write
3. Native arithmetic
4. Cycle counter read
5. Intentional invalid access (0x5000_0000)
6. SYS_STATUS validation
7. SYS_CONTROL clearing of sticky `bus_error`
8. Writing `0x50415353` ('PASS') to DMEM at the end.

## 6. Simulation Command
```bash
cd sim
iverilog -g2012 -o phase1.vvp phase1_tb.sv ../rtl/soc_top.sv ../rtl/picorv32.v ../rtl/native_interconnect.sv ../rtl/imem_bram.sv ../rtl/dmem_bram.sv ../rtl/sys_regs.sv ../rtl/reset_ctrl.sv
vvp phase1.vvp
```

## 7. Simulation Result
Simulation reached completion at cycle 88. Output:
```
========================================
           PHASE1_PASS                  
========================================
Cycle count: 88
```

## 8. Assertion Results
- The testbench tracks bus stalls dynamically. No valid transaction exceeded the hard threshold (10 cycles).
- Unmapped memory addresses correctly terminated immediately (did not hang).
- Zero assertion failures occurred.

## 9. Tool/Environment Issues
- `git` was missing from the environment, so `picorv32.v` was downloaded via a direct HTTP `Invoke-WebRequest`.
- A RISC-V GCC cross-compiler was missing, so a hand-assembled hex payload was generated to exercise all exact Phase 1 logic requirements without failing the toolchain dependency.

## 10. Commit/Source Hashes
- **PicoRV32:** Master branch at `https://raw.githubusercontent.com/YosysHQ/picorv32/master/picorv32.v`

## 11. Conclusion
**PHASE 1 is a PASS.** The PicoRV32 native CPU foundation has been functionally validated. The environment is now ready for Phase 2 (Fixed Accelerator + Wrapper).
