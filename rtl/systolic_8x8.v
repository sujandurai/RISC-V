`timescale 1ns/1ps

module systolic_8x8_ws #(
    parameter DW = 8,
    parameter AW = 32
)(
    input wire clk,
    input wire rst_n,

    // ========================================================
    // CONTROL
    // ========================================================

    input wire mac_en,
    input wire clear_psum,

    // ========================================================
    // WEIGHT LOADING
    //
    // One PE is selected at a time.
    // ========================================================

    input wire                 load_weight,
    input wire [2:0]           weight_row,
    input wire [2:0]           weight_col,
    input wire signed [DW-1:0] weight_data,

    // ========================================================
    // ALREADY-SKEWED ACTIVATION INPUTS
    //
    // These come from input_skew.v
    //
    // act_in0 -> PE row 0
    // act_in1 -> PE row 1
    // ...
    // act_in7 -> PE row 7
    // ========================================================

    input wire signed [DW-1:0] act_in0,
    input wire signed [DW-1:0] act_in1,
    input wire signed [DW-1:0] act_in2,
    input wire signed [DW-1:0] act_in3,
    input wire signed [DW-1:0] act_in4,
    input wire signed [DW-1:0] act_in5,
    input wire signed [DW-1:0] act_in6,
    input wire signed [DW-1:0] act_in7,

    // ========================================================
    // PSUM INPUT
    //
    // Normally all zeros for a fresh 8x8 multiplication.
    // ========================================================

    input wire signed [AW-1:0] psum_in0,
    input wire signed [AW-1:0] psum_in1,
    input wire signed [AW-1:0] psum_in2,
    input wire signed [AW-1:0] psum_in3,
    input wire signed [AW-1:0] psum_in4,
    input wire signed [AW-1:0] psum_in5,
    input wire signed [AW-1:0] psum_in6,
    input wire signed [AW-1:0] psum_in7,

    // ========================================================
    // FINAL OUTPUTS
    //
    // Bottom row of the array.
    // ========================================================

    output wire signed [AW-1:0] psum_out0,
    output wire signed [AW-1:0] psum_out1,
    output wire signed [AW-1:0] psum_out2,
    output wire signed [AW-1:0] psum_out3,
    output wire signed [AW-1:0] psum_out4,
    output wire signed [AW-1:0] psum_out5,
    output wire signed [AW-1:0] psum_out6,
    output wire signed [AW-1:0] psum_out7
);

    // ========================================================
    // ACTIVATION LINKS
    //
    // [row][column]
    //
    // column 0 = array input
    // column 8 = array output
    // ========================================================

    wire signed [DW-1:0] a0 [0:8];
    wire signed [DW-1:0] a1 [0:8];
    wire signed [DW-1:0] a2 [0:8];
    wire signed [DW-1:0] a3 [0:8];

    wire signed [DW-1:0] a4 [0:8];
    wire signed [DW-1:0] a5 [0:8];
    wire signed [DW-1:0] a6 [0:8];
    wire signed [DW-1:0] a7 [0:8];


    // ========================================================
    // PSUM LINKS
    //
    // [column][row]
    //
    // row 0 = array input
    // row 8 = array output
    // ========================================================

    wire signed [AW-1:0] p0 [0:8];
    wire signed [AW-1:0] p1 [0:8];
    wire signed [AW-1:0] p2 [0:8];
    wire signed [AW-1:0] p3 [0:8];

    wire signed [AW-1:0] p4 [0:8];
    wire signed [AW-1:0] p5 [0:8];
    wire signed [AW-1:0] p6 [0:8];
    wire signed [AW-1:0] p7 [0:8];


    // ========================================================
    // ARRAY INPUTS
    // ========================================================

    assign a0[0] = act_in0;
    assign a1[0] = act_in1;
    assign a2[0] = act_in2;
    assign a3[0] = act_in3;

    assign a4[0] = act_in4;
    assign a5[0] = act_in5;
    assign a6[0] = act_in6;
    assign a7[0] = act_in7;


    assign p0[0] = psum_in0;
    assign p1[0] = psum_in1;
    assign p2[0] = psum_in2;
    assign p3[0] = psum_in3;

    assign p4[0] = psum_in4;
    assign p5[0] = psum_in5;
    assign p6[0] = psum_in6;
    assign p7[0] = psum_in7;


    // ========================================================
    // WEIGHT LOAD DECODING
    // ========================================================

    wire load00;
    wire load01;
    wire load02;
    wire load03;
    wire load04;
    wire load05;
    wire load06;
    wire load07;

    wire load10;
    wire load11;
    wire load12;
    wire load13;
    wire load14;
    wire load15;
    wire load16;
    wire load17;

    wire load20;
    wire load21;
    wire load22;
    wire load23;
    wire load24;
    wire load25;
    wire load26;
    wire load27;

    wire load30;
    wire load31;
    wire load32;
    wire load33;
    wire load34;
    wire load35;
    wire load36;
    wire load37;

    wire load40;
    wire load41;
    wire load42;
    wire load43;
    wire load44;
    wire load45;
    wire load46;
    wire load47;

    wire load50;
    wire load51;
    wire load52;
    wire load53;
    wire load54;
    wire load55;
    wire load56;
    wire load57;

    wire load60;
    wire load61;
    wire load62;
    wire load63;
    wire load64;
    wire load65;
    wire load66;
    wire load67;

    wire load70;
    wire load71;
    wire load72;
    wire load73;
    wire load74;
    wire load75;
    wire load76;
    wire load77;


    assign load00 = load_weight &&
                    (weight_row == 3'd0) &&
                    (weight_col == 3'd0);

    assign load01 = load_weight &&
                    (weight_row == 3'd0) &&
                    (weight_col == 3'd1);

    assign load02 = load_weight &&
                    (weight_row == 3'd0) &&
                    (weight_col == 3'd2);

    assign load03 = load_weight &&
                    (weight_row == 3'd0) &&
                    (weight_col == 3'd3);

    assign load04 = load_weight &&
                    (weight_row == 3'd0) &&
                    (weight_col == 3'd4);

    assign load05 = load_weight &&
                    (weight_row == 3'd0) &&
                    (weight_col == 3'd5);

    assign load06 = load_weight &&
                    (weight_row == 3'd0) &&
                    (weight_col == 3'd6);

    assign load07 = load_weight &&
                    (weight_row == 3'd0) &&
                    (weight_col == 3'd7);


    assign load10 = load_weight &&
                    (weight_row == 3'd1) &&
                    (weight_col == 3'd0);

    assign load11 = load_weight &&
                    (weight_row == 3'd1) &&
                    (weight_col == 3'd1);

    assign load12 = load_weight &&
                    (weight_row == 3'd1) &&
                    (weight_col == 3'd2);

    assign load13 = load_weight &&
                    (weight_row == 3'd1) &&
                    (weight_col == 3'd3);

    assign load14 = load_weight &&
                    (weight_row == 3'd1) &&
                    (weight_col == 3'd4);

    assign load15 = load_weight &&
                    (weight_row == 3'd1) &&
                    (weight_col == 3'd5);

    assign load16 = load_weight &&
                    (weight_row == 3'd1) &&
                    (weight_col == 3'd6);

    assign load17 = load_weight &&
                    (weight_row == 3'd1) &&
                    (weight_col == 3'd7);


    assign load20 = load_weight &&
                    (weight_row == 3'd2) &&
                    (weight_col == 3'd0);

    assign load21 = load_weight &&
                    (weight_row == 3'd2) &&
                    (weight_col == 3'd1);

    assign load22 = load_weight &&
                    (weight_row == 3'd2) &&
                    (weight_col == 3'd2);

    assign load23 = load_weight &&
                    (weight_row == 3'd2) &&
                    (weight_col == 3'd3);

    assign load24 = load_weight &&
                    (weight_row == 3'd2) &&
                    (weight_col == 3'd4);

    assign load25 = load_weight &&
                    (weight_row == 3'd2) &&
                    (weight_col == 3'd5);

    assign load26 = load_weight &&
                    (weight_row == 3'd2) &&
                    (weight_col == 3'd6);

    assign load27 = load_weight &&
                    (weight_row == 3'd2) &&
                    (weight_col == 3'd7);


    assign load30 = load_weight &&
                    (weight_row == 3'd3) &&
                    (weight_col == 3'd0);

    assign load31 = load_weight &&
                    (weight_row == 3'd3) &&
                    (weight_col == 3'd1);

    assign load32 = load_weight &&
                    (weight_row == 3'd3) &&
                    (weight_col == 3'd2);

    assign load33 = load_weight &&
                    (weight_row == 3'd3) &&
                    (weight_col == 3'd3);

    assign load34 = load_weight &&
                    (weight_row == 3'd3) &&
                    (weight_col == 3'd4);

    assign load35 = load_weight &&
                    (weight_row == 3'd3) &&
                    (weight_col == 3'd5);

    assign load36 = load_weight &&
                    (weight_row == 3'd3) &&
                    (weight_col == 3'd6);

    assign load37 = load_weight &&
                    (weight_row == 3'd3) &&
                    (weight_col == 3'd7);


    assign load40 = load_weight &&
                    (weight_row == 3'd4) &&
                    (weight_col == 3'd0);

    assign load41 = load_weight &&
                    (weight_row == 3'd4) &&
                    (weight_col == 3'd1);

    assign load42 = load_weight &&
                    (weight_row == 3'd4) &&
                    (weight_col == 3'd2);

    assign load43 = load_weight &&
                    (weight_row == 3'd4) &&
                    (weight_col == 3'd3);

    assign load44 = load_weight &&
                    (weight_row == 3'd4) &&
                    (weight_col == 3'd4);

    assign load45 = load_weight &&
                    (weight_row == 3'd4) &&
                    (weight_col == 3'd5);

    assign load46 = load_weight &&
                    (weight_row == 3'd4) &&
                    (weight_col == 3'd6);

    assign load47 = load_weight &&
                    (weight_row == 3'd4) &&
                    (weight_col == 3'd7);


    assign load50 = load_weight &&
                    (weight_row == 3'd5) &&
                    (weight_col == 3'd0);

    assign load51 = load_weight &&
                    (weight_row == 3'd5) &&
                    (weight_col == 3'd1);

    assign load52 = load_weight &&
                    (weight_row == 3'd5) &&
                    (weight_col == 3'd2);

    assign load53 = load_weight &&
                    (weight_row == 3'd5) &&
                    (weight_col == 3'd3);

    assign load54 = load_weight &&
                    (weight_row == 3'd5) &&
                    (weight_col == 3'd4);

    assign load55 = load_weight &&
                    (weight_row == 3'd5) &&
                    (weight_col == 3'd5);

    assign load56 = load_weight &&
                    (weight_row == 3'd5) &&
                    (weight_col == 3'd6);

    assign load57 = load_weight &&
                    (weight_row == 3'd5) &&
                    (weight_col == 3'd7);


    assign load60 = load_weight &&
                    (weight_row == 3'd6) &&
                    (weight_col == 3'd0);

    assign load61 = load_weight &&
                    (weight_row == 3'd6) &&
                    (weight_col == 3'd1);

    assign load62 = load_weight &&
                    (weight_row == 3'd6) &&
                    (weight_col == 3'd2);

    assign load63 = load_weight &&
                    (weight_row == 3'd6) &&
                    (weight_col == 3'd3);

    assign load64 = load_weight &&
                    (weight_row == 3'd6) &&
                    (weight_col == 3'd4);

    assign load65 = load_weight &&
                    (weight_row == 3'd6) &&
                    (weight_col == 3'd5);

    assign load66 = load_weight &&
                    (weight_row == 3'd6) &&
                    (weight_col == 3'd6);

    assign load67 = load_weight &&
                    (weight_row == 3'd6) &&
                    (weight_col == 3'd7);


    assign load70 = load_weight &&
                    (weight_row == 3'd7) &&
                    (weight_col == 3'd0);

    assign load71 = load_weight &&
                    (weight_row == 3'd7) &&
                    (weight_col == 3'd1);

    assign load72 = load_weight &&
                    (weight_row == 3'd7) &&
                    (weight_col == 3'd2);

    assign load73 = load_weight &&
                    (weight_row == 3'd7) &&
                    (weight_col == 3'd3);

    assign load74 = load_weight &&
                    (weight_row == 3'd7) &&
                    (weight_col == 3'd4);

    assign load75 = load_weight &&
                    (weight_row == 3'd7) &&
                    (weight_col == 3'd5);

    assign load76 = load_weight &&
                    (weight_row == 3'd7) &&
                    (weight_col == 3'd6);

    assign load77 = load_weight &&
                    (weight_row == 3'd7) &&
                    (weight_col == 3'd7);


    // ========================================================
    // ROW 0
    // ========================================================

    pe_ws #(.DW(DW), .AW(AW)) pe00 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load00),
        .weight_in(weight_data),
        .act_in(a0[0]),
        .act_out(a0[1]),
        .psum_in(p0[0]),
        .psum_out(p0[1]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe01 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load01),
        .weight_in(weight_data),
        .act_in(a0[1]),
        .act_out(a0[2]),
        .psum_in(p1[0]),
        .psum_out(p1[1]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe02 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load02),
        .weight_in(weight_data),
        .act_in(a0[2]),
        .act_out(a0[3]),
        .psum_in(p2[0]),
        .psum_out(p2[1]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe03 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load03),
        .weight_in(weight_data),
        .act_in(a0[3]),
        .act_out(a0[4]),
        .psum_in(p3[0]),
        .psum_out(p3[1]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe04 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load04),
        .weight_in(weight_data),
        .act_in(a0[4]),
        .act_out(a0[5]),
        .psum_in(p4[0]),
        .psum_out(p4[1]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe05 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load05),
        .weight_in(weight_data),
        .act_in(a0[5]),
        .act_out(a0[6]),
        .psum_in(p5[0]),
        .psum_out(p5[1]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe06 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load06),
        .weight_in(weight_data),
        .act_in(a0[6]),
        .act_out(a0[7]),
        .psum_in(p6[0]),
        .psum_out(p6[1]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe07 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load07),
        .weight_in(weight_data),
        .act_in(a0[7]),
        .act_out(a0[8]),
        .psum_in(p7[0]),
        .psum_out(p7[1]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );


    // ========================================================
    // ROW 1
    // ========================================================

    pe_ws #(.DW(DW), .AW(AW)) pe10 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load10),
        .weight_in(weight_data),
        .act_in(a1[0]),
        .act_out(a1[1]),
        .psum_in(p0[1]),
        .psum_out(p0[2]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe11 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load11),
        .weight_in(weight_data),
        .act_in(a1[1]),
        .act_out(a1[2]),
        .psum_in(p1[1]),
        .psum_out(p1[2]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe12 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load12),
        .weight_in(weight_data),
        .act_in(a1[2]),
        .act_out(a1[3]),
        .psum_in(p2[1]),
        .psum_out(p2[2]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe13 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load13),
        .weight_in(weight_data),
        .act_in(a1[3]),
        .act_out(a1[4]),
        .psum_in(p3[1]),
        .psum_out(p3[2]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe14 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load14),
        .weight_in(weight_data),
        .act_in(a1[4]),
        .act_out(a1[5]),
        .psum_in(p4[1]),
        .psum_out(p4[2]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe15 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load15),
        .weight_in(weight_data),
        .act_in(a1[5]),
        .act_out(a1[6]),
        .psum_in(p5[1]),
        .psum_out(p5[2]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe16 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load16),
        .weight_in(weight_data),
        .act_in(a1[6]),
        .act_out(a1[7]),
        .psum_in(p6[1]),
        .psum_out(p6[2]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe17 (
        .clk(clk),
        .rst_n(rst_n),
        .load_weight(load17),
        .weight_in(weight_data),
        .act_in(a1[7]),
        .act_out(a1[8]),
        .psum_in(p7[1]),
        .psum_out(p7[2]),
        .mac_en(mac_en),
        .clear_psum(clear_psum)
    );


    // ========================================================
    // ROW 2
    // ========================================================

    pe_ws #(.DW(DW), .AW(AW)) pe20 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load20), .weight_in(weight_data),
        .act_in(a2[0]), .act_out(a2[1]),
        .psum_in(p0[2]), .psum_out(p0[3]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe21 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load21), .weight_in(weight_data),
        .act_in(a2[1]), .act_out(a2[2]),
        .psum_in(p1[2]), .psum_out(p1[3]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe22 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load22), .weight_in(weight_data),
        .act_in(a2[2]), .act_out(a2[3]),
        .psum_in(p2[2]), .psum_out(p2[3]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe23 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load23), .weight_in(weight_data),
        .act_in(a2[3]), .act_out(a2[4]),
        .psum_in(p3[2]), .psum_out(p3[3]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe24 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load24), .weight_in(weight_data),
        .act_in(a2[4]), .act_out(a2[5]),
        .psum_in(p4[2]), .psum_out(p4[3]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe25 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load25), .weight_in(weight_data),
        .act_in(a2[5]), .act_out(a2[6]),
        .psum_in(p5[2]), .psum_out(p5[3]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe26 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load26), .weight_in(weight_data),
        .act_in(a2[6]), .act_out(a2[7]),
        .psum_in(p6[2]), .psum_out(p6[3]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe27 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load27), .weight_in(weight_data),
        .act_in(a2[7]), .act_out(a2[8]),
        .psum_in(p7[2]), .psum_out(p7[3]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );


    // ========================================================
    // ROW 3
    // ========================================================

    pe_ws #(.DW(DW), .AW(AW)) pe30 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load30), .weight_in(weight_data),
        .act_in(a3[0]), .act_out(a3[1]),
        .psum_in(p0[3]), .psum_out(p0[4]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe31 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load31), .weight_in(weight_data),
        .act_in(a3[1]), .act_out(a3[2]),
        .psum_in(p1[3]), .psum_out(p1[4]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe32 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load32), .weight_in(weight_data),
        .act_in(a3[2]), .act_out(a3[3]),
        .psum_in(p2[3]), .psum_out(p2[4]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe33 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load33), .weight_in(weight_data),
        .act_in(a3[3]), .act_out(a3[4]),
        .psum_in(p3[3]), .psum_out(p3[4]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe34 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load34), .weight_in(weight_data),
        .act_in(a3[4]), .act_out(a3[5]),
        .psum_in(p4[3]), .psum_out(p4[4]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe35 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load35), .weight_in(weight_data),
        .act_in(a3[5]), .act_out(a3[6]),
        .psum_in(p5[3]), .psum_out(p5[4]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe36 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load36), .weight_in(weight_data),
        .act_in(a3[6]), .act_out(a3[7]),
        .psum_in(p6[3]), .psum_out(p6[4]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe37 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load37), .weight_in(weight_data),
        .act_in(a3[7]), .act_out(a3[8]),
        .psum_in(p7[3]), .psum_out(p7[4]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );


    // ========================================================
    // ROW 4
    // ========================================================

    pe_ws #(.DW(DW), .AW(AW)) pe40 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load40), .weight_in(weight_data),
        .act_in(a4[0]), .act_out(a4[1]),
        .psum_in(p0[4]), .psum_out(p0[5]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe41 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load41), .weight_in(weight_data),
        .act_in(a4[1]), .act_out(a4[2]),
        .psum_in(p1[4]), .psum_out(p1[5]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe42 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load42), .weight_in(weight_data),
        .act_in(a4[2]), .act_out(a4[3]),
        .psum_in(p2[4]), .psum_out(p2[5]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe43 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load43), .weight_in(weight_data),
        .act_in(a4[3]), .act_out(a4[4]),
        .psum_in(p3[4]), .psum_out(p3[5]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe44 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load44), .weight_in(weight_data),
        .act_in(a4[4]), .act_out(a4[5]),
        .psum_in(p4[4]), .psum_out(p4[5]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe45 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load45), .weight_in(weight_data),
        .act_in(a4[5]), .act_out(a4[6]),
        .psum_in(p5[4]), .psum_out(p5[5]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe46 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load46), .weight_in(weight_data),
        .act_in(a4[6]), .act_out(a4[7]),
        .psum_in(p6[4]), .psum_out(p6[5]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe47 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load47), .weight_in(weight_data),
        .act_in(a4[7]), .act_out(a4[8]),
        .psum_in(p7[4]), .psum_out(p7[5]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );


    // ========================================================
    // ROW 5
    // ========================================================

    pe_ws #(.DW(DW), .AW(AW)) pe50 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load50), .weight_in(weight_data),
        .act_in(a5[0]), .act_out(a5[1]),
        .psum_in(p0[5]), .psum_out(p0[6]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe51 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load51), .weight_in(weight_data),
        .act_in(a5[1]), .act_out(a5[2]),
        .psum_in(p1[5]), .psum_out(p1[6]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe52 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load52), .weight_in(weight_data),
        .act_in(a5[2]), .act_out(a5[3]),
        .psum_in(p2[5]), .psum_out(p2[6]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe53 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load53), .weight_in(weight_data),
        .act_in(a5[3]), .act_out(a5[4]),
        .psum_in(p3[5]), .psum_out(p3[6]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe54 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load54), .weight_in(weight_data),
        .act_in(a5[4]), .act_out(a5[5]),
        .psum_in(p4[5]), .psum_out(p4[6]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe55 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load55), .weight_in(weight_data),
        .act_in(a5[5]), .act_out(a5[6]),
        .psum_in(p5[5]), .psum_out(p5[6]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe56 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load56), .weight_in(weight_data),
        .act_in(a5[6]), .act_out(a5[7]),
        .psum_in(p6[5]), .psum_out(p6[6]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe57 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load57), .weight_in(weight_data),
        .act_in(a5[7]), .act_out(a5[8]),
        .psum_in(p7[5]), .psum_out(p7[6]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );


    // ========================================================
    // ROW 6
    // ========================================================

    pe_ws #(.DW(DW), .AW(AW)) pe60 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load60), .weight_in(weight_data),
        .act_in(a6[0]), .act_out(a6[1]),
        .psum_in(p0[6]), .psum_out(p0[7]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe61 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load61), .weight_in(weight_data),
        .act_in(a6[1]), .act_out(a6[2]),
        .psum_in(p1[6]), .psum_out(p1[7]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe62 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load62), .weight_in(weight_data),
        .act_in(a6[2]), .act_out(a6[3]),
        .psum_in(p2[6]), .psum_out(p2[7]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe63 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load63), .weight_in(weight_data),
        .act_in(a6[3]), .act_out(a6[4]),
        .psum_in(p3[6]), .psum_out(p3[7]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe64 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load64), .weight_in(weight_data),
        .act_in(a6[4]), .act_out(a6[5]),
        .psum_in(p4[6]), .psum_out(p4[7]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe65 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load65), .weight_in(weight_data),
        .act_in(a6[5]), .act_out(a6[6]),
        .psum_in(p5[6]), .psum_out(p5[7]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe66 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load66), .weight_in(weight_data),
        .act_in(a6[6]), .act_out(a6[7]),
        .psum_in(p6[6]), .psum_out(p6[7]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe67 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load67), .weight_in(weight_data),
        .act_in(a6[7]), .act_out(a6[8]),
        .psum_in(p7[6]), .psum_out(p7[7]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );


    // ========================================================
    // ROW 7
    // ========================================================

    pe_ws #(.DW(DW), .AW(AW)) pe70 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load70), .weight_in(weight_data),
        .act_in(a7[0]), .act_out(a7[1]),
        .psum_in(p0[7]), .psum_out(p0[8]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe71 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load71), .weight_in(weight_data),
        .act_in(a7[1]), .act_out(a7[2]),
        .psum_in(p1[7]), .psum_out(p1[8]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe72 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load72), .weight_in(weight_data),
        .act_in(a7[2]), .act_out(a7[3]),
        .psum_in(p2[7]), .psum_out(p2[8]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe73 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load73), .weight_in(weight_data),
        .act_in(a7[3]), .act_out(a7[4]),
        .psum_in(p3[7]), .psum_out(p3[8]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe74 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load74), .weight_in(weight_data),
        .act_in(a7[4]), .act_out(a7[5]),
        .psum_in(p4[7]), .psum_out(p4[8]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe75 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load75), .weight_in(weight_data),
        .act_in(a7[5]), .act_out(a7[6]),
        .psum_in(p5[7]), .psum_out(p5[8]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe76 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load76), .weight_in(weight_data),
        .act_in(a7[6]), .act_out(a7[7]),
        .psum_in(p6[7]), .psum_out(p6[8]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );

    pe_ws #(.DW(DW), .AW(AW)) pe77 (
        .clk(clk), .rst_n(rst_n),
        .load_weight(load77), .weight_in(weight_data),
        .act_in(a7[7]), .act_out(a7[8]),
        .psum_in(p7[7]), .psum_out(p7[8]),
        .mac_en(mac_en), .clear_psum(clear_psum)
    );


    // ========================================================
    // FINAL PSUM OUTPUTS
    // ========================================================

    assign psum_out0 = p0[8];
    assign psum_out1 = p1[8];
    assign psum_out2 = p2[8];
    assign psum_out3 = p3[8];

    assign psum_out4 = p4[8];
    assign psum_out5 = p5[8];
    assign psum_out6 = p6[8];
    assign psum_out7 = p7[8];

endmodule