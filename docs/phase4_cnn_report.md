# Phase 4 Edge-AI Workload Report: INT8 CNN Inference on 8×8 WS Systolic SoC

## 1. Executive Summary
This report documents the neural network architecture, INT8 quantization scheme, hardware acceleration mapping, and firmware orchestration for the **8×8 Weight-Stationary (WS) Systolic Array Edge-AI Accelerator**.

The workload is an end-to-end quantized convolutional neural network for image classification (MNIST benchmark) operating on a single 100 MHz clock domain on the Digilent ZedBoard. The systolic array accelerates matrix multiplication and 2D convolution via tile-based matrix decomposition (GEMM), while the PicoRV32 CPU handles pooling, activation functions, K-split accumulation, requantization, and argmax classification.

---

## 2. Quantized CNN Model Architecture

### 2.1 Layer Breakdown
| Layer | Input Dimension | Operation / Parameters | Kernel / Stride | Output Dimension | Weights (Bytes) | Bias (Bytes) |
|---|---|---|---|---|---|---|
| **Input** | $28 \times 28 \times 1$ | Grayscale image (INT8 normalized) | — | $28 \times 28 \times 1$ | — | — |
| **Conv1** | $28 \times 28 \times 1$ | 8 filters, valid padding ($s=1$) | $3 \times 3$ | $26 \times 26 \times 8$ | 72 | 32 |
| **ReLU1** | $26 \times 26 \times 8$ | Elementwise $\max(0, x)$ | — | $26 \times 26 \times 8$ | — | — |
| **Pool1** | $26 \times 26 \times 8$ | Max pooling ($2 \times 2$, $s=2$) | $2 \times 2$ | $13 \times 13 \times 8$ | — | — |
| **Conv2** | $13 \times 13 \times 8$ | 16 filters, valid padding ($s=1$) | $3 \times 3$ | $11 \times 11 \times 16$| 1,152 | 64 |
| **ReLU2** | $11 \times 11 \times 16$| Elementwise $\max(0, x)$ | — | $11 \times 11 \times 16$| — | — |
| **Pool2** | $11 \times 11 \times 16$| Max pooling ($2 \times 2$, $s=2$) | $2 \times 2$ | $5 \times 5 \times 16$ | — | — |
| **FC1** | $400$ ($5 \times 5 \times 16$) | Fully Connected (Matrix GEMM) | $400 \times 32$ | $32$ | 12,800 | 128 |
| **ReLU3** | $32$ | Elementwise $\max(0, x)$ | — | $32$ | — | — |
| **FC2** | $32$ | Fully Connected (Final Logits) | $32 \times 10$ | $10$ | 320 | 40 |
| **Argmax**| $10$ | Winner-take-all classification | — | $1$ (Class 0..9) | — | — |

**Total Parameter Footprint**: 14,344 INT8 weight bytes + 264 INT32 bias words = 15,400 bytes total.

---

## 3. Systolic Array Tile Decomposition & K-Splitting

### 3.1 Hardware Capability
The fixed 8×8 systolic array IP executes an $8 \times 8$ matrix multiplication in Weight-Stationary mode:
$$C_{[8 \times 8]} = A_{[8 \times 8]} \times B_{[8 \times 8]}$$
- Inputs $A$ (activations) and $B$ (weights) are 8-bit signed integers (`int8_t`).
- Output $C$ consists of 64 32-bit signed integers (`int32_t`).
- Stationary weights are preloaded into PE local registers; activations flow horizontally; partial sums accumulate vertically.

### 3.2 K-Dimension Splitting
When computing general matrix multiplications where the reduction dimension $K > 8$:
1. The $M \times K$ activation matrix and $K \times N$ weight matrix are partitioned into $8 \times 8$ sub-blocks.
2. For each block index $k \in \{0, 1, \dots, \lceil K/8 \rceil - 1\}$:
   - DMA loads $8 \times 8$ (64 bytes) activation tile $A_k$ into the accelerator activation buffer.
   - DMA loads $8 \times 8$ (64 bytes) weight tile $B_k$ into the accelerator weight buffer.
   - The CPU issues an explicit `ACC_START` pulse to compute $P_k = A_k \times B_k$.
   - DMA stores 256 bytes (64 INT32 results) from the accelerator output buffer to DMEM.
   - The PicoRV32 software accumulator accumulates:
     $$C_{\text{acc}} = C_{\text{acc}} + P_k$$
3. After all $K$-tiles complete, bias addition and fixed-point requantization are applied:
   $$Y = \text{clip}\left(\left\lfloor \frac{C_{\text{acc}} + \text{bias} + \text{round}}{2^S} \right\rfloor, -128, 127\right)$$

---

## 4. SoC Memory Mapping & Buffer Allocation

The 224 KiB Data Memory (`dmem_bram.sv`) spans `0x0000_8000` to `0x0003_FFFF`:

| Address Range | Size | Region Name | Contents / Usage |
|---|---|---|---|
| `0x0000_8000 – 0x0000_8FFF` | 4 KiB | `SCRATCH` | Stack, UART buffers, frame queues, cycle counters, logits |
| `0x0000_9000 – 0x0000_FFFF` | 28 KiB | `RESERVED` | CPU runtime workspace |
| `0x0001_0000 – 0x0001_3FFF` | 16 KiB | `INPUT_BUF` | 784-byte incoming normalized image tensor |
| `0x0001_4000 – 0x0002_BFFF` | 96 KiB | `WEIGHT_BUF` | Preloaded CNN weights, biases, and quantization scales |
| `0x0002_C000 – 0x0003_3FFF` | 32 KiB | `FEATURE_A` | Ping-pong activation buffer A (Conv1 output, Pool2 output)|
| `0x0003_4000 – 0x0003_BFFF` | 32 KiB | `FEATURE_B` | Ping-pong activation buffer B (Pool1 output, Conv2 output)|
| `0x0003_C000 – 0x0003_FFFF` | 16 KiB | `OUTPUT_BUF` | Systolic array 256-byte DMA target buffer & final logits |

---

## 5. Execution Protocol & Firmware Flow

```
Host PC                            PicoRV32 CPU                          DMA / Accelerator
  │                                     │                                        │
  │─── HELLO (0x01) ───────────────────>│                                        │
  │<── ACK (0x7F) ──────────────────────│                                        │
  │                                     │                                        │
  │─── INPUT_DATA Chunk 0 (196 B) ─────>│ (Verify CRC16, copy to 0x10000)        │
  │<── ACK (0x7F) ──────────────────────│                                        │
  │─── INPUT_DATA Chunk 1 (196 B) ─────>│                                        │
  │<── ACK (0x7F) ──────────────────────│                                        │
  │─── INPUT_DATA Chunk 2 (196 B) ─────>│                                        │
  │<── ACK (0x7F) ──────────────────────│                                        │
  │─── INPUT_DATA Chunk 3 (196 B) ─────>│                                        │
  │<── ACK (0x7F) ──────────────────────│ (Full 784 B tensor in BRAM)            │
  │                                     │                                        │
  │─── RUN (0x03) ─────────────────────>│ Start Cycle Counter                    │
  │                                     │─── Request DMA_OWNER=1 ───────────────>│
  │                                     │─── Start ACT_LOAD (64 B) ─────────────>│
  │                                     │<── DMA Done Interrupt/Flag ────────────│
  │                                     │─── Start WEIGHT_LOAD (64 B) ──────────>│
  │                                     │<── DMA Done Interrupt/Flag ────────────│
  │                                     │─── Set DMA_OWNER=0, ACC_START=1 ──────>│
  │                                     │                                        │ (Compute 64 INT32)
  │                                     │<── ACC_DONE Latched ───────────────────│
  │                                     │─── Request DMA_OWNER=1 ───────────────>│
  │                                     │─── Start RESULT_STORE (256 B) ────────>│
  │                                     │<── DMA Done (Results at 0x3C000) ──────│
  │                                     │ Argmax classification                  │
  │                                     │ Stop Cycle Counter                     │
  │<── RESULT (0x04, class, lat, log) ──│                                        │
```

---

## 6. Software & Hardware Verification
The end-to-end flow is validated in bit-exact alignment with `host/golden_model.py`:
- All intermediate tile activations match between the hardware systolic array and Python integer simulation.
- Argmax tie-breaking conforms strictly to lowest-index priority.
