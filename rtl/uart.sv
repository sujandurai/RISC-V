// ============================================================
//  uart.sv  —  Phase 4 PL UART Peripheral
//
//  Authoritative v4.0 Specification:
//    - 100 MHz system clock domain
//    - 115200 baud nominal (divisor 53 = 0x35)
//    - 8N1 format (8 data, no parity, 1 stop)
//    - 16-byte RX FIFO, 16-byte TX FIFO
//    - 2-flip-flop synchronizer on asynchronous uart_rx input
//    - 16x oversampling baud divider (synchronous counter, no generated clock)
//    - Native bus MMIO slave interface at base 0x4000_0300:
//        0x00 UART_DATA     [7:0] TX write / RX read
//        0x04 UART_STATUS   [0]=RX_VALID, [1]=TX_READY, [2]=RX_OVERRUN
//        0x08 UART_DIVISOR  Baud divider (default: 53)
//        0x0C UART_CONTROL  [0]=RX_FLUSH, [1]=TX_FLUSH
// ============================================================

`timescale 1ns/1ps

module uart (
    input  logic        clk,
    input  logic        rst_n,

    // External physical UART pins
    input  logic        uart_rx,
    output logic        uart_tx,

    // CPU Native Bus MMIO Slave Interface
    input  logic        mmio_valid,
    output logic        mmio_ready,
    input  logic [3:0]  mmio_wstrb,
    input  logic [7:0]  mmio_addr,
    input  logic [31:0] mmio_wdata,
    output logic [31:0] mmio_rdata
);

    // ========================================================
    // 1. RX 2-FLIP-FLOP SYNCHRONIZER (CDC Protection)
    // ========================================================
    (* ASYNC_REG = "TRUE" *) logic rx_sync1;
    (* ASYNC_REG = "TRUE" *) logic rx_sync2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= uart_rx;
            rx_sync2 <= rx_sync1;
        end
    end

    // ========================================================
    // 2. BAUD RATE GENERATOR (16× Oversampling Tick)
    // ========================================================
    logic [15:0] divisor;
    logic [15:0] div_cnt;
    logic        baud_tick_16x;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt       <= 16'd0;
            baud_tick_16x <= 1'b0;
        end else begin
            if (div_cnt >= divisor) begin
                div_cnt       <= 16'd0;
                baud_tick_16x <= 1'b1;
            end else begin
                div_cnt       <= div_cnt + 1'b1;
                baud_tick_16x <= 1'b0;
            end
        end
    end

    // ========================================================
    // 3. FIFO DEFINITIONS (16 Bytes each)
    // ========================================================
    localparam int FIFO_DEPTH = 16;

    // RX FIFO
    logic [7:0] rx_mem [0:FIFO_DEPTH-1];
    logic [3:0] rx_wptr, rx_rptr;
    logic [4:0] rx_count;
    logic       rx_fifo_full, rx_fifo_empty;
    logic       rx_push, rx_pop;
    logic [7:0] rx_push_data, rx_pop_data;
    logic       rx_overrun;

    assign rx_fifo_full  = (rx_count == 5'd16);
    assign rx_fifo_empty = (rx_count == 5'd0);
    assign rx_pop_data   = rx_mem[rx_rptr];

    // TX FIFO
    logic [7:0] tx_mem [0:FIFO_DEPTH-1];
    logic [3:0] tx_wptr, tx_rptr;
    logic [4:0] tx_count;
    logic       tx_fifo_full, tx_fifo_empty;
    logic       tx_push, tx_pop;
    logic [7:0] tx_push_data, tx_pop_data;

    assign tx_fifo_full  = (tx_count == 5'd16);
    assign tx_fifo_empty = (tx_count == 5'd0);
    assign tx_pop_data   = tx_mem[tx_rptr];

    // FIFO Flush controls from MMIO
    logic rx_flush_cmd, tx_flush_cmd;

    // RX FIFO process
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_wptr    <= 4'd0;
            rx_rptr    <= 4'd0;
            rx_count   <= 5'd0;
            rx_overrun <= 1'b0;
        end else if (rx_flush_cmd) begin
            rx_wptr    <= 4'd0;
            rx_rptr    <= 4'd0;
            rx_count   <= 5'd0;
            rx_overrun <= 1'b0;
        end else begin
            case ({rx_push && !rx_fifo_full, rx_pop && !rx_fifo_empty})
                2'b10: begin
                    rx_mem[rx_wptr] <= rx_push_data;
                    rx_wptr         <= rx_wptr + 1'b1;
                    rx_count        <= rx_count + 1'b1;
                end
                2'b01: begin
                    rx_rptr  <= rx_rptr + 1'b1;
                    rx_count <= rx_count - 1'b1;
                end
                2'b11: begin
                    rx_mem[rx_wptr] <= rx_push_data;
                    rx_wptr         <= rx_wptr + 1'b1;
                    rx_rptr         <= rx_rptr + 1'b1;
                end
                default: ;
            endcase

            // Sticky overrun flag: if push arrives while FIFO is already full
            if (rx_push && rx_fifo_full) begin
                rx_overrun <= 1'b1;
            end
        end
    end

    // TX FIFO process
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_wptr  <= 4'd0;
            tx_rptr  <= 4'd0;
            tx_count <= 5'd0;
        end else if (tx_flush_cmd) begin
            tx_wptr  <= 4'd0;
            tx_rptr  <= 4'd0;
            tx_count <= 5'd0;
        end else begin
            case ({tx_push && !tx_fifo_full, tx_pop && !tx_fifo_empty})
                2'b10: begin
                    tx_mem[tx_wptr] <= tx_push_data;
                    tx_wptr         <= tx_wptr + 1'b1;
                    tx_count        <= tx_count + 1'b1;
                end
                2'b01: begin
                    tx_rptr  <= tx_rptr + 1'b1;
                    tx_count <= tx_count - 1'b1;
                end
                2'b11: begin
                    tx_mem[tx_wptr] <= tx_push_data;
                    tx_wptr         <= tx_wptr + 1'b1;
                    tx_rptr         <= tx_rptr + 1'b1;
                end
                default: ;
            endcase
        end
    end

    // ========================================================
    // 4. UART RECEIVER FSM (16x oversampling)
    // ========================================================
    typedef enum logic [1:0] {
        RX_STATE_IDLE  = 2'b00,
        RX_STATE_START = 2'b01,
        RX_STATE_DATA  = 2'b10,
        RX_STATE_STOP  = 2'b11
    } rx_state_t;

    rx_state_t rx_state;
    logic [3:0] rx_tick_cnt;
    logic [2:0] rx_bit_idx;
    logic [7:0] rx_shift_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state        <= RX_STATE_IDLE;
            rx_tick_cnt     <= 4'd0;
            rx_bit_idx      <= 3'd0;
            rx_shift_reg    <= 8'h00;
            rx_push         <= 1'b0;
            rx_push_data    <= 8'h00;
        end else begin
            rx_push <= 1'b0;

            case (rx_state)
                RX_STATE_IDLE: begin
                    rx_tick_cnt <= 4'd0;
                    rx_bit_idx  <= 3'd0;
                    if (rx_sync2 == 1'b0) begin
                        // Falling edge: start bit detection
                        rx_state <= RX_STATE_START;
                    end
                end

                RX_STATE_START: begin
                    if (baud_tick_16x) begin
                        if (rx_tick_cnt == 4'd7) begin
                            // Sample center of start bit
                            if (rx_sync2 == 1'b0) begin
                                rx_tick_cnt <= 4'd0;
                                rx_state    <= RX_STATE_DATA;
                            end else begin
                                // False start bit: return to IDLE
                                rx_state <= RX_STATE_IDLE;
                            end
                        end else begin
                            rx_tick_cnt <= rx_tick_cnt + 1'b1;
                        end
                    end
                end

                RX_STATE_DATA: begin
                    if (baud_tick_16x) begin
                        if (rx_tick_cnt == 4'd15) begin
                            rx_tick_cnt <= 4'd0;
                            rx_shift_reg[rx_bit_idx] <= rx_sync2;
                            if (rx_bit_idx == 3'd7) begin
                                rx_state <= RX_STATE_STOP;
                            end else begin
                                rx_bit_idx <= rx_bit_idx + 1'b1;
                            end
                        end else begin
                            rx_tick_cnt <= rx_tick_cnt + 1'b1;
                        end
                    end
                end

                RX_STATE_STOP: begin
                    if (baud_tick_16x) begin
                        if (rx_tick_cnt == 4'd15) begin
                            rx_tick_cnt <= 4'd0;
                            // Check valid stop bit (high)
                            if (rx_sync2 == 1'b1) begin
                                rx_push      <= 1'b1;
                                rx_push_data <= rx_shift_reg;
                            end
                            rx_state <= RX_STATE_IDLE;
                        end else begin
                            rx_tick_cnt <= rx_tick_cnt + 1'b1;
                        end
                    end
                end

                default: rx_state <= RX_STATE_IDLE;
            endcase
        end
    end

    // ========================================================
    // 5. UART TRANSMITTER FSM (16x oversampling)
    // ========================================================
    typedef enum logic [1:0] {
        TX_STATE_IDLE  = 2'b00,
        TX_STATE_START = 2'b01,
        TX_STATE_DATA  = 2'b10,
        TX_STATE_STOP  = 2'b11
    } tx_state_t;

    tx_state_t tx_state;
    logic [3:0] tx_tick_cnt;
    logic [2:0] tx_bit_idx;
    logic [7:0] tx_shift_reg;
    logic       tx_out_bit;

    assign uart_tx = tx_out_bit;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state     <= TX_STATE_IDLE;
            tx_tick_cnt  <= 4'd0;
            tx_bit_idx   <= 3'd0;
            tx_shift_reg <= 8'h00;
            tx_pop       <= 1'b0;
            tx_out_bit   <= 1'b1; // Idle line is HIGH
        end else begin
            tx_pop <= 1'b0;

            case (tx_state)
                TX_STATE_IDLE: begin
                    tx_out_bit  <= 1'b1;
                    tx_tick_cnt <= 4'd0;
                    tx_bit_idx  <= 3'd0;
                    if (!tx_fifo_empty) begin
                        tx_shift_reg <= tx_pop_data;
                        tx_pop       <= 1'b1;
                        tx_state     <= TX_STATE_START;
                    end
                end

                TX_STATE_START: begin
                    tx_out_bit <= 1'b0; // Start bit is LOW
                    if (baud_tick_16x) begin
                        if (tx_tick_cnt == 4'd15) begin
                            tx_tick_cnt <= 4'd0;
                            tx_state    <= TX_STATE_DATA;
                        end else begin
                            tx_tick_cnt <= tx_tick_cnt + 1'b1;
                        end
                    end
                end

                TX_STATE_DATA: begin
                    tx_out_bit <= tx_shift_reg[tx_bit_idx];
                    if (baud_tick_16x) begin
                        if (tx_tick_cnt == 4'd15) begin
                            tx_tick_cnt <= 4'd0;
                            if (tx_bit_idx == 3'd7) begin
                                tx_state <= TX_STATE_STOP;
                            end else begin
                                tx_bit_idx <= tx_bit_idx + 1'b1;
                            end
                        end else begin
                            tx_tick_cnt <= tx_tick_cnt + 1'b1;
                        end
                    end
                end

                TX_STATE_STOP: begin
                    tx_out_bit <= 1'b1; // Stop bit is HIGH
                    if (baud_tick_16x) begin
                        if (tx_tick_cnt == 4'd15) begin
                            tx_tick_cnt <= 4'd0;
                            tx_state    <= TX_STATE_IDLE;
                        end else begin
                            tx_tick_cnt <= tx_tick_cnt + 1'b1;
                        end
                    end
                end

                default: tx_state <= TX_STATE_IDLE;
            endcase
        end
    end

    // ========================================================
    // 6. NATIVE MMIO SLAVE INTERFACE (Base 0x4000_0300)
    // ========================================================
    logic mmio_ack;
    assign mmio_ready = mmio_ack;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mmio_ack     <= 1'b0;
            mmio_rdata   <= 32'h0;
            divisor      <= 16'd0;
            rx_pop       <= 1'b0;
            tx_push      <= 1'b0;
            tx_push_data <= 8'h00;
            rx_flush_cmd <= 1'b0;
            tx_flush_cmd <= 1'b0;
        end else begin
            mmio_ack     <= 1'b0;
            rx_pop       <= 1'b0;
            tx_push      <= 1'b0;
            rx_flush_cmd <= 1'b0;
            tx_flush_cmd <= 1'b0;

            if (mmio_valid && !mmio_ready) begin
                mmio_ack <= 1'b1;

                if (mmio_wstrb == 4'b0000) begin
                    // ---- MMIO READS ----
                    case (mmio_addr)
                        8'h00: begin // UART_DATA
                            if (!rx_fifo_empty) begin
                                mmio_rdata <= {24'h0, rx_pop_data};
                                rx_pop     <= 1'b1;
                            end else begin
                                mmio_rdata <= 32'h0;
                            end
                        end

                        8'h04: begin // UART_STATUS
                            // bit0: RX_VALID, bit1: TX_READY, bit2: RX_OVERRUN
                            mmio_rdata <= {29'h0, rx_overrun, !tx_fifo_full, !rx_fifo_empty};
                        end

                        8'h08: begin // UART_DIVISOR
                            mmio_rdata <= {16'h0, divisor};
                        end

                        8'h0C: begin // UART_CONTROL
                            mmio_rdata <= 32'h0;
                        end

                        default: mmio_rdata <= 32'h0;
                    endcase
                end else if (mmio_wstrb == 4'b1111) begin
                    // ---- MMIO FULL-WORD WRITES ----
                    case (mmio_addr)
                        8'h00: begin // UART_DATA
                            if (!tx_fifo_full) begin
                                tx_push      <= 1'b1;
                                tx_push_data <= mmio_wdata[7:0];
                            end
                        end

                        8'h08: begin // UART_DIVISOR
                            divisor <= mmio_wdata[15:0];
                        end

                        8'h0C: begin // UART_CONTROL
                            if (mmio_wdata[0]) rx_flush_cmd <= 1'b1;
                            if (mmio_wdata[1]) tx_flush_cmd <= 1'b1;
                        end

                        default: ;
                    endcase
                end
            end
        end
    end

endmodule
