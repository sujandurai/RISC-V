// ============================================================
//  firmware/phase4_cnn.c  —  Phase 4 Reference C Firmware
//
//  Authoritative v4.0 Specification:
//    - PicoRV32 RV32IM CPU
//    - IMEM at 0x0000_0000 (32 KiB)
//    - DMEM at 0x0000_8000 (224 KiB)
//    - SYS MMIO at 0x4000_0000
//    - ACC MMIO at 0x4000_0100
//    - DMA MMIO at 0x4000_0200
//    - UART MMIO at 0x4000_0300
// ============================================================

#include <stdint.h>
#include <stdbool.h>

// MMIO Addresses
#define SYS_BASE    0x40000000
#define ACC_BASE    0x40000100
#define DMA_BASE    0x40000200
#define UART_BASE   0x40000300

#define SYS_REG(offset)   (*(volatile uint32_t *)(SYS_BASE + (offset)))
#define ACC_REG(offset)   (*(volatile uint32_t *)(ACC_BASE + (offset)))
#define DMA_REG(offset)   (*(volatile uint32_t *)(DMA_BASE + (offset)))
#define UART_REG(offset)  (*(volatile uint32_t *)(UART_BASE + (offset)))

// Memory Region Bases
#define INPUT_BASE      ((volatile int8_t *)0x00010000)
#define WEIGHTS_BASE    ((volatile int8_t *)0x00014000)
#define FEATURE_A_BASE  ((volatile int8_t *)0x0002C000)
#define FEATURE_B_BASE  ((volatile int8_t *)0x00034000)
#define OUTPUT_BASE     ((volatile int32_t *)0x0003C000)

// UART Registers
#define UART_DATA     UART_REG(0x00)
#define UART_STATUS   UART_REG(0x04)
#define UART_DIVISOR  UART_REG(0x08)
#define UART_CONTROL  UART_REG(0x0C)

// Frame types
#define TYPE_HELLO      0x01
#define TYPE_INPUT_DATA 0x02
#define TYPE_RUN        0x03
#define TYPE_RESULT     0x04
#define TYPE_NACK       0x7E
#define TYPE_ACK        0x7F

// CRC16-CCITT
static uint16_t crc16_update(uint16_t crc, uint8_t b) {
    crc ^= ((uint16_t)b << 8);
    for (int i = 0; i < 8; i++) {
        if (crc & 0x8000) {
            crc = (crc << 1) ^ 0x1021;
        } else {
            crc = (crc << 1);
        }
    }
    return crc;
}

// UART Polling Routines
static uint8_t uart_recv_byte(void) {
    while ((UART_STATUS & 0x01) == 0); // wait RX_VALID
    return (uint8_t)(UART_DATA & 0xFF);
}

static void uart_send_byte(uint8_t b) {
    while ((UART_STATUS & 0x02) == 0); // wait TX_READY
    UART_DATA = b;
}

// Frame Transmission
static void send_frame(uint8_t type, uint16_t len, const uint8_t *payload) {
    uart_send_byte(0xA5);
    uart_send_byte(0x5A);
    uart_send_byte(type);
    uart_send_byte(len & 0xFF);
    uart_send_byte((len >> 8) & 0xFF);

    uint16_t crc = 0xFFFF;
    crc = crc16_update(crc, type);
    crc = crc16_update(crc, len & 0xFF);
    crc = crc16_update(crc, (len >> 8) & 0xFF);

    for (uint16_t i = 0; i < len; i++) {
        uart_send_byte(payload[i]);
        crc = crc16_update(crc, payload[i]);
    }

    uart_send_byte(crc & 0xFF);
    uart_send_byte((crc >> 8) & 0xFF);
}

static void send_ack(void) {
    send_frame(TYPE_ACK, 0, 0);
}

static void send_nack(uint8_t err_code) {
    send_frame(TYPE_NACK, 1, &err_code);
}

// Requantization per Section 12.2
static inline int8_t requantize(int32_t x, int shift) {
    if (shift == 0) {
        if (x > 127) return 127;
        if (x < -128) return -128;
        return (int8_t)x;
    }
    int32_t half = 1 << (shift - 1);
    int32_t val;
    if (x >= 0) {
        val = (x + half) >> shift;
    } else {
        val = -(((-x) + half) >> shift);
    }
    if (val > 127) return 127;
    if (val < -128) return -128;
    return (int8_t)val;
}

// Hardware-accelerated 8x8 Tile GEMM using DMA
static void run_tile_gemm(uint32_t act_addr, uint32_t wgt_addr, uint32_t res_addr) {
    // 1. DMA ACT_LOAD (64 bytes)
    DMA_REG(0x14) = 1; // DMA_OWNER = 1
    DMA_REG(0x08) = act_addr;
    DMA_REG(0x10) = 64;
    DMA_REG(0x00) = 0x01; // START | ACT_LOAD
    while ((DMA_REG(0x04) & 0x02) == 0);
    DMA_REG(0x00) = 0x02; // CLEAR_DONE

    // 2. DMA WEIGHT_LOAD (64 bytes)
    DMA_REG(0x08) = wgt_addr;
    DMA_REG(0x10) = 64;
    DMA_REG(0x00) = 0x11; // START | WEIGHT_LOAD
    while ((DMA_REG(0x04) & 0x02) == 0);
    DMA_REG(0x00) = 0x02;

    // 3. Release ownership to CPU & Run Accelerator
    DMA_REG(0x14) = 0;
    ACC_REG(0x00) = 0x01; // ACC_START
    while ((ACC_REG(0x04) & 0x02) == 0); // Wait DONE
    ACC_REG(0x00) = 0x02; // CLEAR_DONE

    // 4. DMA RESULT_STORE (256 bytes)
    DMA_REG(0x14) = 1;
    DMA_REG(0x0C) = res_addr;
    DMA_REG(0x10) = 256;
    DMA_REG(0x00) = 0x21; // START | RESULT_STORE
    while ((DMA_REG(0x04) & 0x02) == 0);
    DMA_REG(0x00) = 0x02;
    DMA_REG(0x14) = 0;
}

// Main Edge-AI firmware loop
int main(void) {
    // 1. Hardware initialization
    UART_DIVISOR = 53;      // 115200 baud at 100 MHz
    UART_CONTROL = 0x03;    // Flush RX and TX FIFOs
    SYS_REG(0x08) = 0x1E;   // Clear SYS sticky error flags
    ACC_REG(0x00) = 0x06;   // Clear ACC status
    DMA_REG(0x00) = 0x06;   // Clear DMA status

    uint8_t payload_buf[256];

    while (1) {
        // Wait for SYNC1 (0xA5)
        if (uart_recv_byte() != 0xA5) continue;
        // Wait for SYNC2 (0x5A)
        if (uart_recv_byte() != 0x5A) continue;

        uint8_t type = uart_recv_byte();
        uint8_t len_lo = uart_recv_byte();
        uint8_t len_hi = uart_recv_byte();
        uint16_t len = ((uint16_t)len_hi << 8) | len_lo;

        if (len > 256) {
            send_nack(0x12); // ERR_ILLEGAL_LENGTH
            continue;
        }

        for (uint16_t i = 0; i < len; i++) {
            payload_buf[i] = uart_recv_byte();
        }

        uint8_t crc_lo = uart_recv_byte();
        uint8_t crc_hi = uart_recv_byte();
        uint16_t rx_crc = ((uint16_t)crc_hi << 8) | crc_lo;

        // Verify CRC16-CCITT
        uint16_t exp_crc = 0xFFFF;
        exp_crc = crc16_update(exp_crc, type);
        exp_crc = crc16_update(exp_crc, len_lo);
        exp_crc = crc16_update(exp_crc, len_hi);
        for (uint16_t i = 0; i < len; i++) {
            exp_crc = crc16_update(exp_crc, payload_buf[i]);
        }

        if (rx_crc != exp_crc) {
            send_nack(0x11); // ERR_BAD_CRC
            continue;
        }

        // Dispatch Command
        if (type == TYPE_HELLO) {
            send_ack();
        } else if (type == TYPE_INPUT_DATA) {
            uint16_t offset = (uint16_t)payload_buf[0] | ((uint16_t)payload_buf[1] << 8);
            uint16_t data_len = len - 2;
            for (uint16_t i = 0; i < data_len; i++) {
                INPUT_BASE[offset + i] = (int8_t)payload_buf[2 + i];
            }
            send_ack();
        } else if (type == TYPE_RUN) {
            uint32_t t_start = SYS_REG(0x0C); // Cycle counter

            // Run CNN / Tile execution
            run_tile_gemm(0x00010000, 0x00014000, 0x0003C000);

            // Read logits and compute argmax
            int32_t logits[10];
            int best_idx = 0;
            int32_t best_val = OUTPUT_BASE[0];
            logits[0] = best_val;
            for (int i = 1; i < 10; i++) {
                int32_t val = OUTPUT_BASE[i];
                logits[i] = val;
                if (val > best_val) {
                    best_val = val;
                    best_idx = i;
                }
            }

            uint32_t t_end = SYS_REG(0x0C);
            uint32_t latency = t_end - t_start;

            // Construct RESULT payload (45 bytes)
            uint8_t res_buf[45];
            res_buf[0] = (uint8_t)best_idx;
            *(uint32_t *)&res_buf[1] = latency;
            for (int i = 0; i < 10; i++) {
                *(int32_t *)&res_buf[5 + i * 4] = logits[i];
            }

            send_frame(TYPE_RESULT, 45, res_buf);
        } else {
            send_nack(0x13); // ERR_UNKNOWN_TYPE
        }
    }
    return 0;
}
