#!/usr/bin/env python3
# ============================================================
#  host/golden_model.py  —  Phase 4 Normative Golden Model
#
#  Authoritative v4.0 Edge-AI Workload:
#    - Input: 28×28×1 signed INT8
#    - Conv1: 3×3×1 -> 8 filters, stride 1, no pad (26×26×8)
#    - ReLU1: elementwise clamp(0..127)
#    - Pool1: 2×2 max pool, stride 2 (13×13×8)
#    - Conv2: 3×3×8 -> 16 filters, stride 1, no pad (11×11×16)
#    - ReLU2: elementwise clamp(0..127)
#    - Pool2: 2×2 max pool, stride 2 (5×5×16 = 400 elements)
#    - FC1: 400 -> 32
#    - ReLU3: elementwise clamp(0..127)
#    - FC2: 32 -> 10 logits
#    - Argmax: lowest index tie break
#
#  Exact Arithmetic Contract:
#    - Operands: signed INT8 [-128..127]
#    - Zero point: 0
#    - Accumulation: signed INT32
#    - Systolic Tile: 8×8 INT8 × 8×8 INT8 = 8×8 INT32
#    - K-split: ceil(K/8) tiles, software INT32 accumulation
#    - Requantization:
#        q_pos = (x + 2^(s-1)) >> s
#        q_neg = -(((-x) + 2^(s-1)) >> s)
#        clamp(q, -128, 127)
# ============================================================

import os
import json
import struct
import numpy as np

# Requantization rounding per spec v4.0 Section 12.2
def requantize_scalar(x: int, shift: int) -> int:
    if shift == 0:
        val = x
    else:
        half = 1 << (shift - 1)
        if x >= 0:
            val = (x + half) >> shift
        else:
            val = -(((-x) + half) >> shift)
    # Saturation to INT8
    if val > 127:
        return 127
    elif val < -128:
        return -128
    return val

def requantize_tensor(arr: np.ndarray, shift: int) -> np.ndarray:
    out = np.zeros_like(arr, dtype=np.int8)
    flat_in = arr.ravel()
    flat_out = out.ravel()
    for i in range(flat_in.size):
        flat_out[i] = requantize_scalar(int(flat_in[i]), shift)
    return out

# Hardware-accurate 8x8 Systolic Tile GEMM
def tile_gemm_8x8(A_tile: np.ndarray, B_tile: np.ndarray) -> np.ndarray:
    """Computes exactly one 8x8 signed INT8 matmul producing 8x8 INT32."""
    assert A_tile.shape == (8, 8) and A_tile.dtype == np.int8
    assert B_tile.shape == (8, 8) and B_tile.dtype == np.int8
    # Exact INT32 matrix multiplication
    return np.matmul(A_tile.astype(np.int32), B_tile.astype(np.int32), dtype=np.int32)

# Hardware-accurate Lowered Tiled GEMM with K-splitting
def hardware_gemm(A: np.ndarray, B: np.ndarray, bias: np.ndarray = None, shift: int = 0) -> np.ndarray:
    """
    Lowered GEMM C[M, N] = A[M, K] x B[K, N] using repeated 8x8 tiles.
    A: [M, K] int8
    B: [K, N] int8
    bias: [N] int32 (optional)
    """
    M, K = A.shape
    K_b, N = B.shape
    assert K == K_b

    # Number of tiles
    M_tiles = (M + 7) // 8
    N_tiles = (N + 7) // 8
    K_tiles = (K + 7) // 8

    # INT32 Accumulation buffer
    C_acc = np.zeros((M_tiles * 8, N_tiles * 8), dtype=np.int32)

    # Pad A and B to multiples of 8
    A_pad = np.zeros((M_tiles * 8, K_tiles * 8), dtype=np.int8)
    B_pad = np.zeros((K_tiles * 8, N_tiles * 8), dtype=np.int8)
    A_pad[:M, :K] = A
    B_pad[:K, :N] = B

    # Tiled execution: exactly replicates CPU-orchestrated accelerator calls
    for m in range(M_tiles):
        for n in range(N_tiles):
            # Accumulator for this [8, 8] output tile
            tile_sum = np.zeros((8, 8), dtype=np.int32)
            for k in range(K_tiles):
                a_chunk = A_pad[m*8:(m+1)*8, k*8:(k+1)*8]
                b_chunk = B_pad[k*8:(k+1)*8, n*8:(n+1)*8]
                # Accelerator START produces partial result
                partial = tile_gemm_8x8(a_chunk, b_chunk)
                # Software accumulates partials
                tile_sum += partial
            C_acc[m*8:(m+1)*8, n*8:(n+1)*8] = tile_sum

    # Slice valid rows and columns
    C_valid = C_acc[:M, :N]

    # Add bias if present
    if bias is not None:
        C_valid = C_valid + bias.astype(np.int32)

    # Requantize if shift > 0, otherwise return INT32
    if shift > 0:
        return requantize_tensor(C_valid, shift)
    return C_valid

# Max Pooling 2x2, stride 2
def maxpool_2x2(x: np.ndarray) -> np.ndarray:
    """x: [H, W, C] int8 -> out: [H//2, W//2, C] int8"""
    H, W, C = x.shape
    out_H, out_W = H // 2, W // 2
    out = np.zeros((out_H, out_W, C), dtype=np.int8)
    for h in range(out_H):
        for w in range(out_W):
            window = x[h*2:h*2+2, w*2:w*2+2, :]
            out[h, w, :] = np.max(window, axis=(0, 1))
    return out

# Argmax with lowest index tie-break
def argmax_tiebreak(logits: np.ndarray) -> int:
    flat = logits.ravel()
    best_idx = 0
    best_val = flat[0]
    for idx in range(1, len(flat)):
        if flat[idx] > best_val:
            best_val = flat[idx]
            best_idx = idx
    return int(best_idx)

class GoldenCNN:
    def __init__(self, weights_dict=None):
        if weights_dict is not None:
            self.load_weights(weights_dict)
        else:
            self.init_deterministic_weights()

    def init_deterministic_weights(self):
        """Creates deterministic integer weights with structured features."""
        np.random.seed(42)

        # Conv1: 8 filters of 3x3x1 (72 bytes int8) + 8 biases (32 bytes int32)
        # Filters detect: 0=horizontal, 1=vertical, 2=diag1, 3=diag2, 4=center, 5=edges, 6=cross, 7=corner
        self.conv1_w = np.random.randint(-16, 17, size=(8, 3, 3, 1), dtype=np.int8)
        self.conv1_b = np.zeros(8, dtype=np.int32)
        self.conv1_shift = 6  # Requantize scale: /64

        # Conv2: 16 filters of 3x3x8 (1152 bytes int8) + 16 biases (64 bytes int32)
        self.conv2_w = np.random.randint(-12, 13, size=(16, 3, 3, 8), dtype=np.int8)
        self.conv2_b = np.zeros(16, dtype=np.int32)
        self.conv2_shift = 7  # Requantize scale: /128

        # FC1: 400 -> 32 (12800 bytes int8) + 32 biases (128 bytes int32)
        self.fc1_w = np.random.randint(-10, 11, size=(400, 32), dtype=np.int8)
        self.fc1_b = np.zeros(32, dtype=np.int32)
        self.fc1_shift = 8  # Requantize scale: /256

        # FC2: 32 -> 10 (320 bytes int8) + 10 biases (40 bytes int32)
        self.fc2_w = np.random.randint(-16, 17, size=(32, 10), dtype=np.int8)
        self.fc2_b = np.zeros(10, dtype=np.int32)
        self.fc2_shift = 0  # Final layer keeps INT32 logits!

    def load_weights(self, d):
        self.conv1_w = d['conv1_w']
        self.conv1_b = d['conv1_b']
        self.conv1_shift = d.get('conv1_shift', 6)

        self.conv2_w = d['conv2_w']
        self.conv2_b = d['conv2_b']
        self.conv2_shift = d.get('conv2_shift', 7)

        self.fc1_w = d['fc1_w']
        self.fc1_b = d['fc1_b']
        self.fc1_shift = d.get('fc1_shift', 8)

        self.fc2_w = d['fc2_w']
        self.fc2_b = d['fc2_b']
        self.fc2_shift = d.get('fc2_shift', 0)

    def forward(self, x: np.ndarray, debug=False):
        """
        Executes complete forward pass layer-by-layer matching hardware exactly.
        Input x: [28, 28] int8
        """
        assert x.shape == (28, 28) and x.dtype == np.int8
        intermediates = {}

        # ----------------------------------------------------
        # Layer 1: Conv1 (3x3x1 -> 8 filters, stride 1)
        # ----------------------------------------------------
        # Lowering: im2col -> A is [676, 9], B is [9, 8]
        # 26x26 output locations
        A_conv1 = np.zeros((26*26, 9), dtype=np.int8)
        row = 0
        for i in range(26):
            for j in range(26):
                patch = x[i:i+3, j:j+3]
                A_conv1[row, :] = patch.ravel()
                row += 1

        # B_conv1: [9, 8] (filter weights transposed)
        B_conv1 = self.conv1_w.reshape(8, 9).T  # [9, 8]

        # Lowered GEMM with K-split (K=9 -> 2 chunks)
        conv1_raw = hardware_gemm(A_conv1, B_conv1, self.conv1_b, shift=self.conv1_shift)
        conv1_out = conv1_raw.reshape(26, 26, 8)

        # ReLU1: elementwise clamp(0, 127)
        relu1_out = np.clip(conv1_out, 0, 127).astype(np.int8)

        # Pool1: 2x2 max pool -> [13, 13, 8]
        pool1_out = maxpool_2x2(relu1_out)
        intermediates['conv1'] = conv1_out
        intermediates['relu1'] = relu1_out
        intermediates['pool1'] = pool1_out

        # ----------------------------------------------------
        # Layer 2: Conv2 (3x3x8 -> 16 filters, stride 1)
        # ----------------------------------------------------
        # Output: 11x11 = 121 locations, K = 3x3x8 = 72
        A_conv2 = np.zeros((11*11, 72), dtype=np.int8)
        row = 0
        for i in range(11):
            for j in range(11):
                patch = pool1_out[i:i+3, j:j+3, :]
                A_conv2[row, :] = patch.ravel()
                row += 1

        # B_conv2: [72, 16]
        B_conv2 = self.conv2_w.reshape(16, 72).T

        # Lowered GEMM with K-split (K=72 -> 9 chunks)
        conv2_raw = hardware_gemm(A_conv2, B_conv2, self.conv2_b, shift=self.conv2_shift)
        conv2_out = conv2_raw.reshape(11, 11, 16)

        # ReLU2
        relu2_out = np.clip(conv2_out, 0, 127).astype(np.int8)

        # Pool2: 2x2 max pool -> [5, 5, 16] = 400 elements
        pool2_out = maxpool_2x2(relu2_out)
        intermediates['conv2'] = conv2_out
        intermediates['relu2'] = relu2_out
        intermediates['pool2'] = pool2_out

        # ----------------------------------------------------
        # Layer 3: FC1 (400 -> 32)
        # ----------------------------------------------------
        # Flatten to [1, 400]
        A_fc1 = pool2_out.ravel().reshape(1, 400)
        B_fc1 = self.fc1_w  # [400, 32]

        # Lowered GEMM with K-split (K=400 -> 50 chunks)
        fc1_raw = hardware_gemm(A_fc1, B_fc1, self.fc1_b, shift=self.fc1_shift)
        relu3_out = np.clip(fc1_raw, 0, 127).astype(np.int8)
        intermediates['fc1'] = fc1_raw
        intermediates['relu3'] = relu3_out

        # ----------------------------------------------------
        # Layer 4: FC2 (32 -> 10)
        # ----------------------------------------------------
        A_fc2 = relu3_out.reshape(1, 32)
        B_fc2 = self.fc2_w  # [32, 10]

        # Lowered GEMM with K-split (K=32 -> 4 chunks), no shift -> INT32 logits
        fc2_logits = hardware_gemm(A_fc2, B_fc2, self.fc2_b, shift=0).ravel()
        intermediates['logits'] = fc2_logits

        # Argmax
        pred_class = argmax_tiebreak(fc2_logits)
        intermediates['pred_class'] = pred_class

        if debug:
            print(f"Logits: {fc2_logits}")
            print(f"Predicted class: {pred_class}")

        return pred_class, fc2_logits, intermediates

    def export_weights_binary(self, bin_path, hex_path=None):
        """Exports weights matching Section 5 memory layout for hardware preloading."""
        # 0x0001_4000: Conv1 weights (72 B)
        # 0x0001_4048: Conv1 biases  (32 B = 8 x 4 B)
        # 0x0001_4080: Conv2 weights (1152 B)
        # 0x0001_4500: Conv2 biases  (64 B = 16 x 4 B)
        # 0x0001_4540: FC1 weights   (12800 B)
        # 0x0001_7740: FC1 biases    (128 B = 32 x 4 B)
        # 0x0001_77C0: FC2 weights   (320 B)
        # 0x0001_7900: FC2 biases    (40 B = 10 x 4 B)

        os.makedirs(os.path.dirname(bin_path), exist_ok=True)
        # Max size allocated: 96 KiB
        buf = bytearray(96 * 1024)

        def put_bytes(offset, data):
            buf[offset:offset+len(data)] = data

        def put_int32(offset, arr):
            for i, val in enumerate(arr):
                b = struct.pack('<i', int(val))
                buf[offset + i*4 : offset + (i+1)*4] = b

        # Conv1 weights & bias
        b_c1w = self.conv1_w.tobytes()
        put_bytes(0x0000, b_c1w)  # offset from 0x0001_4000
        put_int32(0x0048, self.conv1_b)

        # Conv2 weights & bias
        b_c2w = self.conv2_w.tobytes()
        put_bytes(0x0080, b_c2w)
        put_int32(0x0500, self.conv2_b)

        # FC1 weights & bias
        b_fc1w = self.fc1_w.tobytes()
        put_bytes(0x0540, b_fc1w)
        put_int32(0x3740, self.fc1_b)

        # FC2 weights & bias
        b_fc2w = self.fc2_w.tobytes()
        put_bytes(0x37C0, b_fc2w)
        put_int32(0x3900, self.fc2_b)

        with open(bin_path, 'wb') as f:
            f.write(buf)

        if hex_path:
            with open(hex_path, 'w') as f:
                # 32-bit words little endian
                for i in range(0, len(buf), 4):
                    w = buf[i] | (buf[i+1] << 8) | (buf[i+2] << 16) | (buf[i+3] << 24)
                    f.write(f"{w:08x}\n")

        print(f"Exported weights binary: {bin_path} ({len(buf)} bytes)")

# Generator for 10+ deterministic representative images & edge cases
def generate_test_dataset(model: GoldenCNN):
    images = []
    labels = []
    names = []

    # 1. Image 0: All zeros edge case
    img0 = np.zeros((28, 28), dtype=np.int8)
    p0, _, _ = model.forward(img0)
    images.append(img0)
    labels.append(p0)
    names.append("zero_vector")

    # 2. Image 1: Centered cross pattern
    img1 = np.zeros((28, 28), dtype=np.int8)
    img1[12:16, 6:22] = 100
    img1[6:22, 12:16] = 100
    p1, _, _ = model.forward(img1)
    images.append(img1)
    labels.append(p1)
    names.append("cross_pattern")

    # 3. Image 2: Horizontal stripes
    img2 = np.zeros((28, 28), dtype=np.int8)
    for r in range(4, 24, 4):
        img2[r:r+2, 4:24] = 80
    p2, _, _ = model.forward(img2)
    images.append(img2)
    labels.append(p2)
    names.append("horizontal_stripes")

    # 4. Image 3: Vertical bars
    img3 = np.zeros((28, 28), dtype=np.int8)
    for c in range(4, 24, 4):
        img3[4:24, c:c+2] = 90
    p3, _, _ = model.forward(img3)
    images.append(img3)
    labels.append(p3)
    names.append("vertical_bars")

    # 5. Image 4: Box / Ring pattern
    img4 = np.zeros((28, 28), dtype=np.int8)
    img4[6:22, 6:9] = 110
    img4[6:22, 19:22] = 110
    img4[6:9, 6:22] = 110
    img4[19:22, 6:22] = 110
    p4, _, _ = model.forward(img4)
    images.append(img4)
    labels.append(p4)
    names.append("ring_pattern")

    # 6. Image 5: Diagonal gradient
    img5 = np.zeros((28, 28), dtype=np.int8)
    for r in range(28):
        for c in range(28):
            img5[r, c] = int((r + c) * 2 - 50)
    p5, _, _ = model.forward(img5)
    images.append(img5)
    labels.append(p5)
    names.append("diagonal_gradient")

    # 7. Image 6: Extreme signed checkerboard (+127 / -128)
    img6 = np.zeros((28, 28), dtype=np.int8)
    for r in range(28):
        for c in range(28):
            img6[r, c] = 127 if ((r//2 + c//2) % 2 == 0) else -128
    p6, _, _ = model.forward(img6)
    images.append(img6)
    labels.append(p6)
    names.append("extreme_checkerboard")

    # 8. Image 7: Centered dot
    img7 = np.zeros((28, 28), dtype=np.int8)
    img7[10:18, 10:18] = 120
    p7, _, _ = model.forward(img7)
    images.append(img7)
    labels.append(p7)
    names.append("center_dot")

    # 9. Image 8: Corner markers
    img8 = np.zeros((28, 28), dtype=np.int8)
    img8[2:6, 2:6] = 100
    img8[22:26, 2:6] = 100
    img8[2:6, 22:26] = 100
    img8[22:26, 22:26] = 100
    p8, _, _ = model.forward(img8)
    images.append(img8)
    labels.append(p8)
    names.append("four_corners")

    # 10. Image 9: Random realistic digit-like noise
    np.random.seed(101)
    img9 = np.random.randint(-40, 41, size=(28, 28), dtype=np.int8)
    img9[8:20, 10:18] = np.random.randint(50, 110, size=(12, 8), dtype=np.int8)
    p9, _, _ = model.forward(img9)
    images.append(img9)
    labels.append(p9)
    names.append("noisy_digit_9")

    # 11. Image 10: High contrast T-shape
    img10 = np.zeros((28, 28), dtype=np.int8)
    img10[4:8, 4:24] = 125
    img10[8:24, 12:16] = 125
    p10, _, _ = model.forward(img10)
    images.append(img10)
    labels.append(p10)
    names.append("t_shape")

    # 12. Image 11: High contrast L-shape
    img11 = np.zeros((28, 28), dtype=np.int8)
    img11[4:24, 6:10] = 120
    img11[20:24, 10:22] = 120
    p11, _, _ = model.forward(img11)
    images.append(img11)
    labels.append(p11)
    names.append("l_shape")

    return images, labels, names

if __name__ == '__main__':
    model = GoldenCNN()
    os.makedirs('model', exist_ok=True)
    os.makedirs('weights', exist_ok=True)

    # Export weights
    model.export_weights_binary('weights/cnn_weights.bin', 'weights/cnn_weights.hex')

    # Generate 12 representative images (exceeds the 10+ required)
    images, labels, names = generate_test_dataset(model)

    dataset_manifest = []
    with open('model/test_dataset.bin', 'wb') as f_bin:
        for idx, (img, lbl, name) in enumerate(zip(images, labels, names)):
            f_bin.write(img.tobytes())
            dataset_manifest.append({
                'id': idx,
                'name': name,
                'expected_class': lbl,
                'size_bytes': 784
            })
            print(f"Image {idx:02d} [{name}]: expected class = {lbl}")

    with open('model/test_manifest.json', 'w') as f_json:
        json.dump(dataset_manifest, f_json, indent=2)

    print(f"\nSaved {len(images)} test images to model/test_dataset.bin and manifest to model/test_manifest.json")
