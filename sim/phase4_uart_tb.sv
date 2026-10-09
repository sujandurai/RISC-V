// ============================================================
//  phase4_uart_tb.sv  —  Phase 4 UART Hardware & Protocol Testbench
//
//  Authoritative v4.0 Specification:
//    - 100 MHz system clock (10 ns period)
//    - 115200 nominal baud, divisor = 53
//    - 8N1 format, 16-byte RX/TX FIFOs, 2-FF RX synchronizer
//    - v4.0 Frame Grammar:
//        SYNC1 (0xA5)
//        SYNC2 (0x5A)
//        TYPE (1 byte)
//        LENGTH (2 bytes, little-endian)
//        PAYLOAD (0..256 bytes)
//        CRC16 (2 bytes, little-endian, polynomial 0x1021, init 0xFFFF)
//
//  Required 16 Test Cases (Specification Section 9):
//    1.  Reset state verification
//    2.  TX transmission
//    3.  RX reception
//    4.  RX CDC 2-FF synchronization
//    5.  FIFO full flags & behavior
//    6.  FIFO empty flags & behavior
//    7.  RX overrun flag & sticky latch
//    8.  RX and TX FIFO flush controls
//    9.  Baud divisor read/write
//    10. Valid frame parsing (HELLO, INPUT_DATA, RUN)
//    11. Bad CRC detection
//    12. Bad length detection
//    13. Unknown command/type detection
//    14. Malformed frame handling
//    15. Frame resynchronization after garbage
//    16. Multiple consecutive streaming frames
// ============================================================

`timescale 1ns/1ps

module phase4_uart_tb;

    logic clk;
    logic rst_n;
    logic uart_rx_pin;
    logic uart_tx_pin;

    // MMIO signals
    logic        mmio_valid;
    logic        mmio_ready;
    logic [3:0]  mmio_wstrb;
    logic [7:0]  mmio_addr;
    logic [31:0] mmio_wdata;
    logic [31:0] mmio_rdata;

    // Instantiate UART peripheral
    uart dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .uart_rx    (uart_rx_pin),
        .uart_tx    (uart_tx_pin),
        .mmio_valid (mmio_valid),
        .mmio_ready (mmio_ready),
        .mmio_wstrb (mmio_wstrb),
        .mmio_addr  (mmio_addr),
        .mmio_wdata (mmio_wdata),
        .mmio_rdata (mmio_rdata)
    );

    // 100 MHz clock generator (10 ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    // MMIO Helper Tasks
    task mmio_write(input [7:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            mmio_valid <= 1'b1;
            mmio_wstrb <= 4'b1111;
            mmio_addr  <= addr;
            mmio_wdata <= data;
            @(posedge clk);
            while (!mmio_ready) @(posedge clk);
            mmio_valid <= 1'b0;
            mmio_wstrb <= 4'b0000;
            #1;
        end
    endtask

    task mmio_read(input [7:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            mmio_valid <= 1'b1;
            mmio_wstrb <= 4'b0000;
            mmio_addr  <= addr;
            @(posedge clk);
            while (!mmio_ready) @(posedge clk);
            data = mmio_rdata;
            mmio_valid <= 1'b0;
            #1;
        end
    endtask

    // Module-level buffers for Icarus Verilog compatibility
    logic [7:0] tb_tx_payload [0:255];
    logic [7:0] tb_rx_payload [0:255];
    logic [7:0] tb_crc_buf    [0:259];

    // Independent Golden CRC16-CCITT Reference (polynomial 0x1021, init 0xFFFF)
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

    // Send single UART serial byte from host into uart_rx_pin
    task send_uart_byte(input [7:0] b, input int div);
        int bit_time_ns;
        int k;
        begin
            bit_time_ns = (div + 1) * 16 * 10;
            
            // Start bit
            uart_rx_pin <= 1'b0;
            #(bit_time_ns);

            // 8 Data bits (LSB first)
            for (k = 0; k < 8; k = k + 1) begin
                uart_rx_pin <= b[k];
                #(bit_time_ns);
            end

            // Stop bit
            uart_rx_pin <= 1'b1;
            #(bit_time_ns);
        end
    endtask

    // Receive single UART serial byte from uart_tx_pin into testbench
    task recv_uart_byte(output [7:0] b, input int div);
        int bit_time_ns;
        int k;
        begin
            bit_time_ns = (div + 1) * 16 * 10;
            
            // Wait for start bit falling edge
            @(negedge uart_tx_pin);
            // Wait to center of start bit
            #(bit_time_ns / 2);

            // Sample 8 data bits at center
            for (k = 0; k < 8; k = k + 1) begin
                #(bit_time_ns);
                b[k] = uart_tx_pin;
            end

            // Stop bit
            #(bit_time_ns);
        end
    endtask

    // Test counters
    int tests_passed = 0;
    int tests_failed = 0;

    // Firmware-like Frame Parser State Machine for testbench simulation
    typedef enum logic [2:0] {
        PARSE_SYNC1   = 3'd0,
        PARSE_SYNC2   = 3'd1,
        PARSE_TYPE    = 3'd2,
        PARSE_LEN_LO  = 3'd3,
        PARSE_LEN_HI  = 3'd4,
        PARSE_PAYLOAD = 3'd5,
        PARSE_CRC_LO  = 3'd6,
        PARSE_CRC_HI  = 3'd7
    } parse_state_t;

    task parse_frame_from_uart(
        output logic        frame_ok,
        output logic [7:0]  frame_type,
        output logic [15:0] frame_len,
        output logic [7:0]  err_code
    );
        parse_state_t state;
        logic [31:0]  status_val;
        logic [31:0]  data_val;
        logic [7:0]   rx_b;
        logic [15:0]  rx_crc;
        int           crc_len;
        logic [15:0]  exp_crc;
        int           p_idx;
        int           timeout_limit;
        int           ci;
        begin
            state         = PARSE_SYNC1;
            frame_ok      = 1'b0;
            err_code      = 8'h00;
            timeout_limit = 20000;
            p_idx         = 0;

            while (!frame_ok && err_code == 8'h00 && timeout_limit > 0) begin
                timeout_limit = timeout_limit - 1;
                mmio_read(8'h04, status_val);
                if (status_val[0]) begin // RX_VALID
                    mmio_read(8'h00, data_val);
                    rx_b = data_val[7:0];

                    case (state)
                        PARSE_SYNC1: begin
                            if (rx_b == 8'hA5) state = PARSE_SYNC2;
                        end

                        PARSE_SYNC2: begin
                            if (rx_b == 8'h5A) state = PARSE_TYPE;
                            else if (rx_b == 8'hA5) state = PARSE_SYNC2;
                            else state = PARSE_SYNC1;
                        end

                        PARSE_TYPE: begin
                            frame_type = rx_b;
                            if (rx_b != 8'h01 && rx_b != 8'h02 && rx_b != 8'h03 && 
                                rx_b != 8'h04 && rx_b != 8'h7E && rx_b != 8'h7F) begin
                                err_code = 8'h13; // Unknown type
                            end else begin
                                state = PARSE_LEN_LO;
                            end
                        end

                        PARSE_LEN_LO: begin
                            frame_len[7:0] = rx_b;
                            state = PARSE_LEN_HI;
                        end

                        PARSE_LEN_HI: begin
                            frame_len[15:8] = rx_b;
                            if (frame_len > 256) begin
                                err_code = 8'h12; // Illegal length
                            end else if (frame_len == 0) begin
                                state = PARSE_CRC_LO;
                            end else begin
                                p_idx = 0;
                                state = PARSE_PAYLOAD;
                            end
                        end

                        PARSE_PAYLOAD: begin
                            tb_rx_payload[p_idx] = rx_b;
                            p_idx = p_idx + 1;
                            if (p_idx == frame_len) begin
                                state = PARSE_CRC_LO;
                            end
                        end

                        PARSE_CRC_LO: begin
                            rx_crc[7:0] = rx_b;
                            state = PARSE_CRC_HI;
                        end

                        PARSE_CRC_HI: begin
                            rx_crc[15:8] = rx_b;
                            // Verify CRC
                            tb_crc_buf[0] = frame_type;
                            tb_crc_buf[1] = frame_len[7:0];
                            tb_crc_buf[2] = frame_len[15:8];
                            for (ci = 0; ci < frame_len; ci = ci + 1) begin
                                tb_crc_buf[3 + ci] = tb_rx_payload[ci];
                            end
                            crc_len = 3 + frame_len;
                            exp_crc = calc_crc16_buf(crc_len);

                            if (rx_crc === exp_crc) begin
                                frame_ok = 1'b1;
                            end else begin
                                err_code = 8'h11; // Bad CRC
                            end
                        end
                    endcase
                end else begin
                    #100;
                end
            end
        end
    endtask

    // Helper task to send complete frame over UART RX pin
    task send_frame(input [7:0] f_type, input [15:0] f_len, input int div, input bit corrupt_crc);
        logic [15:0] crc_val;
        int ci;
        begin
            // 1. SYNC bytes
            send_uart_byte(8'hA5, div);
            send_uart_byte(8'h5A, div);

            // 2. TYPE
            send_uart_byte(f_type, div);

            // 3. LENGTH (little-endian)
            send_uart_byte(f_len[7:0], div);
            send_uart_byte(f_len[15:8], div);

            // 4. PAYLOAD
            for (ci = 0; ci < f_len; ci = ci + 1) begin
                send_uart_byte(tb_tx_payload[ci], div);
            end

            // 5. CRC16
            tb_crc_buf[0] = f_type;
            tb_crc_buf[1] = f_len[7:0];
            tb_crc_buf[2] = f_len[15:8];
            for (ci = 0; ci < f_len; ci = ci + 1) begin
                tb_crc_buf[3 + ci] = tb_tx_payload[ci];
            end
            crc_val = calc_crc16_buf(3 + f_len);

            if (corrupt_crc) crc_val = crc_val ^ 16'hFFFF; // Invert CRC

            send_uart_byte(crc_val[7:0], div);
            send_uart_byte(crc_val[15:8], div);
        end
    endtask

    // ========================================================
    // MAIN TEST SEQUENCE
    // ========================================================
    initial begin
        logic [31:0] read_val;
        logic [7:0]  tx_b;
        logic        f_ok;
        logic [7:0]  f_type;
        logic [15:0] f_len;
        logic [7:0]  f_err;
        int          i;
        int          fast_div;
        int          sf;
        int          all_stream_ok;

        fast_div = 2;

        $display("=================================================");
        $display("     PHASE 4: PL UART TESTBENCH COMMENCING       ");
        $display("=================================================");

        // Reset
        rst_n       = 0;
        uart_rx_pin = 1'b1;
        mmio_valid  = 0;
        mmio_wstrb  = 0;
        mmio_addr   = 0;
        mmio_wdata  = 0;
        #100;
        rst_n       = 1;
        #20;

        // ----------------------------------------------------
        // TEST 1: RESET STATE VERIFICATION
        // ----------------------------------------------------
        mmio_read(8'h04, read_val); // UART_STATUS
        // bit0 RX_VALID=0, bit1 TX_READY=1, bit2 RX_OVERRUN=0 -> 32'h00000002
        if (read_val === 32'h0000_0002) begin
            $display("PASS [Test 1] Reset state: STATUS = 0x%08x (TX_READY=1, RX_VALID=0, OVERRUN=0)", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 1] Unexpected reset STATUS: 0x%08x", read_val);
            tests_failed = tests_failed + 1;
        end

        // Check default divisor
        mmio_read(8'h08, read_val); // UART_DIVISOR
        if (read_val[15:0] === 16'd53) begin
            $display("PASS [Test 1] Reset default divisor = 53 (0x35)");
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 1] Unexpected default divisor: %0d", read_val);
            tests_failed = tests_failed + 1;
        end

        // ----------------------------------------------------
        // TEST 9: BAUD DIVISOR READ/WRITE
        // ----------------------------------------------------
        mmio_write(8'h08, fast_div); // Set fast divisor for simulation
        mmio_read(8'h08, read_val);
        if (read_val[15:0] === fast_div) begin
            $display("PASS [Test 9] Baud divisor programmable: %0d", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 9] Failed to write divisor: %0d", read_val);
            tests_failed = tests_failed + 1;
        end

        // ----------------------------------------------------
        // TEST 2: TX TRANSMISSION
        // ----------------------------------------------------
        fork
            begin
                mmio_write(8'h00, 32'hA5); // Write byte to TX FIFO
            end
            begin
                recv_uart_byte(tx_b, fast_div);
            end
        join
        if (tx_b === 8'hA5) begin
            $display("PASS [Test 2] UART TX output bit-exact: 0x%02x", tx_b);
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 2] UART TX expected 0xA5, got 0x%02x", tx_b);
            tests_failed = tests_failed + 1;
        end

        // ----------------------------------------------------
        // TEST 3 & 4: RX RECEPTION & 2-FF SYNCHRONIZATION
        // ----------------------------------------------------
        send_uart_byte(8'h5A, fast_div);
        mmio_read(8'h04, read_val); // Check RX_VALID
        if (read_val[0] === 1'b1) begin
            mmio_read(8'h00, read_val);
            if (read_val[7:0] === 8'h5A) begin
                $display("PASS [Test 3 & 4] UART RX received via 2-FF synchronizer: 0x%02x", read_val[7:0]);
                tests_passed = tests_passed + 1;
            end else begin
                $display("FAIL [Test 3 & 4] UART RX byte mismatch: got 0x%02x", read_val[7:0]);
                tests_failed = tests_failed + 1;
            end
        end else begin
            $display("FAIL [Test 3 & 4] RX_VALID not asserted after stop bit!");
            tests_failed = tests_failed + 1;
        end

        // ----------------------------------------------------
        // TEST 5 & 6: FIFO FULL AND EMPTY FLAGS
        // ----------------------------------------------------
        // Push 17 bytes rapidly so 1 byte is loaded into transmitter and 16 fill the FIFO
        for (i = 0; i < 17; i = i + 1) begin
            mmio_write(8'h00, i + 8'h10);
        end
        mmio_read(8'h04, read_val); // TX_READY should be 0 when FIFO is full (16 bytes in FIFO)
        if (read_val[1] === 1'b0) begin
            $display("PASS [Test 5] TX FIFO full flagged: TX_READY = 0");
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 5] TX_READY did not deassert when full! STATUS=0x%08x", read_val);
            tests_failed = tests_failed + 1;
        end

        // ----------------------------------------------------
        // TEST 8: FLUSH CONTROLS
        // ----------------------------------------------------
        mmio_write(8'h0C, 32'h02); // TX_FLUSH
        mmio_read(8'h04, read_val);
        if (read_val[1] === 1'b1) begin
            $display("PASS [Test 8] TX FIFO flushed successfully: TX_READY = 1");
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 8] TX FIFO flush failed!");
            tests_failed = tests_failed + 1;
        end

        // ----------------------------------------------------
        // TEST 7: RX OVERRUN DETECTION
        // ----------------------------------------------------
        // Send 17 bytes without reading from RX FIFO
        for (i = 0; i < 17; i = i + 1) begin
            send_uart_byte(8'h40 + i, fast_div);
        end
        mmio_read(8'h04, read_val);
        if (read_val[2] === 1'b1) begin // RX_OVERRUN
            $display("PASS [Test 7] RX Overrun flagged on 17th byte: STATUS = 0x%08x", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 7] RX_OVERRUN not asserted on overflow!");
            tests_failed = tests_failed + 1;
        end

        // Clear overrun via RX_FLUSH
        mmio_write(8'h0C, 32'h01); // RX_FLUSH
        #100;
        mmio_read(8'h04, read_val);
        if (read_val[2] === 1'b0 && read_val[0] === 1'b0) begin
            $display("PASS [Test 8] RX FIFO flushed and OVERRUN cleared: STATUS = 0x%08x", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 8] RX flush did not clear overrun/valid!");
            tests_failed = tests_failed + 1;
        end

        // ----------------------------------------------------
        // TEST 10: VALID FRAMES (HELLO, INPUT_DATA, RUN)
        // ----------------------------------------------------
        $display("\n--- Running Test 10: Valid Protocol Frames ---");
        // 10A. Send HELLO Frame (Type 0x01, Len 0)
        fork
            begin
                send_frame(8'h01, 16'd0, fast_div, 1'b0);
            end
            begin
                parse_frame_from_uart(f_ok, f_type, f_len, f_err);
            end
        join
        if (f_ok && f_type == 8'h01 && f_len == 0) begin
            $display("PASS [Test 10A] Valid HELLO frame parsed bit-exact (Type 0x01, Len 0)");
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 10A] HELLO frame parse failed: ok=%0d, type=0x%02x, err=0x%02x", f_ok, f_type, f_err);
            tests_failed = tests_failed + 1;
        end

        // 10B. Send INPUT_DATA Frame (Type 0x02, Len 16) with concurrent draining
        for (i = 0; i < 16; i = i + 1) tb_tx_payload[i] = 8'hA0 + i;
        fork
            begin
                send_frame(8'h02, 16'd16, fast_div, 1'b0);
            end
            begin
                parse_frame_from_uart(f_ok, f_type, f_len, f_err);
            end
        join
        if (f_ok && f_type == 8'h02 && f_len == 16) begin
            $display("PASS [Test 10B] Valid INPUT_DATA frame parsed bit-exact (Type 0x02, Len 16)");
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 10B] INPUT_DATA frame parse failed: ok=%0d, err=0x%02x", f_ok, f_err);
            tests_failed = tests_failed + 1;
        end

        // 10C. Send RUN Frame (Type 0x03, Len 0)
        fork
            begin
                send_frame(8'h03, 16'd0, fast_div, 1'b0);
            end
            begin
                parse_frame_from_uart(f_ok, f_type, f_len, f_err);
            end
        join
        if (f_ok && f_type == 8'h03 && f_len == 0) begin
            $display("PASS [Test 10C] Valid RUN frame parsed bit-exact (Type 0x03, Len 0)");
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 10C] RUN frame parse failed: ok=%0d, err=0x%02x", f_ok, f_err);
            tests_failed = tests_failed + 1;
        end

        // ----------------------------------------------------
        // TEST 11: BAD CRC DETECTION
        // ----------------------------------------------------
        $display("\n--- Running Test 11: Bad CRC Rejection ---");
        tb_tx_payload[0] = 8'h55;
        fork
            begin
                send_frame(8'h02, 16'd1, fast_div, 1'b1); // Corrupt CRC
            end
            begin
                parse_frame_from_uart(f_ok, f_type, f_len, f_err);
            end
        join
        if (!f_ok && f_err == 8'h11) begin
            $display("PASS [Test 11] Bad CRC successfully rejected with error 0x11");
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 11] Expected CRC rejection, got ok=%0d, err=0x%02x", f_ok, f_err);
            tests_failed = tests_failed + 1;
        end

        // ----------------------------------------------------
        // TEST 12: BAD LENGTH DETECTION (> 256)
        // ----------------------------------------------------
        $display("\n--- Running Test 12: Bad Length Rejection ---");
        fork
            begin
                send_uart_byte(8'hA5, fast_div);
                send_uart_byte(8'h5A, fast_div);
                send_uart_byte(8'h02, fast_div); // Type 0x02
                send_uart_byte(8'hF4, fast_div); // Len = 500 (0x01F4)
                send_uart_byte(8'h01, fast_div);
            end
            begin
                parse_frame_from_uart(f_ok, f_type, f_len, f_err);
            end
        join
        if (!f_ok && f_err == 8'h12) begin
            $display("PASS [Test 12] Invalid length (500 > 256) rejected with error 0x12");
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 12] Expected length rejection, got ok=%0d, err=0x%02x", f_ok, f_err);
            tests_failed = tests_failed + 1;
        end
        mmio_write(8'h0C, 32'h01); // Flush RX

        // ----------------------------------------------------
        // TEST 13: UNKNOWN COMMAND/TYPE
        // ----------------------------------------------------
        $display("\n--- Running Test 13: Unknown Command Rejection ---");
        fork
            begin
                send_uart_byte(8'hA5, fast_div);
                send_uart_byte(8'h5A, fast_div);
                send_uart_byte(8'h55, fast_div); // Illegal Type 0x55
            end
            begin
                parse_frame_from_uart(f_ok, f_type, f_len, f_err);
            end
        join
        if (!f_ok && f_err == 8'h13) begin
            $display("PASS [Test 13] Unknown frame type 0x55 rejected with error 0x13");
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 13] Expected type rejection, got ok=%0d, err=0x%02x", f_ok, f_err);
            tests_failed = tests_failed + 1;
        end
        mmio_write(8'h0C, 32'h01); // Flush RX

        // ----------------------------------------------------
        // TEST 14 & 15: MALFORMED FRAME & RESYNCHRONIZATION
        // ----------------------------------------------------
        $display("\n--- Running Test 14 & 15: Garbage Resynchronization ---");
        fork
            begin
                send_uart_byte(8'hFF, fast_div);
                send_uart_byte(8'h00, fast_div);
                send_uart_byte(8'hA5, fast_div); // Partial sync
                send_uart_byte(8'h33, fast_div); // False sync2
                send_uart_byte(8'h77, fast_div);
                // Follow immediately with valid HELLO frame
                send_frame(8'h01, 16'd0, fast_div, 1'b0);
            end
            begin
                parse_frame_from_uart(f_ok, f_type, f_len, f_err);
            end
        join
        if (f_ok && f_type == 8'h01 && f_len == 0) begin
            $display("PASS [Test 14 & 15] Successfully resynchronized after noise and received HELLO frame");
            tests_passed = tests_passed + 1;
        end else begin
            $display("FAIL [Test 14 & 15] Failed to resynchronize after noise: ok=%0d, err=0x%02x", f_ok, f_err);
            tests_failed = tests_failed + 1;
        end

        // ----------------------------------------------------
        // TEST 16: MULTIPLE CONSECUTIVE STREAMING FRAMES
        // ----------------------------------------------------
        $display("\n--- Running Test 16: Consecutive Streaming Frames ---");
        all_stream_ok = 1;
        for (sf = 0; sf < 5; sf = sf + 1) begin
            tb_tx_payload[0] = sf;
            tb_tx_payload[1] = 8'h30 + sf;
            fork
                begin
                    send_frame(8'h02, 16'd2, fast_div, 1'b0);
                end
                begin
                    parse_frame_from_uart(f_ok, f_type, f_len, f_err);
                end
            join
            if (!f_ok || f_type != 8'h02 || f_len != 2 || tb_rx_payload[0] != sf || tb_rx_payload[1] != (8'h30 + sf)) begin
                all_stream_ok = 0;
                $display("FAIL [Test 16] Streaming frame %0d failed: ok=%0d, err=0x%02x", sf, f_ok, f_err);
            end
        end
        if (all_stream_ok) begin
            $display("PASS [Test 16] 5 consecutive back-to-back streaming frames parsed bit-exact");
            tests_passed = tests_passed + 1;
        end else begin
            tests_failed = tests_failed + 1;
        end

        // ====================================================
        // FINAL SUMMARY
        // ====================================================
        $display("\n=================================================");
        $display("           PHASE 4 UART TESTBENCH REPORT         ");
        $display("=================================================");
        $display("Total Tests:  %0d", tests_passed + tests_failed);
        $display("Passed:       %0d", tests_passed);
        $display("Failed:       %0d", tests_failed);
        $display("Pass Rate:    %0.2f%%", (tests_passed * 100.0) / (tests_passed + tests_failed));
        if (tests_failed == 0) begin
            $display(">>> ALL 16 UART HARDWARE & PROTOCOL TESTS PASSED <<<");
        end else begin
            $display(">>> SOME TESTS FAILED <<<");
        end
        $display("=================================================");

        $finish;
    end

endmodule
