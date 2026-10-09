// ============================================================
//  phase3_matrix.c  —  Phase 3 Firmware Source
//
//  End-to-end CPU-driven Matrix Accelerator Flow with Tile DMA:
//    1. Initialize A & B matrices in DMEM
//    2. Grant DMA ownership (DMA_OWNER = 1)
//    3. DMA ACT_LOAD (64 bytes from DMEM 0x8000)
//    4. DMA WEIGHT_LOAD (64 bytes from DMEM 0x8040)
//    5. Return ownership to CPU (DMA_OWNER = 0)
//    6. Explicit CPU Accelerator START (ACC_CONTROL.START = 1)
//    7. Poll ACC_STATUS until DONE
//    8. Grant DMA ownership (DMA_OWNER = 1)
//    9. DMA RESULT_STORE (256 bytes to DMEM 0x8080)
//   10. Return ownership to CPU (DMA_OWNER = 0)
//   11. CPU verifies all 64 INT32 results against reference GEMM
//   12. Writes PASS marker (0x900D0001) or FAIL (0xBAD00001) to 0x8180
// ============================================================

#include <stdint.h>

#define SYS_BASE    0x40000000
#define ACC_BASE    0x40000100
#define DMA_BASE    0x40000200
#define DMEM_BASE   0x00008000

// SYS registers
#define SYS_STATUS  (*(volatile uint32_t*)(SYS_BASE + 0x04))

// ACC registers
#define ACC_CTRL    (*(volatile uint32_t*)(ACC_BASE + 0x00))
#define ACC_STATUS  (*(volatile uint32_t*)(ACC_BASE + 0x04))

// DMA registers
#define DMA_CTRL    (*(volatile uint32_t*)(DMA_BASE + 0x00))
#define DMA_STATUS  (*(volatile uint32_t*)(DMA_BASE + 0x04))
#define DMA_SRC     (*(volatile uint32_t*)(DMA_BASE + 0x08))
#define DMA_DST     (*(volatile uint32_t*)(DMA_BASE + 0x0C))
#define DMA_LEN     (*(volatile uint32_t*)(DMA_BASE + 0x10))
#define DMA_OWNER   (*(volatile uint32_t*)(DMA_BASE + 0x14))
#define DMA_TIMEOUT (*(volatile uint32_t*)(DMA_BASE + 0x18))
#define DMA_ERR     (*(volatile uint32_t*)(DMA_BASE + 0x1C))

// Memory pointers
#define MAT_A       ((volatile int8_t*)(DMEM_BASE + 0x00))   // 0x8000, 64 bytes
#define MAT_B       ((volatile int8_t*)(DMEM_BASE + 0x40))   // 0x8040, 64 bytes
#define MAT_C       ((volatile int32_t*)(DMEM_BASE + 0x80))  // 0x8080, 256 bytes
#define MARKER      (*(volatile uint32_t*)(DMEM_BASE + 0x180))// 0x8180

#define PASS_MARKER 0x900D0001
#define FAIL_MARKER 0xBAD00001

int main(void) {
    // 1. Initialize matrices A and B (e.g., all 1s -> each C element = 8)
    for (int i = 0; i < 64; i++) {
        MAT_A[i] = 1;
        MAT_B[i] = 1;
    }

    // 2. Grant DMA ownership
    DMA_OWNER = 1;

    // 3. DMA ACT_LOAD (64 bytes from MAT_A to activation buffer)
    DMA_SRC = (uint32_t)MAT_A;
    DMA_LEN = 64;
    DMA_CTRL = 0x01 | (0x00 << 4); // START | MODE_ACT_LOAD(0)
    while (!(DMA_STATUS & 0x02));  // Poll DONE
    DMA_CTRL = 0x02;               // CLEAR_DONE

    // 4. DMA WEIGHT_LOAD (64 bytes from MAT_B to weight buffer)
    DMA_SRC = (uint32_t)MAT_B;
    DMA_LEN = 64;
    DMA_CTRL = 0x01 | (0x01 << 4); // START | MODE_WEIGHT_LOAD(1)
    while (!(DMA_STATUS & 0x02));  // Poll DONE
    DMA_CTRL = 0x02;               // CLEAR_DONE

    // 5. Release ownership back to CPU
    DMA_OWNER = 0;

    // 6. Explicit CPU Accelerator START
    ACC_CTRL = 0x01; // START

    // 7. Poll until accelerator finishes
    while (!(ACC_STATUS & 0x02));  // Poll DONE
    ACC_CTRL = 0x02;               // CLEAR_DONE

    // 8. Grant DMA ownership for draining results
    DMA_OWNER = 1;

    // 9. DMA RESULT_STORE (256 bytes to MAT_C)
    DMA_DST = (uint32_t)MAT_C;
    DMA_LEN = 256;
    DMA_CTRL = 0x01 | (0x02 << 4); // START | MODE_RESULT_STORE(2)
    while (!(DMA_STATUS & 0x02));  // Poll DONE
    DMA_CTRL = 0x02;               // CLEAR_DONE

    // 10. Return ownership to CPU
    DMA_OWNER = 0;

    // 11. CPU verifies all 64 INT32 values
    int pass = 1;
    for (int i = 0; i < 64; i++) {
        if (MAT_C[i] != 8) {
            pass = 0;
            break;
        }
    }

    // 12. Write marker
    if (pass) {
        MARKER = PASS_MARKER;
    } else {
        MARKER = FAIL_MARKER;
    }

    while (1);
    return 0;
}
