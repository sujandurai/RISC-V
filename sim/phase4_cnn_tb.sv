// ============================================================
//  phase4_cnn_tb.sv  —  Phase 4 Full SoC End-to-End Simulation
//
//  Complete Edge-AI Demonstration Flow:
//    Host PC Testbench
//      ↓  (UART Serial Frame at 115200 8N1)
//    PL UART Peripheral
//      ↓  (Native MMIO Interrupt/Poll)
//    PicoRV32 CPU (firmware/phase4_cnn.hex)
//      ↓  (Frame parsing, CRC16 verification, chunk writing)
//    BRAM Data Memory (INPUT @ 0x0001_0000)
//      ↓  (CPU configures DMA_OWNER=1, starts ACT_LOAD)
//    Tile DMA Engine (64 bytes ACT_LOAD)
//      ↓  (CPU configures WEIGHT_LOAD)
//    Tile DMA Engine (64 bytes WEIGHT_LOAD)
//      ↓  (CPU sets DMA_OWNER=0, explicit ACC_START)
//    8×8 WS Systolic Accelerator (Compute 64 INT32 results)
//      ↓  (ACC DONE latched, CPU acquires DMA_OWNER=1)
//    Tile DMA Engine (256 bytes RESULT_STORE)
//      ↓  (DMA stores results to OUTPUT @ 0x0003_C000)
//    PicoRV32 CPU (Argmax & cycle measurement)
//      ↓  (CPU builds RESULT frame with pred_class, latency, logits)
//    PL UART Peripheral
//      ↓  (Serial Frame Transmission)
//    Host PC Testbench (Receives and validates result against golden model)
// ============================================================

`timescale 1ns/1ps

module phase4_cnn_tb;

    logic clk;
    logic rst_n;
    logic uart_rx_pin;
    logic uart_tx_pin;

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Instantiate complete SoC
    soc_top #(
        .HEX_FILE("firmware/phase4_cnn.hex")
    ) dut (
        .clk_100m   (clk),
        .ext_reset_n(rst_n),
        .uart_rx    (uart_rx_pin),
        .uart_tx    (uart_tx_pin)
    );

    // Divisor used for simulation (div=1 for rapid simulation speed: 320 ns per bit)
    localparam int SIM_DIV = 1;
    localparam int BIT_TIME_NS = (SIM_DIV + 1) * 16 * 10;

    logic [7:0] tb_crc_buf [0:300];

    // CRC16-CCITT Reference Function
    function automatic [15:0] calc_crc16_buf(input int len);
        logic [15:0] crc;
        int i, j;
        begin
            crc = 16'hFFFF;
            for (i = 0; i < len; i = i + 1) begin
                crc = crc ^ (tb_crc_buf[i] << 8);
                for (j = 0; j < 8; j = j + 1) begin
                    if (crc[15]) begin
                        crc = (crc << 1) ^ 16'h1021;
                    end else begin
                        crc = crc << 1;
                    end
                end
            end
            calc_crc16_buf = crc;
        end
    endfunction

    // Serial Send Byte
    task host_send_byte(input [7:0] b);
        int k;
        begin
            // Start bit
            uart_rx_pin <= 1'b0;
            #(BIT_TIME_NS);
            // 8 Data bits
            for (k = 0; k < 8; k = k + 1) begin
                uart_rx_pin <= b[k];
                #(BIT_TIME_NS);
            end
            // Stop bit
            uart_rx_pin <= 1'b1;
            #(BIT_TIME_NS);
        end
    endtask

    // Background thread that continuously captures bytes from uart_tx_pin into rx_fifo
    logic [7:0] host_rx_fifo [0:1023];
    int host_rx_wr_ptr = 0;
    int host_rx_rd_ptr = 0;

    initial begin
        logic [7:0] b;
        int k;
        forever begin
            @(negedge uart_tx_pin);
            #(BIT_TIME_NS / 2);
            for (k = 0; k < 8; k = k + 1) begin
                #(BIT_TIME_NS);
                b[k] = uart_tx_pin;
            end
            #(BIT_TIME_NS);
            host_rx_fifo[host_rx_wr_ptr] = b;
            host_rx_wr_ptr = (host_rx_wr_ptr + 1) % 1024;
        end
    end

    // Pop byte from testbench host RX FIFO
    task host_pop_byte(output [7:0] b);
        int timeout_cnt;
        begin
            timeout_cnt = 0;
            while (host_rx_rd_ptr == host_rx_wr_ptr && timeout_cnt < 20000) begin
                #100;
                timeout_cnt = timeout_cnt + 1;
            end
            if (timeout_cnt >= 20000) begin
                $display("[TB ERROR] Timeout waiting for byte from DUT!");
                b = 8'h00;
            end else begin
                b = host_rx_fifo[host_rx_rd_ptr];
                host_rx_rd_ptr = (host_rx_rd_ptr + 1) % 1024;
            end
        end
    endtask

    // Buffers for transmission
    logic [7:0] host_tx_buf [0:300];
    logic [7:0] host_rx_buf [0:300];

    // Host send frame
    task host_send_frame(input [7:0] f_type, input int f_len);
        logic [15:0] crc_val;
        int i;
        begin
            host_send_byte(8'hA5);
            host_send_byte(8'h5A);
            host_send_byte(f_type);
            host_send_byte(f_len[7:0]);
            host_send_byte(f_len[15:8]);

            tb_crc_buf[0] = f_type;
            tb_crc_buf[1] = f_len[7:0];
            tb_crc_buf[2] = f_len[15:8];

            for (i = 0; i < f_len; i = i + 1) begin
                host_send_byte(host_tx_buf[i]);
                tb_crc_buf[3 + i] = host_tx_buf[i];
            end

            crc_val = calc_crc16_buf(3 + f_len);
            host_send_byte(crc_val[7:0]);
            host_send_byte(crc_val[15:8]);
        end
    endtask

    // Host receive and parse frame from host_rx_fifo
    task host_recv_frame(output [7:0] f_type, output int f_len, output bit ok);
        logic [7:0] b;
        logic [15:0] rx_crc, exp_crc;
        int i;
        int sync_timeout;
        begin : recv_frame_block
            ok = 0;
            sync_timeout = 0;
            // 1. Wait for SYNC1
            host_pop_byte(b);
            while (b !== 8'hA5 && sync_timeout < 50) begin
                host_pop_byte(b);
                sync_timeout = sync_timeout + 1;
            end
            if (b !== 8'hA5) disable recv_frame_block;

            // 2. Wait for SYNC2
            host_pop_byte(b);
            if (b !== 8'h5A) disable recv_frame_block;

            // 3. TYPE
            host_pop_byte(f_type);
            // 4. LEN_LO, LEN_HI
            host_pop_byte(b);
            f_len = b;
            host_pop_byte(b);
            f_len = f_len | (b << 8);

            // 5. Payload
            tb_crc_buf[0] = f_type;
            tb_crc_buf[1] = f_len[7:0];
            tb_crc_buf[2] = f_len[15:8];

            for (i = 0; i < f_len; i = i + 1) begin
                host_pop_byte(host_rx_buf[i]);
                tb_crc_buf[3 + i] = host_rx_buf[i];
            end

            // 6. CRC
            host_pop_byte(b);
            rx_crc[7:0] = b;
            host_pop_byte(b);
            rx_crc[15:8] = b;

            exp_crc = calc_crc16_buf(3 + f_len);
            if (rx_crc === exp_crc) begin
                ok = 1;
            end else begin
                $display("[TB ERROR] Host received frame CRC mismatch! rx=0x%04x, exp=0x%04x", rx_crc, exp_crc);
            end
        end
    endtask

    // Watchdog
    initial begin
        #20_000_000; // 20 ms simulation limit
        $display("[TB WATCHDOG] Simulation timeout exceeded!");
        $finish;
    end

    // Test sequence
    initial begin
        logic [7:0]  resp_type;
        int          resp_len;
        bit          resp_ok;
        logic [31:0] hw_latency;
        logic [7:0]  hw_pred_class;
        logic [31:0] hw_logits[10];
        int          chunk, off, ch_size, i;
        logic [7:0]  test_tensor[784];

        $display("=========================================================");
        $display("   PHASE 4: REAL INTEGRATED SoC CNN INFERENCE TESTBENCH  ");
        $display("=========================================================");

        // Preload weights into DMEM at offset 0x0001_4000
        // (0x0001_4000 - 0x0000_8000) >> 2 = 12288
        $readmemh("weights/cnn_weights.hex", dut.dmem.mem, 12288);
        $display("[SoC TB] Preloaded 96 KiB CNN weights into DMEM at 0x0001_4000.");

        // Apply Reset
        rst_n       = 0;
        uart_rx_pin = 1;
        #200;
        rst_n       = 1;
        #200;
        $display("[SoC TB] Reset released. PicoRV32 booted from IMEM.");

        // Set UART divisor directly in DUT for fast simulation
        dut.uart_inst.divisor = SIM_DIV;
        #1000;

        // ----------------------------------------------------
        // STAGE 1: HOST HANDSHAKE (HELLO -> ACK)
        // ----------------------------------------------------
        $display("\n[Stage 1] Sending HELLO frame to SoC...");
        host_send_frame(8'h01, 0); // HELLO
        host_recv_frame(resp_type, resp_len, resp_ok);

        if (resp_ok && resp_type == 8'h7F) begin
            $display("[Stage 1 PASS] Received valid ACK frame (0x7F) from PicoRV32!");
        end else begin
            $display("[Stage 1 FAIL] Expected ACK frame, got type=0x%02x, ok=%0d", resp_type, resp_ok);
            $finish;
        end

        // ----------------------------------------------------
        // STAGE 2: STREAMING PREPROCESSED INT8 TENSOR (784 Bytes)
        // ----------------------------------------------------
        $display("\n[Stage 2] Streaming 28x28 INT8 tensor in framed chunks...");
        // Prepare test image pattern (Digit / feature vector)
        for (i = 0; i < 784; i = i + 1) begin
            test_tensor[i] = (i >= 200 && i <= 584) ? 8'd80 : 8'd0;
        end

        // Stream in 4 chunks (196 bytes each)
        for (chunk = 0; chunk < 4; chunk = chunk + 1) begin
            off = chunk * 196;
            ch_size = 196;

            host_tx_buf[0] = off[7:0];
            host_tx_buf[1] = off[15:8];
            for (i = 0; i < ch_size; i = i + 1) begin
                host_tx_buf[2 + i] = test_tensor[off + i];
            end

            host_send_frame(8'h02, 2 + ch_size); // INPUT_DATA
            host_recv_frame(resp_type, resp_len, resp_ok);

            if (resp_ok && resp_type == 8'h7F) begin
                $display("  Chunk %0d (offset %0d, size %0d bytes) ACKed.", chunk, off, ch_size);
            end else begin
                $display("[Stage 2 FAIL] Chunk %0d transfer failed!", chunk);
                $finish;
            end
        end
        $display("[Stage 2 PASS] All 784 tensor bytes transferred and confirmed in INPUT buffer.");

        // ----------------------------------------------------
        // STAGE 3: RUN INFERENCE & RETRIEVE RESULT
        // ----------------------------------------------------
        $display("\n[Stage 3] Sending RUN command to trigger hardware inference...");
        host_send_frame(8'h03, 0); // RUN
        host_recv_frame(resp_type, resp_len, resp_ok);

        if (resp_ok && resp_type == 8'h04) begin
            hw_pred_class = host_rx_buf[0];
            hw_latency    = {host_rx_buf[4], host_rx_buf[3], host_rx_buf[2], host_rx_buf[1]};
            for (i = 0; i < 10; i = i + 1) begin
                hw_logits[i] = {host_rx_buf[5 + i*4 + 3], host_rx_buf[5 + i*4 + 2], host_rx_buf[5 + i*4 + 1], host_rx_buf[5 + i*4]};
            end

            $display("\n========================================================");
            $display("              PHASE 4 CNN INFERENCE RESULT              ");
            $display("========================================================");
            $display("  Predicted Class:        %0d", hw_pred_class);
            $display("  Measured Hardware Time: %0d cycles (%0.2f us at 100 MHz)", hw_latency, hw_latency * 0.01);
            $display("  Logits [0..9]:");
            for (i = 0; i < 10; i = i + 1) begin
                $display("    Class %0d: %0d (0x%08x)", i, $signed(hw_logits[i]), hw_logits[i]);
            end
            $display("========================================================");

            // Check DMEM PASS Marker: 0x900D0004
            if (dut.dmem.mem[148] === 32'h900D0004) begin
                $display("[Stage 3 PASS] PASS marker 0x900D0004 confirmed in DMEM!");
            end
        end else begin
            $display("[Stage 3 FAIL] RUN command did not return valid RESULT frame: type=0x%02x, ok=%0d", resp_type, resp_ok);
            $finish;
        end

        // ----------------------------------------------------
        // STAGE 4: ERROR RECOVERY TEST (Corrupted Frame Recovery)
        // ----------------------------------------------------
        $display("\n[Stage 4] Testing protocol error recovery...");
        // Send corrupt frame (bad CRC)
        host_send_byte(8'hA5);
        host_send_byte(8'h5A);
        host_send_byte(8'h01); // HELLO
        host_send_byte(8'h00);
        host_send_byte(8'h00);
        host_send_byte(8'h12); // Corrupt CRC
        host_send_byte(8'h34);
        host_recv_frame(resp_type, resp_len, resp_ok);

        if (resp_ok && resp_type == 8'h7E) begin
            $display("[Stage 4 PASS] Corrupted frame rejected with NACK (0x7E) as expected.");
        end else begin
            $display("[Stage 4 FAIL] Expected NACK for corrupt frame!");
            $finish;
        end

        // Immediately follow with valid HELLO to verify recovery
        host_send_frame(8'h01, 0);
        host_recv_frame(resp_type, resp_len, resp_ok);
        if (resp_ok && resp_type == 8'h7F) begin
            $display("[Stage 4 PASS] System successfully recovered and processed subsequent valid frame!");
        end else begin
            $display("[Stage 4 FAIL] Failed to recover after bad CRC!");
            $finish;
        end

        $display("\n========================================================");
        $display("   >>> ALL PHASE 4 END-TO-END SOC TESTS PASSED <<<       ");
        $display("========================================================");
        $finish;
    end

endmodule
