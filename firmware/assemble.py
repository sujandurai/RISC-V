#!/usr/bin/env python3
"""
Phase 3 RISC-V RV32I firmware assembler.
Produces Verilog $readmemh-compatible hex (one 32-bit word per line).

Memory map:
  0x0000_0000 : IMEM (code)
  0x0000_8000 : DMEM start
  0x4000_0000 : SYS MMIO
  0x4000_0100 : ACC MMIO
  0x4000_0200 : DMA MMIO

DMA MMIO offsets from 0x4000_0200:
  0x00 DMA_CONTROL   [0]=START,[1]=CLR_DONE,[2]=CLR_ERR,[5:4]=MODE(00=ACT,01=WGT,10=RST)
  0x04 DMA_STATUS    [0]=BUSY,[1]=DONE,[2]=ERROR,[3]=TIMEOUT,[4]=REJECTED
  0x08 DMA_SRC_ADDR
  0x0C DMA_DST_ADDR
  0x10 DMA_LENGTH
  0x14 DMA_OWNER     [0]: 0=CPU, 1=DMA
  0x18 DMA_TIMEOUT
  0x1C DMA_ERROR_CODE

ACC MMIO offsets from 0x4000_0100:
  0x00 ACC_CONTROL   [0]=START,[1]=CLR_DONE
  0x04 ACC_STATUS    [0]=BUSY,[1]=DONE,[2]=RESULT_VALID,[3]=ERROR

Test matrices:
  A = all 0x01 bytes  (in DMEM at 0x8000, 64 bytes)
  B = all 0x01 bytes  (in DMEM at 0x8040, 64 bytes)
  C expected = all 8  (each INT32 result = 8, at 0x8080, 256 bytes)
  PASS/FAIL marker at 0x8180
"""

# ---- Register aliases -------------------------------------------------------
x = list(range(32))
x0=x[0];  x1=x[1];  x2=x[2];  x3=x[3];  x4=x[4];  x5=x[5]
x6=x[6];  x7=x[7];  x8=x[8];  x9=x[9];  x10=x[10]; x11=x[11]
x12=x[12];x13=x[13];x14=x[14];x15=x[15];x16=x[16];x17=x[17]
x18=x[18];x19=x[19];x20=x[20];x21=x[21];x22=x[22];x23=x[23]
x24=x[24];x25=x[25];x26=x[26];x27=x[27];x28=x[28];x29=x[29]
x30=x[30];x31=x[31]

# ---- Encoding helpers -------------------------------------------------------
def si(val, bits):
    """Sign-extend / mask to 'bits'-wide field."""
    return val & ((1 << bits) - 1)

def LUI(rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | 0x37

def ADDI(rd, rs1, imm12):
    return (si(imm12, 12) << 20) | (rs1 << 15) | (rd << 7) | 0x13

def ANDI(rd, rs1, imm12):
    return (si(imm12, 12) << 20) | (rs1 << 15) | (7 << 12) | (rd << 7) | 0x13

def SLLI(rd, rs1, shamt):
    return ((shamt & 0x1F) << 20) | (rs1 << 15) | (1 << 12) | (rd << 7) | 0x13

def LW(rd, rs1, imm12):
    return (si(imm12, 12) << 20) | (rs1 << 15) | (2 << 12) | (rd << 7) | 0x03

def SW(rs2, rs1, imm12):
    imm = si(imm12, 12)
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (2 << 12) | ((imm & 0x1F) << 7) | 0x23

def _branch(rs1, rs2, offset, funct3):
    off = si(offset, 13)
    return (((off>>12)&1)<<31) | (((off>>5)&0x3F)<<25) | (rs2<<20) | (rs1<<15) \
         | (funct3<<12) | (((off>>1)&0xF)<<8) | (((off>>11)&1)<<7) | 0x63

def BNE(rs1, rs2, offset): return _branch(rs1, rs2, offset, 1)
def BEQ(rs1, rs2, offset): return _branch(rs1, rs2, offset, 0)

def JAL(rd, offset):
    off = si(offset, 21)
    return (((off>>20)&1)<<31) | (((off>>1)&0x3FF)<<21) | (((off>>11)&1)<<20) \
         | (((off>>12)&0xFF)<<12) | (rd<<7) | 0x6F

# ---- Firmware generation ----------------------------------------------------
prog = []

def emit(instr):
    prog.append(instr & 0xFFFFFFFF)

def pc():
    return len(prog) * 4

# Helper: compute B-type offset to a previously recorded address
def back(target_addr):
    return target_addr - pc()   # offset from current (not-yet-added) instruction

# Helper: compute forward offset from a fixup slot
def fwd(slot_idx, target_addr):
    return target_addr - (slot_idx * 4)

# =============================================================================
# SETUP: load base addresses into registers
#   x12 = 0x4000_0000  (MMIO base)
#   x13 = 0x4000_0100  (ACC base)
#   x14 = 0x4000_0200  (DMA base)
#   x10 = 0x0000_8000  (DMEM base)
# =============================================================================
emit(LUI(x12, 0x40000))        # x12 = 0x40000000
emit(ADDI(x13, x12, 0x100))    # x13 = 0x40000100
emit(ADDI(x14, x12, 0x200))    # x14 = 0x40000200
emit(LUI(x10, 0x8))            # x10 = 0x00008000

# =============================================================================
# Write A matrix (all 0x01) to DMEM[0x8000..0x803F]
#   16 words of 0x01010101
# =============================================================================
emit(LUI(x16, 0x01010))        # x16 = 0x01010000
emit(ADDI(x16, x16, 0x101))    # x16 = 0x01010101
emit(ADDI(x17, x10, 0))        # x17 = 0x8000 (ptr)
emit(ADDI(x15, x0, 16))        # x15 = 16 (counter)

STORE_A = pc()
emit(SW(x16, x17, 0))
emit(ADDI(x17, x17, 4))
emit(ADDI(x15, x15, -1))
emit(BNE(x15, x0, back(STORE_A)))   # loop

# =============================================================================
# Write B matrix (all 0x01) to DMEM[0x8040..0x807F]
# =============================================================================
emit(ADDI(x17, x10, 0x40))     # x17 = 0x8040
emit(ADDI(x15, x0, 16))

STORE_B = pc()
emit(SW(x16, x17, 0))
emit(ADDI(x17, x17, 4))
emit(ADDI(x15, x15, -1))
emit(BNE(x15, x0, back(STORE_B)))

# =============================================================================
# DMA ACT_LOAD  (src=0x8000, len=64, mode=00, owner=1)
# =============================================================================
emit(SW(x10, x14, 8))          # DMA_SRC_ADDR = 0x8000
emit(ADDI(x11, x0, 64))
emit(SW(x11, x14, 16))         # DMA_LENGTH = 64
emit(ADDI(x11, x0, 1))
emit(SW(x11, x14, 20))         # DMA_OWNER = 1
emit(ADDI(x11, x0, 1))         # START | MODE=ACT_LOAD(00) = 0x01
emit(SW(x11, x14, 0))          # DMA_CONTROL → start

POLL_ACT = pc()
emit(LW(x11, x14, 4))          # DMA_STATUS
emit(ANDI(x11, x11, 2))        # DONE bit [1]
emit(BEQ(x11, x0, back(POLL_ACT)))  # loop until DONE

emit(ADDI(x11, x0, 2))
emit(SW(x11, x14, 0))          # CLEAR_DONE

# =============================================================================
# DMA WEIGHT_LOAD  (src=0x8040, len=64, mode=01)
# =============================================================================
emit(ADDI(x11, x10, 0x40))     # src = 0x8040
emit(SW(x11, x14, 8))          # DMA_SRC_ADDR
emit(ADDI(x11, x0, 0x11))      # START | MODE=WEIGHT(01<<4=0x10) = 0x11
emit(SW(x11, x14, 0))          # DMA_CONTROL → start

POLL_WT = pc()
emit(LW(x11, x14, 4))
emit(ANDI(x11, x11, 2))
emit(BEQ(x11, x0, back(POLL_WT)))

emit(ADDI(x11, x0, 2))
emit(SW(x11, x14, 0))          # CLEAR_DONE

# =============================================================================
# Release DMA ownership → CPU starts accelerator
# =============================================================================
emit(SW(x0, x14, 20))          # DMA_OWNER = 0
emit(ADDI(x11, x0, 1))
emit(SW(x11, x13, 0))          # ACC_CONTROL.START = 1

POLL_ACC = pc()
emit(LW(x11, x13, 4))          # ACC_STATUS
emit(ANDI(x11, x11, 2))        # DONE bit [1]
emit(BEQ(x11, x0, back(POLL_ACC)))

emit(ADDI(x11, x0, 2))
emit(SW(x11, x13, 0))          # ACC_CONTROL.CLEAR_DONE

# =============================================================================
# DMA RESULT_STORE  (dst=0x8080, len=256, mode=10)
# =============================================================================
emit(ADDI(x11, x0, 1))
emit(SW(x11, x14, 20))         # DMA_OWNER = 1
emit(ADDI(x11, x10, 0x80))     # dst = 0x8080
emit(SW(x11, x14, 12))         # DMA_DST_ADDR
emit(ADDI(x11, x0, 1))
emit(SLLI(x11, x11, 8))        # x11 = 256
emit(SW(x11, x14, 16))         # DMA_LENGTH = 256
emit(ADDI(x11, x0, 0x21))      # START | MODE=RESULT(10<<4=0x20) = 0x21
emit(SW(x11, x14, 0))          # DMA_CONTROL → start

POLL_RS = pc()
emit(LW(x11, x14, 4))
emit(ANDI(x11, x11, 2))
emit(BEQ(x11, x0, back(POLL_RS)))

emit(ADDI(x11, x0, 2))
emit(SW(x11, x14, 0))          # CLEAR_DONE
emit(SW(x0, x14, 20))          # DMA_OWNER = 0

# =============================================================================
# VERIFY results: C[i][j] = 8 for all 64 entries
# =============================================================================
emit(ADDI(x17, x10, 0x80))     # x17 = 0x8080 (result base)
emit(ADDI(x18, x0, 8))         # expected = 8
emit(ADDI(x15, x0, 64))        # counter

VERIFY = pc()
emit(LW(x11, x17, 0))          # load result
FAIL_BRANCH_IDX = len(prog)
emit(0)                         # placeholder: BNE x11, x18, fail
emit(ADDI(x17, x17, 4))
emit(ADDI(x15, x15, -1))
emit(BNE(x15, x0, back(VERIFY)))

# =============================================================================
# PASS: write 0x900D0001 to 0x8180, then spin
# =============================================================================
emit(LUI(x19, 0x8))            # x19 = 0x8000
emit(ADDI(x19, x19, 0x180))    # x19 = 0x8180
emit(LUI(x11, 0x900D0))        # x11 = 0x900D0000
emit(ADDI(x11, x11, 1))        # x11 = 0x900D0001
emit(SW(x11, x19, 0))          # *0x8180 = PASS

SPIN = pc()
emit(JAL(x0, 0))               # infinite spin

# =============================================================================
# FAIL: write 0xBAD00001 to 0x8180
# =============================================================================
FAIL_ADDR = pc()
emit(LUI(x19, 0x8))
emit(ADDI(x19, x19, 0x180))
emit(LUI(x11, 0xBAD00))        # x11 = 0xBAD00000
emit(ADDI(x11, x11, 1))        # x11 = 0xBAD00001
emit(SW(x11, x19, 0))
emit(JAL(x0, 0))               # infinite spin

# Fix up the forward branch to fail
prog[FAIL_BRANCH_IDX] = BNE(x11, x18, fwd(FAIL_BRANCH_IDX, FAIL_ADDR))

# =============================================================================
# Output
# =============================================================================
import os
out = os.path.join(os.path.dirname(__file__), 'phase3_matrix.hex')
with open(out, 'w') as f:
    for w in prog:
        f.write(f'{w:08x}\n')

print(f"Assembled {len(prog)} instructions ({len(prog)*4} bytes)")
print(f"PASS marker : address 0x8180, value 0x900D0001")
print(f"FAIL marker : address 0x8180, value 0xBAD00001")
print(f"Wrote {out}")
