# Phase 4 Verification Report: PL UART Peripheral & Serial Protocol

## 1. Executive Summary
As part of the authoritative v4.0 implementation contract for the **Edge-AI RISC-V SoC with 8×8 Weight-Stationary Systolic Array**, a dedicated, register-controlled PL UART peripheral was implemented at MMIO base address `0x4000_0300`. The peripheral provides a robust, self-contained serial communications bridge running at 115,200 baud (8N1) over the ZedBoard Pmod JA interface, operating synchronously within the single 100 MHz PL clock domain without clock dividers or secondary clock trees.

All 17 required verification tests in `sim/phase4_uart_tb.sv` passed with 100% compliance.

---

## 2. Hardware Architecture (`rtl/uart.sv`)

### 2.1 Register Map (Base: `0x4000_0300`)
| Offset | Name | Type | Reset | Description |
|---|---|---|---|---|
| `0x00` | `UART_DATA` | RW | `0x00` | TX write data / RX read data (lower 8 bits). |
| `0x04` | `UART_STATUS` | RO | `0x02` | `bit[0]`: `RX_VALID` (1 = FIFO not empty)<br>`bit[1]`: `TX_READY` (1 = FIFO not full)<br>`bit[2]`: `RX_OVERRUN` (sticky, cleared by read or flush)<br>`bit[3]`: `TX_BUSY` (1 = serializer active) |
| `0x08` | `UART_DIVISOR` | RW | `0x0035` | 16-bit baud rate divider. Programmed to 53 for 115,200 baud at 100 MHz. |
| `0x0C` | `UART_CONTROL` | WO/W1P | `0x00` | `bit[0]`: `RX_FLUSH` (clears RX FIFO)<br>`bit[1]`: `TX_FLUSH` (clears TX FIFO) |

### 2.2 Baud Rate Generator & Oversampling
- The baud generator utilizes **16× oversampling** driven directly by the 100 MHz primary clock.
- The 16× baud tick interval is defined by:
  $$\text{Sample Interval} = \text{DIVISOR} + 1$$
- For 100 MHz system clock and 115,200 baud:
  $$\text{DIVISOR} = \text{round}\left(\frac{100,000,000}{16 \times 115,200}\right) - 1 = \text{round}(54.25) - 1 = 53 \; (0x0035)$$
- Actual baud rate achieved:
  $$\text{Baud}_{\text{actual}} = \frac{100,000,000}{16 \times 54} = 115,740.7 \; \text{baud} \quad (\text{Error: } +0.47\%, \ll \pm 2\% \text{ tolerance})$$

### 2.3 Clock Domain Crossing (CDC) & Glitch Filtering
- The asynchronous external `uart_rx` pin is protected by a dedicated **2-flip-flop synchronizer** chain (`rx_sync_1`, `rx_sync_2`).
- The synchronized line feeds a majority voter / mid-bit sampler that latches the RX start bit at sample index 7 and data bits at sample index 7 of each bit interval.
- Specification Rule 11.1 compliance: No false path exceptions or timing ignores are placed on the synchronizer chain.

### 2.4 FIFO Buffers
- **TX FIFO**: 16-entry circular FIFO with synchronous write, read, and status flags.
- **RX FIFO**: 16-entry circular FIFO with overrun detection (`RX_OVERRUN` flag asserted on push to full FIFO).

---

## 3. Protocol Framing & Data Grammar

The v4.0 binary framing format operates above the byte stream:
```
+--------+--------+--------+---------------+---------------+--------------------+---------------+---------------+
| SYNC1  | SYNC2  |  TYPE  |   LEN_LO      |   LEN_HI      |   PAYLOAD (0..256) |   CRC16_LO    |   CRC16_HI    |
| (0xA5) | (0x5A) | (1 B)  |    (1 B)      |    (1 B)      |      (0..256 B)    |    (1 B)      |    (1 B)      |
+--------+--------+--------+---------------+---------------+--------------------+---------------+---------------+
```

### 3.1 Frame Types
- `0x01` (`HELLO`): Host keepalive / discovery handshake.
- `0x02` (`INPUT_DATA`): Chunked INT8 input tensor stream (`[offset_lo, offset_hi, data...]`).
- `0x03` (`RUN`): Execute full hardware CNN inference.
- `0x04` (`RESULT`): Return predicted class, execution latency (cycles), and 10 INT32 logits.
- `0x7E` (`NACK`): Error frame indicating rejected packet (`0x11`=Bad CRC, `0x12`=Illegal Length, `0x13`=Unknown Type).
- `0x7F` (`ACK`): Successful receipt and verification of command/chunk.

### 3.2 CRC16-CCITT Definition
- **Polynomial**: $x^{16} + x^{12} + x^5 + 1$ (`0x1021`)
- **Initial Value**: `0xFFFF`
- **Coverage**: `TYPE || LENGTH_LO || LENGTH_HI || PAYLOAD` (excludes SYNC bytes and CRC itself).

---

## 4. Verification Test Matrix (`sim/phase4_uart_tb.sv`)

| Test # | Test Description | Stimulus & Check | Result |
|---|---|---|---|
| **01** | Reset Default State | Verify `STATUS=0x02` (TX_READY), `DIVISOR=53`, FIFOs empty | **PASS** |
| **02** | Single Byte TX | Transmit `0x42`, verify serial start/data/stop timing | **PASS** |
| **03** | Single Byte RX | Inject `0x99`, verify `RX_VALID`, read `DATA=0x99` | **PASS** |
| **04** | 2-FF CDC Synchronizer | Verify asynchronous edges propagate without metastability | **PASS** |
| **05** | TX FIFO Full Flag | Fill TX FIFO with 16 bytes; verify `TX_READY=0` on 16th | **PASS** |
| **06** | TX FIFO Drain Sequence | Verify all 16 bytes drain serially in order; `TX_READY=1` | **PASS** |
| **07** | RX FIFO Full Flag | Fill RX FIFO with 16 bytes; verify `RX_VALID=1` throughout | **PASS** |
| **08** | RX FIFO Overrun Flag | Push 17th byte; verify sticky `RX_OVERRUN` bit asserted | **PASS** |
| **09** | RX FIFO Flush Control | Write `0x01` to `CONTROL`; verify `RX_VALID=0`, `OVERRUN=0` | **PASS** |
| **10** | TX FIFO Flush Control | Write `0x02` to `CONTROL`; verify TX FIFO instantly cleared | **PASS** |
| **11** | Divisor Modification | Modify divisor to 10; verify sample rate scales accordingly | **PASS** |
| **12** | Valid Frame Transmission | Send `HELLO` frame with valid CRC16; verify frame ACK | **PASS** |
| **13** | Corrupt CRC Rejection | Inject corrupt CRC16; verify host receives NACK (`0x11`) | **PASS** |
| **14** | Corrupt Length Rejection| Inject payload length > 256; verify NACK (`0x12`) | **PASS** |
| **15** | Unknown Frame Rejection | Inject type `0x33`; verify NACK (`0x13`) | **PASS** |
| **16** | Noise Resynchronization | Inject random line noise before `0xA5 0x5A`; verify sync | **PASS** |
| **17** | Back-to-Back Burst Stream| Stream 128 bytes back-to-back with zero inter-byte gaps | **PASS** |

**Summary**: 17 / 17 tests PASSED (100.00% pass rate).
