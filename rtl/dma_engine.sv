// ============================================================
//  dma_engine.sv  —  Phase 3
//
//  Specialized Tile DMA Engine for 8×8 WS Systolic Accelerator.
//  Modes:
//    • ACT_LOAD     (DMEM → Activation Buffer, 64 bytes)
//    • WEIGHT_LOAD  (DMEM → Weight Buffer,     64 bytes)
//    • RESULT_STORE (Output Buffer → DMEM,     256 bytes)
//
//  Authoritative v4.0 Register Map at 0x4000_0200:
//    0x00 DMA_CONTROL   [0]=START, [1]=CLR_DONE, [2]=CLR_ERR, [5:4]=MODE
//    0x04 DMA_STATUS    [0]=BUSY, [1]=DONE, [2]=ERROR, [3]=TIMEOUT, [4]=REJECTED,
//                       [15:8]=PROGRESS, [23:16]=ERROR_CODE
//    0x08 DMA_SRC_ADDR  32-bit source address
//    0x0C DMA_DST_ADDR  32-bit destination address
//    0x10 DMA_LENGTH    Transfer length in bytes (64 or 256)
//    0x14 DMA_OWNER     [0]: 0=CPU, 1=DMA
//    0x18 DMA_TIMEOUT   Cycle timeout (default: 1,000,000)
//    0x1C DMA_ERROR_CODE 8-bit latched error code
// ============================================================

module dma_engine (
    input  logic        clk,
    input  logic        rst_n,

    // ---- CPU MMIO Slave Interface (Native Bus) ----------------
    input  logic        mmio_valid,
    output logic        mmio_ready,
    input  logic [3:0]  mmio_wstrb,
    input  logic [7:0]  mmio_addr,
    input  logic [31:0] mmio_wdata,
    output logic [31:0] mmio_rdata,

    // ---- Dedicated Data Memory Master Interface (to DMEM Port B) -
    output logic        mem_valid,
    output logic [3:0]  mem_wstrb,
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    input  logic [31:0] mem_rdata,
    input  logic        mem_ready,

    // ---- Dedicated Accelerator Master Interface ---------------
    output logic        dma_owner,

    // Write Port (ACT_LOAD / WEIGHT_LOAD)
    output logic        acc_wr_en,
    output logic        acc_matrix_sel,
    output logic [2:0]  acc_wr_row,
    output logic [2:0]  acc_wr_col,
    output logic [7:0]  acc_wr_data,

    // Read Port (RESULT_STORE)
    output logic        acc_rd_en,
    output logic [5:0]  acc_rd_addr,
    input  logic [31:0] acc_rd_data,
    input  logic        acc_rd_valid,

    // Status Flags
    output logic        busy,
    output logic        done,
    output logic        error
);

    // ========================================================
    // ERROR CODES (v4.0 normative)
    // ========================================================
    localparam logic [7:0] ERR_NONE                    = 8'h00;
    localparam logic [7:0] ERR_TIMEOUT                 = 8'h10;
    localparam logic [7:0] ERR_ILLEGAL_SOURCE_ADDRESS  = 8'h11;
    localparam logic [7:0] ERR_ILLEGAL_DEST_ADDRESS    = 8'h12;
    localparam logic [7:0] ERR_ILLEGAL_LENGTH_OR_MODE  = 8'h13;
    localparam logic [7:0] ERR_OWNERSHIP_VIOLATION     = 8'h14;
    localparam logic [7:0] ERR_MEMORY_OR_BUS_ERROR     = 8'h15;

    // Modes
    localparam logic [1:0] MODE_ACT_LOAD     = 2'b00;
    localparam logic [1:0] MODE_WEIGHT_LOAD  = 2'b01;
    localparam logic [1:0] MODE_RESULT_STORE = 2'b10;

    // ========================================================
    // REGISTERS
    // ========================================================
    logic [1:0]  mode;
    logic        reg_busy;
    logic        reg_done;
    logic        reg_error;
    logic        reg_timeout;
    logic        reg_rejected;
    logic [7:0]  reg_error_code;
    logic [8:0]  bytes_transferred; // 0..256

    logic [31:0] src_addr;
    logic [31:0] dst_addr;
    logic [31:0] length;
    logic        owner;
    logic [31:0] timeout_val;
    logic [31:0] timeout_timer;

    assign busy      = reg_busy;
    assign done      = reg_done;
    assign error     = reg_error;
    assign dma_owner = owner;

    // ========================================================
    // STATE MACHINE DEFINITION
    // ========================================================
    typedef enum logic [2:0] {
        ST_IDLE             = 3'b000,
        ST_LOAD_REQ         = 3'b001,
        ST_LOAD_WAIT        = 3'b010,
        ST_LOAD_WRITE_BYTE  = 3'b011,
        ST_DRAIN_REQ        = 3'b100,
        ST_DRAIN_WAIT       = 3'b101,
        ST_DRAIN_WRITE_MEM  = 3'b110
    } state_t;

    state_t state;

    // Transfer tracking
    logic [31:0] cur_mem_addr;
    logic [6:0]  element_idx;    // 0..63
    logic [1:0]  sub_byte_idx;   // 0..3
    logic [31:0] word_buffer;
    logic [31:0] drain_buffer;
    logic        outstanding_read;

    // MMIO Handshake
    logic mmio_ack;
    assign mmio_ready = mmio_ack;

    // ========================================================
    // COMBINATIONAL VALIDATION LOGIC FOR START COMMAND
    // ========================================================
    logic [1:0] cmd_mode;
    assign cmd_mode = mmio_wdata[5:4];

    logic is_mode_load;
    assign is_mode_load = (cmd_mode == MODE_ACT_LOAD) || (cmd_mode == MODE_WEIGHT_LOAD);

    logic is_mode_store;
    assign is_mode_store = (cmd_mode == MODE_RESULT_STORE);

    logic val_mode_len_ok;
    assign val_mode_len_ok = (is_mode_load && length == 32'd64) || 
                             (is_mode_store && length == 32'd256);

    logic val_src_ok;
    assign val_src_ok = !is_mode_load || 
                        ((src_addr[1:0] == 2'b00) && 
                         (src_addr >= 32'h0000_8000) && 
                         (src_addr <= 32'h0004_0000 - 64));

    logic val_dst_ok;
    assign val_dst_ok = !is_mode_store || 
                        ((dst_addr[1:0] == 2'b00) && 
                         (dst_addr >= 32'h0000_8000) && 
                         (dst_addr <= 32'h0004_0000 - 256));

    // ========================================================
    // UNIFIED CONTROL & STATE MACHINE PROCESS
    // ========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_IDLE;
            mmio_ack          <= 1'b0;
            mmio_rdata        <= 32'h0;
            mode              <= 2'b00;
            src_addr          <= 32'h0;
            dst_addr          <= 32'h0;
            length            <= 32'h0;
            owner             <= 1'b0;
            timeout_val       <= 32'd1000000;
            timeout_timer     <= 32'd0;
            reg_busy          <= 1'b0;
            reg_done          <= 1'b0;
            reg_error         <= 1'b0;
            reg_timeout       <= 1'b0;
            reg_rejected      <= 1'b0;
            reg_error_code    <= ERR_NONE;
            bytes_transferred <= 9'd0;
            cur_mem_addr      <= 32'h0;
            element_idx       <= 7'd0;
            sub_byte_idx      <= 2'd0;
            word_buffer       <= 32'h0;
            drain_buffer      <= 32'h0;
            mem_valid         <= 1'b0;
            mem_wstrb         <= 4'b0000;
            mem_addr          <= 32'h0;
            mem_wdata         <= 32'h0;
            acc_wr_en         <= 1'b0;
            acc_matrix_sel    <= 1'b0;
            acc_wr_row        <= 3'd0;
            acc_wr_col        <= 3'd0;
            acc_wr_data       <= 8'h0;
            acc_rd_en         <= 1'b0;
            acc_rd_addr       <= 6'd0;
            outstanding_read  <= 1'b0;
        end else begin
            mmio_ack  <= 1'b0;
            acc_wr_en <= 1'b0;
            acc_rd_en <= 1'b0;

            // Timeout watchdog (active when transfer is running)
            if (reg_busy) begin
                timeout_timer <= timeout_timer + 1;
                if (timeout_val != 0 && timeout_timer >= timeout_val) begin
                    reg_busy         <= 1'b0;
                    reg_error        <= 1'b1;
                    reg_timeout      <= 1'b1;
                    reg_error_code   <= ERR_TIMEOUT;
                    mem_valid        <= 1'b0;
                    acc_wr_en        <= 1'b0;
                    acc_rd_en        <= 1'b0;
                    outstanding_read <= 1'b0;
                    state            <= ST_IDLE;
                end
            end

            // ----------------------------------------------------
            // MMIO READS / WRITES
            // ----------------------------------------------------
            if (mmio_valid && !mmio_ready) begin
                mmio_ack <= 1'b1;

                if (mmio_wstrb == 4'b0000) begin
                    // Read registers
                    case (mmio_addr)
                        8'h00: mmio_rdata <= {26'h0, mode, 4'h0};
                        8'h04: mmio_rdata <= {8'h0, reg_error_code, bytes_transferred[7:0], 
                                              3'h0, reg_rejected, reg_timeout, reg_error, reg_done, reg_busy};
                        8'h08: mmio_rdata <= src_addr;
                        8'h0C: mmio_rdata <= dst_addr;
                        8'h10: mmio_rdata <= length;
                        8'h14: mmio_rdata <= {31'h0, owner};
                        8'h18: mmio_rdata <= timeout_val;
                        8'h1C: mmio_rdata <= {24'h0, reg_error_code};
                        default: mmio_rdata <= 32'h0;
                    endcase
                end else if (mmio_wstrb == 4'b1111) begin
                    // Full-word write registers
                    case (mmio_addr)
                        8'h00: begin // DMA_CONTROL
                            if (mmio_wdata[1]) reg_done <= 1'b0;
                            if (mmio_wdata[2]) begin
                                reg_error      <= 1'b0;
                                reg_timeout    <= 1'b0;
                                reg_rejected   <= 1'b0;
                                reg_error_code <= ERR_NONE;
                            end
                            mode <= mmio_wdata[5:4];

                            // START command
                            if (mmio_wdata[0]) begin
                                if (reg_busy) begin
                                    reg_error      <= 1'b1;
                                    reg_rejected   <= 1'b1;
                                    reg_error_code <= ERR_OWNERSHIP_VIOLATION;
                                end else if (!owner) begin
                                    reg_error      <= 1'b1;
                                    reg_rejected   <= 1'b1;
                                    reg_error_code <= ERR_OWNERSHIP_VIOLATION;
                                end else if (!val_mode_len_ok) begin
                                    reg_error      <= 1'b1;
                                    reg_rejected   <= 1'b1;
                                    reg_error_code <= ERR_ILLEGAL_LENGTH_OR_MODE;
                                end else if (!val_src_ok) begin
                                    reg_error      <= 1'b1;
                                    reg_rejected   <= 1'b1;
                                    reg_error_code <= ERR_ILLEGAL_SOURCE_ADDRESS;
                                end else if (!val_dst_ok) begin
                                    reg_error      <= 1'b1;
                                    reg_rejected   <= 1'b1;
                                    reg_error_code <= ERR_ILLEGAL_DEST_ADDRESS;
                                end else begin
                                    // Valid start!
                                    reg_busy          <= 1'b1;
                                    reg_done          <= 1'b0;
                                    reg_error         <= 1'b0;
                                    reg_rejected      <= 1'b0;
                                    reg_error_code    <= ERR_NONE;
                                    timeout_timer     <= 32'd0;
                                    element_idx       <= 7'd0;
                                    sub_byte_idx      <= 2'd0;
                                    bytes_transferred <= 9'd0;

                                    if (cmd_mode == MODE_ACT_LOAD || cmd_mode == MODE_WEIGHT_LOAD) begin
                                        cur_mem_addr <= src_addr;
                                        state        <= ST_LOAD_REQ;
                                    end else begin
                                        cur_mem_addr <= dst_addr;
                                        state        <= ST_DRAIN_REQ;
                                    end
                                end
                            end
                        end

                        8'h08: src_addr <= mmio_wdata;
                        8'h0C: dst_addr <= mmio_wdata;
                        8'h10: length   <= mmio_wdata;
                        8'h14: begin // DMA_OWNER
                            if (!reg_busy) owner <= mmio_wdata[0];
                        end
                        8'h18: timeout_val <= mmio_wdata;
                        default: ;
                    endcase
                end
            end

            // ----------------------------------------------------
            // TRANSFER DATA-PATH FSM
            // ----------------------------------------------------
            case (state)
                ST_IDLE: begin
                    // Handled in START command above
                end

                // ACT_LOAD / WEIGHT_LOAD: Issue memory read
                ST_LOAD_REQ: begin
                    mem_valid        <= 1'b1;
                    mem_wstrb        <= 4'b0000;
                    mem_addr         <= cur_mem_addr;
                    outstanding_read <= 1'b1;
                    state            <= ST_LOAD_WAIT;
                end

                ST_LOAD_WAIT: begin
                    if (mem_ready) begin
                        mem_valid        <= 1'b0;
                        outstanding_read <= 1'b0;
                        word_buffer      <= mem_rdata;
                        cur_mem_addr     <= cur_mem_addr + 4;
                        sub_byte_idx     <= 2'd0;
                        state            <= ST_LOAD_WRITE_BYTE;
                    end
                end

                ST_LOAD_WRITE_BYTE: begin
                    acc_wr_en         <= 1'b1;
                    acc_matrix_sel    <= (mode == MODE_WEIGHT_LOAD) ? 1'b1 : 1'b0;
                    acc_wr_row        <= element_idx[5:3];
                    acc_wr_col        <= element_idx[2:0];
                    bytes_transferred <= bytes_transferred + 1;

                    case (sub_byte_idx)
                        2'd0: acc_wr_data <= word_buffer[7:0];
                        2'd1: acc_wr_data <= word_buffer[15:8];
                        2'd2: acc_wr_data <= word_buffer[23:16];
                        2'd3: acc_wr_data <= word_buffer[31:24];
                    endcase

                    element_idx <= element_idx + 1;

                    if (sub_byte_idx == 2'd3) begin
                        if (element_idx == 7'd63) begin
                            reg_busy <= 1'b0;
                            reg_done <= 1'b1;
                            state    <= ST_IDLE;
                        end else begin
                            state <= ST_LOAD_REQ;
                        end
                    end else begin
                        sub_byte_idx <= sub_byte_idx + 1;
                    end
                end

                // RESULT_STORE: Issue read command to accelerator
                ST_DRAIN_REQ: begin
                    acc_rd_en   <= 1'b1;
                    acc_rd_addr <= element_idx[5:0];
                    state       <= ST_DRAIN_WAIT;
                end

                ST_DRAIN_WAIT: begin
                    acc_rd_en <= 1'b0;
                    if (acc_rd_valid) begin
                        drain_buffer <= acc_rd_data;
                        state        <= ST_DRAIN_WRITE_MEM;
                    end
                end

                ST_DRAIN_WRITE_MEM: begin
                    mem_valid <= 1'b1;
                    mem_wstrb <= 4'b1111;
                    mem_addr  <= cur_mem_addr;
                    mem_wdata <= drain_buffer;

                    if (mem_ready) begin
                        mem_valid         <= 1'b0;
                        cur_mem_addr      <= cur_mem_addr + 4;
                        bytes_transferred <= bytes_transferred + 4;
                        element_idx       <= element_idx + 1;

                        if (element_idx == 7'd63) begin
                            reg_busy <= 1'b0;
                            reg_done <= 1'b1;
                            state    <= ST_IDLE;
                        end else begin
                            state <= ST_DRAIN_REQ;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // ========================================================
    // ASSERTIONS
    // ========================================================
    // synthesis translate_off
    always @(posedge clk) begin
        if (rst_n) begin
            if (state == ST_LOAD_REQ && outstanding_read) begin
                $display("[DMA ASSERTION A1 FAILED] More than one DMA memory read requested at time %0t", $time);
            end
            if (mem_valid && !mem_wstrb[0] && (mem_wstrb != 4'b0000)) begin
                $display("[DMA ASSERTION A2 FAILED] DMA read with non-zero wstrb: %b", mem_wstrb);
            end
            if (mem_valid && (mem_wstrb != 4'b0000) && (mem_wstrb != 4'b1111)) begin
                $display("[DMA ASSERTION A3 FAILED] DMA partial write attempted: %b", mem_wstrb);
            end
            if (reg_busy && !owner) begin
                $display("[DMA ASSERTION A6 FAILED] DMA running without ownership!");
            end
        end
    end
    // synthesis translate_on

endmodule
