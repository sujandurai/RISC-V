#!/usr/bin/env python3
# ============================================================
#  host/uart_host.py  —  Host Communication Script for Edge-AI SoC
#
#  Authoritative v4.0 Host Protocol:
#    - Physical: 115200 baud, 8N1
#    - Frame Format:
#        SYNC1   : 0xA5
#        SYNC2   : 0x5A
#        TYPE    : 1 byte  (0x01=HELLO, 0x02=INPUT_DATA, 0x03=RUN, 0x04=RESULT, 0x7E=NACK, 0x7F=ACK)
#        LENGTH  : 2 bytes, little-endian (0..256)
#        PAYLOAD : variable
#        CRC16   : 2 bytes, little-endian (CRC16-CCITT, poly=0x1021, init=0xFFFF)
# ============================================================

import sys
import time
import struct
import argparse

# CRC16-CCITT implementation
def crc16_ccitt(data: bytes, init=0xFFFF, poly=0x1021) -> int:
    crc = init
    for b in data:
        crc ^= (b << 8)
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ poly) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc

# Frame types
TYPE_HELLO      = 0x01
TYPE_INPUT_DATA = 0x02
TYPE_RUN        = 0x03
TYPE_RESULT     = 0x04
TYPE_NACK       = 0x7E
TYPE_ACK        = 0x7F

def build_frame(frame_type: int, payload: bytes = b'') -> bytes:
    """Builds a complete binary frame with header and CRC16."""
    length = len(payload)
    assert length <= 256, f"Payload length {length} exceeds maximum 256 bytes"

    header = bytes([0xA5, 0x5A, frame_type, length & 0xFF, (length >> 8) & 0xFF])
    covered_data = bytes([frame_type, length & 0xFF, (length >> 8) & 0xFF]) + payload
    crc = crc16_ccitt(covered_data)
    crc_bytes = struct.pack('<H', crc)
    return header + payload + crc_bytes

def parse_frame(frame_bytes: bytes):
    """Parses and validates a raw frame."""
    if len(frame_bytes) < 7:
        return False, None, "Frame too short"
    if frame_bytes[0] != 0xA5 or frame_bytes[1] != 0x5A:
        return False, None, "Invalid SYNC bytes"

    f_type = frame_bytes[2]
    f_len = frame_bytes[3] | (frame_bytes[4] << 8)
    if len(frame_bytes) != 7 + f_len:
        return False, None, f"Length mismatch: header says {f_len}, got {len(frame_bytes)-7}"

    payload = frame_bytes[5:5+f_len]
    rx_crc = frame_bytes[5+f_len] | (frame_bytes[6+f_len] << 8)

    covered_data = bytes([f_type, frame_bytes[3], frame_bytes[4]]) + payload
    exp_crc = crc16_ccitt(covered_data)
    if rx_crc != exp_crc:
        return False, None, f"CRC mismatch: expected 0x{exp_crc:04X}, received 0x{rx_crc:04X}"

    return True, {'type': f_type, 'length': f_len, 'payload': payload}, "OK"

class HostClient:
    def __init__(self, port=None, baud=115200, timeout=2.0):
        self.port_name = port
        self.baud = baud
        self.timeout = timeout
        self.ser = None

    def connect(self):
        if self.port_name:
            import serial
            self.ser = serial.Serial(self.port_name, self.baud, timeout=self.timeout)
            print(f"Connected to {self.port_name} at {self.baud} baud")
        else:
            print("Running in loopback / simulation mode (no physical serial port specified)")

    def send_raw(self, data: bytes):
        if self.ser:
            self.ser.write(data)
            self.ser.flush()

    def read_exact(self, num_bytes: int) -> bytes:
        if self.ser:
            return self.ser.read(num_bytes)
        return b''

    def read_frame(self, timeout=2.0) -> dict:
        """Reads one complete valid frame from serial."""
        start_t = time.time()
        buf = bytearray()
        while time.time() - start_t < timeout:
            b = self.read_exact(1)
            if not b:
                continue
            buf += b
            # Search for sync
            if len(buf) >= 2 and buf[-2] == 0xA5 and buf[-1] == 0x5A:
                # Found sync! Now read type and length (3 bytes)
                hdr = self.read_exact(3)
                if len(hdr) < 3:
                    return None
                f_type = hdr[0]
                f_len = hdr[1] | (hdr[2] << 8)
                payload = self.read_exact(f_len)
                crc_b = self.read_exact(2)
                full = bytes([0xA5, 0x5A]) + hdr + payload + crc_b
                ok, parsed, err = parse_frame(full)
                if ok:
                    return parsed
                else:
                    print(f"Warning: Frame parse error: {err}")
        return None

    def send_hello(self):
        """Sends HELLO and expects ACK."""
        frame = build_frame(TYPE_HELLO, b'')
        print(f"Sending HELLO frame ({len(frame)} bytes)...")
        self.send_raw(frame)
        resp = self.read_frame()
        if resp and resp['type'] == TYPE_ACK:
            print("Received ACK from FPGA!")
            return True
        print(f"Failed to receive ACK: {resp}")
        return False

    def send_tensor(self, tensor_bytes: bytes):
        """Sends 784-byte INT8 tensor in chunks <= 256 bytes."""
        assert len(tensor_bytes) == 784
        chunk_size = 196
        for offset in range(0, 784, chunk_size):
            chunk = tensor_bytes[offset:offset+chunk_size]
            # Payload format: [offset_lo, offset_hi, data...]
            chunk_payload = struct.pack('<H', offset) + chunk
            frame = build_frame(TYPE_INPUT_DATA, chunk_payload)
            print(f"Sending INPUT_DATA chunk at offset {offset} ({len(chunk)} bytes)...")
            self.send_raw(frame)
            resp = self.read_frame()
            if not resp or resp['type'] != TYPE_ACK:
                raise RuntimeError(f"Chunk at offset {offset} not ACKed! {resp}")
        print("All 784 tensor bytes transferred and ACKed!")

    def run_inference(self):
        """Sends RUN command and waits for RESULT."""
        frame = build_frame(TYPE_RUN, b'')
        print("Sending RUN command...")
        t0 = time.time()
        self.send_raw(frame)
        resp = self.read_frame(timeout=10.0)
        t_total = time.time() - t0
        if resp and resp['type'] == TYPE_RESULT:
            # Result payload: [class (1B), cycle_count (4B), logits (10 x 4B = 40B)]
            pred_class = resp['payload'][0]
            cycle_cnt = struct.unpack('<I', resp['payload'][1:5])[0]
            logits = struct.unpack('<10i', resp['payload'][5:45])
            print(f"RESULT RECEIVED: Predicted Class = {pred_class}")
            print(f"FPGA Hardware Execution Cycles = {cycle_cnt} ({cycle_cnt * 10 / 1e6:.2f} ms)")
            print(f"Total Host Latency (including UART) = {t_total * 1000:.2f} ms")
            print(f"INT32 Logits: {logits}")
            return pred_class, logits, cycle_cnt
        raise RuntimeError(f"Inference failed or timed out: {resp}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Edge-AI RISC-V SoC UART Host Client")
    parser.add_argument('--port', type=str, default=None, help="Serial port (e.g. COM3, /dev/ttyUSB0)")
    parser.add_argument('--baud', type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument('--test-frame', action='store_true', help="Run internal frame unit tests")
    args = parser.parse_args()

    if args.test_frame or args.port is None:
        print("Running Host Frame & Protocol Verification...")
        # Verify frame builder and parser
        hello = build_frame(TYPE_HELLO, b'')
        ok, res, msg = parse_frame(hello)
        assert ok and res['type'] == TYPE_HELLO and res['length'] == 0
        print(f"HELLO Frame Verification: PASS ({hello.hex().upper()})")

        data_test = bytes([i % 256 for i in range(256)])
        data_frame = build_frame(TYPE_INPUT_DATA, data_test)
        ok, res, msg = parse_frame(data_frame)
        assert ok and res['type'] == TYPE_INPUT_DATA and res['length'] == 256 and res['payload'] == data_test
        print(f"INPUT_DATA (256-byte) Verification: PASS (CRC = 0x{res['length']:04X})")

        run_frame = build_frame(TYPE_RUN, b'')
        ok, res, msg = parse_frame(run_frame)
        assert ok and res['type'] == TYPE_RUN
        print("RUN Frame Verification: PASS")

        # Test CRC corruption
        corrupted = bytearray(hello)
        corrupted[-1] ^= 0xFF
        ok, res, msg = parse_frame(bytes(corrupted))
        assert not ok and "CRC mismatch" in msg
        print("Corrupted CRC Rejection: PASS")
        print("All host protocol unit tests passed successfully!")
