`timescale 1ns/1ps

module accelerator #(
    parameter DW = 8,
    parameter AW = 32
)(
    input wire clk,
    input wire rst_n,

    // ========================================================
    // START
    // ========================================================

    input wire start,

    output wire busy,
    output wire done,

    // ========================================================
    // MATRIX LOAD INTERFACE
    //
    // matrix_select:
    //
    // 0 = Activation matrix A
    // 1 = Weight matrix B
    //
    // One element is written per cycle.
    // ========================================================

    input wire                 wr_en,
    input wire                 matrix_select,

    input wire [2:0]           wr_row,
    input wire [2:0]           wr_col,

    input wire signed [DW-1:0] wr_data,

    // ========================================================
    // OUTPUT READ INTERFACE
    //
    // address:
    //
    // 0  = C[0][0]
    // 1  = C[0][1]
    // ...
    // 7  = C[0][7]
    // 8  = C[1][0]
    // ...
    // 63 = C[7][7]
    // ========================================================

    input wire                 rd_en,
    input wire [5:0]           rd_addr,

    output wire signed [AW-1:0] rd_data,
    output wire                 rd_valid
);


    // ========================================================
    // CONTROLLER OUTPUTS
    // ========================================================

    wire       act_rd_en;
    wire [2:0] act_rd_row;

    wire       weight_rd_en;
    wire [2:0] weight_rd_row;
    wire [2:0] weight_rd_col;

    wire       load_weight;
    wire [2:0] load_weight_row;
    wire [2:0] load_weight_col;

    wire clear_psum;
    wire mac_en;

    wire       capture_en;
    wire [3:0] diag_count;


    // ========================================================
    // DATAPATH STATUS
    // ========================================================

    wire matrix_done;


    // ========================================================
    // MATRIX LOAD DECODING
    //
    // matrix_select = 0 → Activation Buffer
    // matrix_select = 1 → Weight Buffer
    // ========================================================

    wire act_wr_en;
    wire weight_wr_en;

    assign act_wr_en =
        wr_en && (matrix_select == 1'b0);

    assign weight_wr_en =
        wr_en && (matrix_select == 1'b1);


    // ========================================================
    // CONTROLLER
    // ========================================================

    controller u_controller (
        .clk(clk),
        .rst_n(rst_n),

        .start(start),

        .busy(busy),
        .done(done),

        // Activation read
        .act_rd_en(act_rd_en),
        .act_rd_row(act_rd_row),

        // Weight buffer read
        .weight_rd_en(weight_rd_en),
        .weight_rd_row(weight_rd_row),
        .weight_rd_col(weight_rd_col),

        // PE weight load
        .load_weight(load_weight),
        .load_weight_row(load_weight_row),
        .load_weight_col(load_weight_col),

        // Compute
        .clear_psum(clear_psum),
        .mac_en(mac_en),

        // Output capture
        .capture_en(capture_en),
        .diag_count(diag_count)
    );


    // ========================================================
    // DATAPATH
    // ========================================================

    ws_datapath #(
        .DW(DW),
        .AW(AW)
    ) u_ws_datapath (
        .clk(clk),
        .rst_n(rst_n),

        // ----------------------------------------------------
        // Activation matrix load
        // ----------------------------------------------------

        .act_wr_en(act_wr_en),
        .act_wr_row(wr_row),
        .act_wr_col(wr_col),
        .act_wr_data(wr_data),

        // ----------------------------------------------------
        // Activation read
        // ----------------------------------------------------

        .act_rd_en(act_rd_en),
        .act_rd_row(act_rd_row),

        // ----------------------------------------------------
        // Weight matrix load
        // ----------------------------------------------------

        .weight_wr_en(weight_wr_en),
        .weight_wr_row(wr_row),
        .weight_wr_col(wr_col),
        .weight_wr_data(wr_data),

        // ----------------------------------------------------
        // Weight read
        // ----------------------------------------------------

        .weight_rd_en(weight_rd_en),
        .weight_rd_row(weight_rd_row),
        .weight_rd_col(weight_rd_col),

        // ----------------------------------------------------
        // PE weight loading
        // ----------------------------------------------------

        .load_weight(load_weight),
        .load_weight_row(load_weight_row),
        .load_weight_col(load_weight_col),

        // ----------------------------------------------------
        // Computation
        // ----------------------------------------------------

        .clear_psum(clear_psum),
        .mac_en(mac_en),

        // ----------------------------------------------------
        // Output capture
        // ----------------------------------------------------

        .capture_en(capture_en),
        .diag_count(diag_count),

        // ----------------------------------------------------
        // Output read
        // ----------------------------------------------------

        .output_rd_en(rd_en),
        .output_rd_addr(rd_addr),

        .output_rd_data(rd_data),
        .output_data_valid(rd_valid),

        .matrix_done(matrix_done)
    );

endmodule