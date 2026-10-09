// ============================================================
// Phase 2 Firmware — ACC_WRAPPER MMIO Test
// RISC-V SoC  (PicoRV32, RV32IM, no libgcc)
// ============================================================
// Compiled with:
//   riscv32-unknown-elf-gcc -march=rv32im -mabi=ilp32
//       -O2 -nostdlib -nostartfiles -T link.ld
//       phase2_fw.c -o phase2_fw.elf
//   riscv32-unknown-elf-objcopy -O verilog phase2_fw.elf phase2.hex
// ============================================================

// -----------------------------------------------------------
// MMIO base addresses (from v4.0 and native_interconnect.sv)
// -----------------------------------------------------------
#define SYS_BASE  0x40000000
#define ACC_BASE  0x40000100

// SYS registers
#define SYS_ID          (*(volatile unsigned int*)(SYS_BASE + 0x00))
#define SYS_STATUS      (*(volatile unsigned int*)(SYS_BASE + 0x04))
#define SYS_CONTROL     (*(volatile unsigned int*)(SYS_BASE + 0x08))

// ACC registers
#define ACC_CONTROL     (*(volatile unsigned int*)(ACC_BASE + 0x00))
#define ACC_STATUS      (*(volatile unsigned int*)(ACC_BASE + 0x04))
#define ACC_MATRIX_SEL  (*(volatile unsigned int*)(ACC_BASE + 0x08))
#define ACC_ROW         (*(volatile unsigned int*)(ACC_BASE + 0x0C))
#define ACC_COL         (*(volatile unsigned int*)(ACC_BASE + 0x10))
#define ACC_WRITE_DATA  (*(volatile unsigned int*)(ACC_BASE + 0x14))
#define ACC_READ_ADDR   (*(volatile unsigned int*)(ACC_BASE + 0x18))
#define ACC_READ_CMD    (*(volatile unsigned int*)(ACC_BASE + 0x1C))
#define ACC_READ_DATA   (*(volatile unsigned int*)(ACC_BASE + 0x20))
#define ACC_CYCLES      (*(volatile unsigned int*)(ACC_BASE + 0x24))
#define ACC_ERROR_REG   (*(volatile unsigned int*)(ACC_BASE + 0x28))

// ACC_CONTROL bits
#define ACC_CTRL_START       (1u << 0)
#define ACC_CTRL_CLEAR_DONE  (1u << 1)
#define ACC_CTRL_LOCAL_RST   (1u << 2)
#define ACC_CTRL_CLEAR_ERR   (1u << 3)

// ACC_STATUS bits
#define ACC_STATUS_BUSY         (1u << 0)
#define ACC_STATUS_DONE         (1u << 1)
#define ACC_STATUS_RESULT_VALID (1u << 2)
#define ACC_STATUS_ERROR        (1u << 3)

// SYS_CONTROL
#define SYS_CTRL_HALT  (1u << 0)

// -----------------------------------------------------------
// DMEM scratch area for matrices  (DMEM starts at 0x8000)
// -----------------------------------------------------------
#define DMEM_BASE  0x00008000

static volatile signed char  * const dmA =
    (volatile signed char*)(DMEM_BASE + 0x0000);   // 64 bytes  A
static volatile signed char  * const dmB =
    (volatile signed char*)(DMEM_BASE + 0x0040);   // 64 bytes  B
static volatile signed int   * const dmC =
    (volatile signed int* )(DMEM_BASE + 0x0080);   // 256 bytes C

// -----------------------------------------------------------
// tiny pseudo-random (linear congruential, 32-bit)
// -----------------------------------------------------------
static unsigned int lfsr_state = 0xDEADBEEF;
static signed char rand8(void) {
    lfsr_state = lfsr_state * 1664525u + 1013904223u;
    return (signed char)(lfsr_state >> 24);
}

// -----------------------------------------------------------
// Reference SW GEMM  (INT8 × INT8 → INT32 accumulation)
// -----------------------------------------------------------
static void sw_gemm(
    const signed char A[8][8],
    const signed char B[8][8],
    signed int        C[8][8])
{
    int r, c, k;
    for (r = 0; r < 8; r++)
        for (c = 0; c < 8; c++) {
            int acc = 0;
            for (k = 0; k < 8; k++)
                acc += (int)A[r][k] * (int)B[k][c];
            C[r][c] = acc;
        }
}

// -----------------------------------------------------------
// Write 8×8 matrix into accelerator  (sel: 0=A, 1=B)
// -----------------------------------------------------------
static void acc_load_matrix(int sel, const signed char M[8][8]) {
    int r, c;
    ACC_MATRIX_SEL = (unsigned int)sel;
    for (r = 0; r < 8; r++) {
        for (c = 0; c < 8; c++) {
            ACC_ROW        = (unsigned int)r;
            ACC_COL        = (unsigned int)c;
            // sign-extend INT8 to INT32 word (full-word write)
            ACC_WRITE_DATA = (unsigned int)(signed int)M[r][c];
        }
    }
}

// -----------------------------------------------------------
// Start accelerator and poll for done (with cycle timeout)
// Returns 0 on success, 1 on timeout
// -----------------------------------------------------------
static int acc_run(void) {
    unsigned int timeout = 10000;
    ACC_CONTROL = ACC_CTRL_START;
    while (timeout--) {
        if (ACC_STATUS & ACC_STATUS_DONE) return 0;
    }
    return 1;  // timeout
}

// -----------------------------------------------------------
// Read 64 results and compare with SW reference
// Returns 0 on pass, non-zero on first mismatch index+1
// -----------------------------------------------------------
static int acc_verify(const signed int ref[8][8]) {
    int r, c;
    for (r = 0; r < 8; r++) {
        for (c = 0; c < 8; c++) {
            unsigned int addr = (unsigned int)(r * 8 + c);
            ACC_READ_ADDR = addr;
            ACC_READ_CMD  = 1;           // trigger one read
            // 1-cycle latency — read once (wrapper latches rd_data)
            volatile unsigned int rd = ACC_READ_DATA;
            signed int got = (signed int)rd;
            if (got != ref[r][c]) return (r * 8 + c) + 1;
        }
    }
    return 0;
}

// -----------------------------------------------------------
// Write result register (SYS_CONTROL) to communicate PASS/FAIL
// Bit 31 = FAIL,  Bits[7:0] = test index
// -----------------------------------------------------------
#define RESULT_ADDR  (DMEM_BASE + 0x0200)
static volatile unsigned int * const result_reg =
    (volatile unsigned int*)RESULT_ADDR;

// -----------------------------------------------------------
// ENTRY POINT
// -----------------------------------------------------------
void _start(void) __attribute__((noreturn));
void _start(void) {
    // -------------------------------------------------------
    // Local matrix storage on the stack
    // -------------------------------------------------------
    signed char  A[8][8], B[8][8];
    signed int   C_ref[8][8];
    signed int   test;
    int          rc;

    *result_reg = 0xDEAD0000;   // mark: running

    // -------------------------------------------------------
    // Local-reset the accelerator to start clean
    // -------------------------------------------------------
    ACC_CONTROL = ACC_CTRL_LOCAL_RST;
    // Wait for ~8 cycles (spin)
    { volatile int d = 32; while(d--); }
    ACC_CONTROL = ACC_CTRL_CLEAR_ERR | ACC_CTRL_CLEAR_DONE;

    // -------------------------------------------------------
    // TEST 1: Zero matrices
    // -------------------------------------------------------
    test = 1;
    {
        int r, c;
        for (r=0; r<8; r++) for (c=0; c<8; c++) { A[r][c]=0; B[r][c]=0; }
    }
    sw_gemm(A, B, C_ref);
    acc_load_matrix(0, A);
    acc_load_matrix(1, B);
    if (acc_run()) { *result_reg = 0xDEAD0000 | test; goto halt; }
    rc = acc_verify(C_ref);
    if (rc) { *result_reg = 0xBAD00000 | (test<<8) | rc; goto halt; }
    ACC_CONTROL = ACC_CTRL_CLEAR_DONE;

    // -------------------------------------------------------
    // TEST 2: Identity A × all-ones B → B
    // -------------------------------------------------------
    test = 2;
    {
        int r, c;
        for (r=0; r<8; r++) for (c=0; c<8; c++) {
            A[r][c] = (r==c) ? 1 : 0;
            B[r][c] = 1;
        }
    }
    sw_gemm(A, B, C_ref);
    acc_load_matrix(0, A);
    acc_load_matrix(1, B);
    if (acc_run()) { *result_reg = 0xDEAD0000 | test; goto halt; }
    rc = acc_verify(C_ref);
    if (rc) { *result_reg = 0xBAD00000 | (test<<8) | rc; goto halt; }
    ACC_CONTROL = ACC_CTRL_CLEAR_DONE;

    // -------------------------------------------------------
    // TEST 3: Boundary  A=-128, B=127
    // -------------------------------------------------------
    test = 3;
    {
        int r, c;
        for (r=0; r<8; r++) for (c=0; c<8; c++) {
            A[r][c] = -128;
            B[r][c] =  127;
        }
    }
    sw_gemm(A, B, C_ref);
    acc_load_matrix(0, A);
    acc_load_matrix(1, B);
    if (acc_run()) { *result_reg = 0xDEAD0000 | test; goto halt; }
    rc = acc_verify(C_ref);
    if (rc) { *result_reg = 0xBAD00000 | (test<<8) | rc; goto halt; }
    ACC_CONTROL = ACC_CTRL_CLEAR_DONE;

    // -------------------------------------------------------
    // TEST 4-8: Five random matrices
    // -------------------------------------------------------
    {
        int t, r, c;
        for (t = 4; t <= 8; t++) {
            test = t;
            for (r=0; r<8; r++) for (c=0; c<8; c++) {
                A[r][c] = rand8();
                B[r][c] = rand8();
            }
            sw_gemm(A, B, C_ref);
            acc_load_matrix(0, A);
            acc_load_matrix(1, B);
            if (acc_run()) { *result_reg = 0xDEAD0000 | test; goto halt; }
            rc = acc_verify(C_ref);
            if (rc) { *result_reg = 0xBAD00000 | (test<<8) | rc; goto halt; }
            ACC_CONTROL = ACC_CTRL_CLEAR_DONE;
        }
    }

    // -------------------------------------------------------
    // All tests passed → write magic PASS value and halt
    // -------------------------------------------------------
    *result_reg = 0x900D0008;   // 0x900D + tests_passed=8

halt:
    // Signal done to simulator via SYS_CONTROL HALT bit
    SYS_CONTROL = SYS_CTRL_HALT;
    while (1) __asm__ volatile ("nop");
}
