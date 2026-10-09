// ============================================================
//  acc_wrapper.sv  —  Phase 2 / Phase 3
//
//  Wraps the fixed 8×8 WS accelerator IP.
//  Exposes:
//    • CPU MMIO interface  (PicoRV32 native bus)
//    • DMA native interface (direct element read/write)
//    • dma_owner mux between CPU and DMA paths
// ============================================================
module acc_wrapper (
    input  logic        clk,
    input  logic        rst_n,

    // ---- CPU MMIO interface -----------------------------------
    input  logic        cpu_valid,
    output logic        cpu_ready,
    input  logic [3:0]  cpu_wstrb,
    input  logic [7:0]  cpu_addr,
    input  logic [31:0] cpu_wdata,
    output logic [31:0] cpu_rdata,

    // ---- DMA ownership ----------------------------------------
    input  logic        dma_owner,   // 0 = CPU owns, 1 = DMA owns

    // ---- DMA native write interface ---------------------------
    input  logic        dma_wr_en,
    input  logic        dma_matrix_sel,
    input  logic [2:0]  dma_wr_row,
    input  logic [2:0]  dma_wr_col,
    input  logic [7:0]  dma_wr_data,

    // ---- DMA native read interface ----------------------------
    input  logic        dma_rd_en,
    input  logic [5:0]  dma_rd_addr,
    output logic [31:0] dma_rd_data,
    output logic        dma_rd_valid
);

    // ========================================================
    // WRAPPER REGISTERS
    // ========================================================
    logic        acc_matrix_select;
    logic [2:0]  acc_row;
    logic [2:0]  acc_col;
    logic [5:0]  acc_read_address;
    logic [31:0] acc_cycles;
    logic [7:0]  error_code;

    logic        done_latched;
    logic        error_flag;
    logic        result_valid;

    // Local Reset
    logic [2:0] local_reset_counter;
    (* max_fanout = 100 *) logic acc_local_rst_n;

    // Fixed IP status
    logic        fixed_busy;
    logic        fixed_done;
    logic [31:0] fixed_rd_data;      // latched for CPU reads
    logic        fixed_rd_valid_wire;
    logic [31:0] fixed_rd_data_wire;

    // Fixed IP control (CPU path)
    logic        fixed_start;
    logic        fixed_wr_en;        // CPU→IP write strobe
    logic        fixed_rd_en_cpu;    // CPU→IP read enable

    // ========================================================
    // WRAPPER STATE MACHINE
    // ========================================================
    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        RUN    = 2'b01,
        OUTPUT = 2'b10,
        FAULT  = 2'b11
    } state_t;

    state_t state, next_state;

    // Error codes
    localparam ERR_NONE               = 8'h00;
    localparam ERR_ILLEGAL_START      = 8'h01;
    localparam ERR_START_WHILE_BUSY   = 8'h02;
    localparam ERR_WRITE_WHILE_BUSY   = 8'h03;
    localparam ERR_PARTIAL_WRITE      = 8'h04;
    localparam ERR_OWNERSHIP_VIOL     = 8'h05;
    localparam ERR_ILLEGAL_READ       = 8'h06;
    localparam ERR_READ_WHILE_RUNNING = 8'h07;
    localparam ERR_LOCAL_RESET_ACTIVE = 8'h08;

    logic       set_error;
    logic [7:0] next_error_code;

    // ---- Registered state block --------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= IDLE;
            acc_cycles         <= 0;
            done_latched       <= 0;
            error_flag         <= 0;
            error_code         <= ERR_NONE;
            result_valid       <= 0;
            local_reset_counter<= 0;
            acc_local_rst_n    <= 1'b1;
        end else begin
            // Local reset sequence
            if (local_reset_counter > 0) begin
                local_reset_counter <= local_reset_counter - 1;
                acc_local_rst_n     <= 1'b0;
                if (local_reset_counter == 1) begin
                    state        <= IDLE;
                    done_latched <= 0;
                    result_valid <= 0;
                end
            end else begin
                acc_local_rst_n <= 1'b1;
                state           <= next_state;
            end

            // Cycle counter
            if (state == RUN)       acc_cycles <= acc_cycles + 1;
            else if (fixed_start)   acc_cycles <= 0;

            // DONE latch
            if (fixed_done) begin
                done_latched <= 1'b1;
                result_valid <= 1'b1;
            end

            if (do_clear_done) begin
                done_latched <= 1'b0;
                result_valid <= 1'b0;
            end

            if (do_local_reset) begin
                local_reset_counter <= 3'd5;
                error_flag          <= 0;
                error_code          <= ERR_NONE;
            end

            if (do_clear_error) begin
                error_flag <= 0;
                error_code <= ERR_NONE;
            end else if (set_error && !error_flag) begin
                error_flag <= 1'b1;
                error_code <= next_error_code;
            end
        end
    end

    // Next-state logic
    always_comb begin
        next_state = state;
        if (state == IDLE) begin
            if (fixed_start) next_state = RUN;
            else if (set_error) next_state = FAULT;
        end else if (state == RUN) begin
            if (fixed_done) next_state = OUTPUT;
        end else if (state == OUTPUT) begin
            if (fixed_start)  next_state = RUN;
            else if (set_error) next_state = FAULT;
            else if (!done_latched && !result_valid) next_state = IDLE;
        end else if (state == FAULT) begin
            if (do_clear_error) next_state = IDLE;
        end
    end

    // ========================================================
    // MMIO ACCESS LOGIC
    // ========================================================
    logic op_pending;
    logic do_clear_done;
    logic do_local_reset;
    logic do_clear_error;
    logic do_read_cmd;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_pending        <= 0;
            cpu_rdata         <= 0;
            acc_matrix_select <= 0;
            acc_row           <= 0;
            acc_col           <= 0;
            acc_read_address  <= 0;
            fixed_start       <= 0;
            fixed_wr_en       <= 0;
            do_clear_done     <= 0;
            do_local_reset    <= 0;
            do_clear_error    <= 0;
            do_read_cmd       <= 0;
            set_error         <= 0;
            next_error_code   <= ERR_NONE;
        end else begin
            // Pulse defaults
            fixed_start     <= 0;
            fixed_wr_en     <= 0;
            do_clear_done   <= 0;
            do_local_reset  <= 0;
            do_clear_error  <= 0;
            do_read_cmd     <= 0;
            set_error       <= 0;

            if (cpu_valid && !cpu_ready) begin
                op_pending <= 1'b1;

                // ---- READS ----
                if (cpu_wstrb == 4'b0000) begin
                    case (cpu_addr)
                        8'h04: cpu_rdata <= {16'h0, error_code, 4'h0,
                                             error_flag, result_valid,
                                             done_latched, fixed_busy};
                        8'h08: cpu_rdata <= {31'h0, acc_matrix_select};
                        8'h0C: cpu_rdata <= {29'h0, acc_row};
                        8'h10: cpu_rdata <= {29'h0, acc_col};
                        8'h18: cpu_rdata <= {26'h0, acc_read_address};
                        8'h20: cpu_rdata <= fixed_rd_data;
                        8'h24: cpu_rdata <= acc_cycles;
                        8'h28: cpu_rdata <= {24'h0, error_code};
                        default: cpu_rdata <= 0;
                    endcase
                end

                // ---- FULL-WORD WRITES ----
                else if (cpu_wstrb == 4'b1111) begin
                    case (cpu_addr)
                        8'h00: begin // ACC_CONTROL
                            if (cpu_wdata[0]) begin // START
                                if (dma_owner) begin
                                    set_error <= 1; next_error_code <= ERR_OWNERSHIP_VIOL;
                                end else if (state != IDLE && state != OUTPUT) begin
                                    set_error <= 1; next_error_code <= ERR_START_WHILE_BUSY;
                                end else if (fixed_busy) begin
                                    set_error <= 1; next_error_code <= ERR_START_WHILE_BUSY;
                                end else if (state == FAULT) begin
                                    set_error <= 1; next_error_code <= ERR_ILLEGAL_START;
                                end else if (local_reset_counter > 0) begin
                                    set_error <= 1; next_error_code <= ERR_LOCAL_RESET_ACTIVE;
                                end else begin
                                    fixed_start <= 1'b1;
                                end
                            end
                            if (cpu_wdata[1]) do_clear_done  <= 1;
                            if (cpu_wdata[2]) do_local_reset <= 1;
                            if (cpu_wdata[3]) do_clear_error <= 1;
                        end
                        8'h08: acc_matrix_select <= cpu_wdata[0];
                        8'h0C: acc_row           <= cpu_wdata[2:0];
                        8'h10: acc_col           <= cpu_wdata[2:0];
                        8'h14: begin // ACC_WRITE_DATA
                            if (dma_owner) begin
                                set_error <= 1; next_error_code <= ERR_OWNERSHIP_VIOL;
                            end else if (state == RUN || fixed_busy) begin
                                set_error <= 1; next_error_code <= ERR_WRITE_WHILE_BUSY;
                            end else if (state == FAULT) begin
                                set_error <= 1; next_error_code <= ERR_ILLEGAL_START;
                            end else begin
                                fixed_wr_en <= 1'b1;
                            end
                        end
                        8'h18: acc_read_address <= cpu_wdata[5:0];
                        8'h1C: begin // ACC_READ_COMMAND
                            if (state == RUN || fixed_busy) begin
                                set_error <= 1; next_error_code <= ERR_READ_WHILE_RUNNING;
                            end else if (!result_valid) begin
                                set_error <= 1; next_error_code <= ERR_ILLEGAL_READ;
                            end else begin
                                do_read_cmd <= 1'b1;
                            end
                        end
                        default: ;
                    endcase
                end

                // ---- PARTIAL WRITES ----
                else begin
                    set_error <= 1; next_error_code <= ERR_PARTIAL_WRITE;
                end

            end else begin
                op_pending <= 0;
            end
        end
    end

    assign cpu_ready = op_pending;

    // CPU read path for fixed IP
    assign fixed_rd_en_cpu = do_read_cmd;

    // Latch fixed IP read result for CPU
    always_ff @(posedge clk) begin
        if (fixed_rd_valid_wire)
            fixed_rd_data <= fixed_rd_data_wire;
    end

    // ========================================================
    // CPU / DMA MUX  →  Fixed IP
    // ========================================================
    logic        eff_wr_en;
    logic        eff_matrix_sel;
    logic [2:0]  eff_wr_row;
    logic [2:0]  eff_wr_col;
    logic [7:0]  eff_wr_data;
    logic        eff_rd_en;
    logic [5:0]  eff_rd_addr;

    assign eff_wr_en      = dma_owner ? dma_wr_en      : fixed_wr_en;
    assign eff_matrix_sel = dma_owner ? dma_matrix_sel  : acc_matrix_select;
    assign eff_wr_row     = dma_owner ? dma_wr_row      : acc_row;
    assign eff_wr_col     = dma_owner ? dma_wr_col      : acc_col;
    assign eff_wr_data    = dma_owner ? dma_wr_data     : cpu_wdata[7:0];
    assign eff_rd_en      = dma_owner ? dma_rd_en       : fixed_rd_en_cpu;
    assign eff_rd_addr    = dma_owner ? dma_rd_addr     : acc_read_address;

    // DMA read result output (raw wires from fixed IP)
    assign dma_rd_data  = fixed_rd_data_wire;
    assign dma_rd_valid = fixed_rd_valid_wire;

    // ========================================================
    // FIXED IP INSTANTIATION
    // ========================================================
    accelerator #(
        .DW(8),
        .AW(32)
    ) fixed_ip (
        .clk          (clk),
        .rst_n        (acc_local_rst_n),
        .start        (fixed_start),
        .busy         (fixed_busy),
        .done         (fixed_done),
        .wr_en        (eff_wr_en),
        .matrix_select(eff_matrix_sel),
        .wr_row       (eff_wr_row),
        .wr_col       (eff_wr_col),
        .wr_data      (eff_wr_data),
        .rd_en        (eff_rd_en),
        .rd_addr      (eff_rd_addr),
        .rd_data      (fixed_rd_data_wire),
        .rd_valid     (fixed_rd_valid_wire)
    );

endmodule
