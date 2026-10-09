`timescale 1ns/1ps

module ws_datapath #(
    parameter DW = 8,
    parameter AW = 32
)(
    input wire clk,
    input wire rst_n,

    // ========================================================
    // ACTIVATION BUFFER LOAD
    // ========================================================

    input wire                 act_wr_en,
    input wire [2:0]           act_wr_row,
    input wire [2:0]           act_wr_col,
    input wire signed [DW-1:0] act_wr_data,

    // ========================================================
    // ACTIVATION BUFFER READ
    //
    // One complete A row is read.
    // ========================================================

    input wire                 act_rd_en,
    input wire [2:0]           act_rd_row,

    // ========================================================
    // WEIGHT BUFFER LOAD
    // ========================================================

    input wire                 weight_wr_en,
    input wire [2:0]           weight_wr_row,
    input wire [2:0]           weight_wr_col,
    input wire signed [DW-1:0] weight_wr_data,

    // ========================================================
    // WEIGHT BUFFER READ
    //
    // Reads B[row][col] for PE loading.
    // ========================================================

    input wire                 weight_rd_en,
    input wire [2:0]           weight_rd_row,
    input wire [2:0]           weight_rd_col,

    // ========================================================
    // WEIGHT LOADING INTO PE ARRAY
    // ========================================================

    input wire                 load_weight,
    input wire [2:0]           load_weight_row,
    input wire [2:0]           load_weight_col,

    // ========================================================
    // COMPUTATION CONTROL
    // ========================================================

    input wire                 clear_psum,
    input wire                 mac_en,

    // ========================================================
    // OUTPUT CAPTURE CONTROL
    // ========================================================

    input wire                 capture_en,
    input wire [3:0]           diag_count,

    // ========================================================
    // FINAL OUTPUT READ
    // ========================================================

    input wire                 output_rd_en,
    input wire [5:0]           output_rd_addr,

    output wire signed [AW-1:0] output_rd_data,
    output wire                 output_data_valid,

    output wire                 matrix_done
);

    // ========================================================
    // ACTIVATION BUFFER
    // ========================================================

    wire signed [DW-1:0] act_buf0;
    wire signed [DW-1:0] act_buf1;
    wire signed [DW-1:0] act_buf2;
    wire signed [DW-1:0] act_buf3;

    wire signed [DW-1:0] act_buf4;
    wire signed [DW-1:0] act_buf5;
    wire signed [DW-1:0] act_buf6;
    wire signed [DW-1:0] act_buf7;

    wire act_buf_valid;


    activation_buffer_ws #(
        .DW(DW)
    ) u_activation_buffer (
        .clk(clk),
        .rst_n(rst_n),

        .wr_en(act_wr_en),
        .wr_row(act_wr_row),
        .wr_col(act_wr_col),
        .wr_data(act_wr_data),

        .rd_en(act_rd_en),
        .rd_row(act_rd_row),

        .act0(act_buf0),
        .act1(act_buf1),
        .act2(act_buf2),
        .act3(act_buf3),

        .act4(act_buf4),
        .act5(act_buf5),
        .act6(act_buf6),
        .act7(act_buf7),

        .data_valid(act_buf_valid)
    );


    // ========================================================
    // WEIGHT BUFFER
    // ========================================================

    wire signed [DW-1:0] weight_buf_data;
    wire weight_buf_valid;


    weight_buffer_ws #(
        .DW(DW)
    ) u_weight_buffer (
        .clk(clk),
        .rst_n(rst_n),

        .wr_en(weight_wr_en),
        .wr_row(weight_wr_row),
        .wr_col(weight_wr_col),
        .wr_data(weight_wr_data),

        .rd_en(weight_rd_en),
        .rd_row(weight_rd_row),
        .rd_col(weight_rd_col),

        .rd_data(weight_buf_data),
        .data_valid(weight_buf_valid)
    );


    // ========================================================
    // INPUT SKEW
    //
    // act_buf0 -> 0-cycle delay
    // act_buf1 -> 1-cycle delay
    // ...
    // act_buf7 -> 7-cycle delay
    // ========================================================

    wire signed [DW-1:0] skew_act0;
    wire signed [DW-1:0] skew_act1;
    wire signed [DW-1:0] skew_act2;
    wire signed [DW-1:0] skew_act3;

    wire signed [DW-1:0] skew_act4;
    wire signed [DW-1:0] skew_act5;
    wire signed [DW-1:0] skew_act6;
    wire signed [DW-1:0] skew_act7;

    wire skew_valid0;
    wire skew_valid1;
    wire skew_valid2;
    wire skew_valid3;

    wire skew_valid4;
    wire skew_valid5;
    wire skew_valid6;
    wire skew_valid7;


    input_skew #(
        .DW(DW)
    ) u_input_skew (
        .clk(clk),
        .rst_n(rst_n),

        .act_in0(act_buf0),
        .act_in1(act_buf1),
        .act_in2(act_buf2),
        .act_in3(act_buf3),

        .act_in4(act_buf4),
        .act_in5(act_buf5),
        .act_in6(act_buf6),
        .act_in7(act_buf7),

        .valid_in0(act_buf_valid),
        .valid_in1(act_buf_valid),
        .valid_in2(act_buf_valid),
        .valid_in3(act_buf_valid),

        .valid_in4(act_buf_valid),
        .valid_in5(act_buf_valid),
        .valid_in6(act_buf_valid),
        .valid_in7(act_buf_valid),

        .act_out0(skew_act0),
        .act_out1(skew_act1),
        .act_out2(skew_act2),
        .act_out3(skew_act3),

        .act_out4(skew_act4),
        .act_out5(skew_act5),
        .act_out6(skew_act6),
        .act_out7(skew_act7),

        .valid_out0(skew_valid0),
        .valid_out1(skew_valid1),
        .valid_out2(skew_valid2),
        .valid_out3(skew_valid3),

        .valid_out4(skew_valid4),
        .valid_out5(skew_valid5),
        .valid_out6(skew_valid6),
        .valid_out7(skew_valid7)
    );


    // ========================================================
    // 8×8 WEIGHT-STATIONARY SYSTOLIC ARRAY
    //
    // The weight buffer provides one weight.
    //
    // The selected PE is determined by:
    //
    // load_weight_row
    // load_weight_col
    //
    // The actual weight value comes from the weight buffer.
    // ========================================================

    wire signed [AW-1:0] psum_out0;
    wire signed [AW-1:0] psum_out1;
    wire signed [AW-1:0] psum_out2;
    wire signed [AW-1:0] psum_out3;

    wire signed [AW-1:0] psum_out4;
    wire signed [AW-1:0] psum_out5;
    wire signed [AW-1:0] psum_out6;
    wire signed [AW-1:0] psum_out7;


    systolic_8x8_ws #(
        .DW(DW),
        .AW(AW)
    ) u_systolic_array (
        .clk(clk),
        .rst_n(rst_n),

        .mac_en(mac_en),
        .clear_psum(clear_psum),

        .load_weight(load_weight),
        .weight_row(load_weight_row),
        .weight_col(load_weight_col),
        .weight_data(weight_buf_data),

        .act_in0(skew_act0),
        .act_in1(skew_act1),
        .act_in2(skew_act2),
        .act_in3(skew_act3),

        .act_in4(skew_act4),
        .act_in5(skew_act5),
        .act_in6(skew_act6),
        .act_in7(skew_act7),

        // Fresh matrix multiplication starts with
        // zero partial sums.
        .psum_in0(0),
        .psum_in1(0),
        .psum_in2(0),
        .psum_in3(0),

        .psum_in4(0),
        .psum_in5(0),
        .psum_in6(0),
        .psum_in7(0),

        .psum_out0(psum_out0),
        .psum_out1(psum_out1),
        .psum_out2(psum_out2),
        .psum_out3(psum_out3),

        .psum_out4(psum_out4),
        .psum_out5(psum_out5),
        .psum_out6(psum_out6),
        .psum_out7(psum_out7)
    );


    // ========================================================
    // OUTPUT BUFFER
    //
    // Captures the diagonal PSUM stream into C[8][8].
    // ========================================================

    output_buffer_ws #(
        .AW(AW)
    ) u_output_buffer (
        .clk(clk),
        .rst_n(rst_n),

        .capture_en(capture_en),
        .diag_count(diag_count),

        .psum_in0(psum_out0),
        .psum_in1(psum_out1),
        .psum_in2(psum_out2),
        .psum_in3(psum_out3),

        .psum_in4(psum_out4),
        .psum_in5(psum_out5),
        .psum_in6(psum_out6),
        .psum_in7(psum_out7),

        .rd_en(output_rd_en),
        .rd_addr(output_rd_addr),

        .rd_data(output_rd_data),
        .data_valid(output_data_valid),

        .matrix_done(matrix_done)
    );

endmodule