`timescale 1ns/1ps

module input_skew #(
    parameter DW = 8
)(
    input wire clk,
    input wire rst_n,

    // ========================================================
    // INPUT ACTIVATION STREAMS
    //
    // Each input represents one matrix row.
    //
    // act_in0 -> A row 0
    // act_in1 -> A row 1
    // ...
    // act_in7 -> A row 7
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
    // INPUT VALID
    // ========================================================

    input wire valid_in0,
    input wire valid_in1,
    input wire valid_in2,
    input wire valid_in3,
    input wire valid_in4,
    input wire valid_in5,
    input wire valid_in6,
    input wire valid_in7,

    // ========================================================
    // SKEWED OUTPUT STREAMS
    // ========================================================

    output wire signed [DW-1:0] act_out0,
    output wire signed [DW-1:0] act_out1,
    output wire signed [DW-1:0] act_out2,
    output wire signed [DW-1:0] act_out3,
    output wire signed [DW-1:0] act_out4,
    output wire signed [DW-1:0] act_out5,
    output wire signed [DW-1:0] act_out6,
    output wire signed [DW-1:0] act_out7,

    // ========================================================
    // OUTPUT VALID
    // ========================================================

    output wire valid_out0,
    output wire valid_out1,
    output wire valid_out2,
    output wire valid_out3,
    output wire valid_out4,
    output wire valid_out5,
    output wire valid_out6,
    output wire valid_out7
);


    // ========================================================
    // ROW 0
    //
    // Delay = 0 cycles
    // ========================================================

    assign act_out0   = act_in0;
    assign valid_out0 = valid_in0;


    // ========================================================
    // ROW 1
    //
    // Delay = 1 cycle
    // ========================================================

    reg signed [DW-1:0] delay1_data;
    reg                 delay1_valid;


    // ========================================================
    // ROW 2
    //
    // Delay = 2 cycles
    // ========================================================

    reg signed [DW-1:0] delay2_data_1;
    reg signed [DW-1:0] delay2_data_2;

    reg delay2_valid_1;
    reg delay2_valid_2;


    // ========================================================
    // ROW 3
    //
    // Delay = 3 cycles
    // ========================================================

    reg signed [DW-1:0] delay3_data_1;
    reg signed [DW-1:0] delay3_data_2;
    reg signed [DW-1:0] delay3_data_3;

    reg delay3_valid_1;
    reg delay3_valid_2;
    reg delay3_valid_3;


    // ========================================================
    // ROW 4
    //
    // Delay = 4 cycles
    // ========================================================

    reg signed [DW-1:0] delay4_data_1;
    reg signed [DW-1:0] delay4_data_2;
    reg signed [DW-1:0] delay4_data_3;
    reg signed [DW-1:0] delay4_data_4;

    reg delay4_valid_1;
    reg delay4_valid_2;
    reg delay4_valid_3;
    reg delay4_valid_4;


    // ========================================================
    // ROW 5
    //
    // Delay = 5 cycles
    // ========================================================

    reg signed [DW-1:0] delay5_data_1;
    reg signed [DW-1:0] delay5_data_2;
    reg signed [DW-1:0] delay5_data_3;
    reg signed [DW-1:0] delay5_data_4;
    reg signed [DW-1:0] delay5_data_5;

    reg delay5_valid_1;
    reg delay5_valid_2;
    reg delay5_valid_3;
    reg delay5_valid_4;
    reg delay5_valid_5;


    // ========================================================
    // ROW 6
    //
    // Delay = 6 cycles
    // ========================================================

    reg signed [DW-1:0] delay6_data_1;
    reg signed [DW-1:0] delay6_data_2;
    reg signed [DW-1:0] delay6_data_3;
    reg signed [DW-1:0] delay6_data_4;
    reg signed [DW-1:0] delay6_data_5;
    reg signed [DW-1:0] delay6_data_6;

    reg delay6_valid_1;
    reg delay6_valid_2;
    reg delay6_valid_3;
    reg delay6_valid_4;
    reg delay6_valid_5;
    reg delay6_valid_6;


    // ========================================================
    // ROW 7
    //
    // Delay = 7 cycles
    // ========================================================

    reg signed [DW-1:0] delay7_data_1;
    reg signed [DW-1:0] delay7_data_2;
    reg signed [DW-1:0] delay7_data_3;
    reg signed [DW-1:0] delay7_data_4;
    reg signed [DW-1:0] delay7_data_5;
    reg signed [DW-1:0] delay7_data_6;
    reg signed [DW-1:0] delay7_data_7;

    reg delay7_valid_1;
    reg delay7_valid_2;
    reg delay7_valid_3;
    reg delay7_valid_4;
    reg delay7_valid_5;
    reg delay7_valid_6;
    reg delay7_valid_7;


    // ========================================================
    // DELAY PIPELINES
    // ========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            // ------------------------------------------------
            // Row 1
            // ------------------------------------------------

            delay1_data  <= 0;
            delay1_valid <= 0;


            // ------------------------------------------------
            // Row 2
            // ------------------------------------------------

            delay2_data_1 <= 0;
            delay2_data_2 <= 0;

            delay2_valid_1 <= 0;
            delay2_valid_2 <= 0;


            // ------------------------------------------------
            // Row 3
            // ------------------------------------------------

            delay3_data_1 <= 0;
            delay3_data_2 <= 0;
            delay3_data_3 <= 0;

            delay3_valid_1 <= 0;
            delay3_valid_2 <= 0;
            delay3_valid_3 <= 0;


            // ------------------------------------------------
            // Row 4
            // ------------------------------------------------

            delay4_data_1 <= 0;
            delay4_data_2 <= 0;
            delay4_data_3 <= 0;
            delay4_data_4 <= 0;

            delay4_valid_1 <= 0;
            delay4_valid_2 <= 0;
            delay4_valid_3 <= 0;
            delay4_valid_4 <= 0;


            // ------------------------------------------------
            // Row 5
            // ------------------------------------------------

            delay5_data_1 <= 0;
            delay5_data_2 <= 0;
            delay5_data_3 <= 0;
            delay5_data_4 <= 0;
            delay5_data_5 <= 0;

            delay5_valid_1 <= 0;
            delay5_valid_2 <= 0;
            delay5_valid_3 <= 0;
            delay5_valid_4 <= 0;
            delay5_valid_5 <= 0;


            // ------------------------------------------------
            // Row 6
            // ------------------------------------------------

            delay6_data_1 <= 0;
            delay6_data_2 <= 0;
            delay6_data_3 <= 0;
            delay6_data_4 <= 0;
            delay6_data_5 <= 0;
            delay6_data_6 <= 0;

            delay6_valid_1 <= 0;
            delay6_valid_2 <= 0;
            delay6_valid_3 <= 0;
            delay6_valid_4 <= 0;
            delay6_valid_5 <= 0;
            delay6_valid_6 <= 0;


            // ------------------------------------------------
            // Row 7
            // ------------------------------------------------

            delay7_data_1 <= 0;
            delay7_data_2 <= 0;
            delay7_data_3 <= 0;
            delay7_data_4 <= 0;
            delay7_data_5 <= 0;
            delay7_data_6 <= 0;
            delay7_data_7 <= 0;

            delay7_valid_1 <= 0;
            delay7_valid_2 <= 0;
            delay7_valid_3 <= 0;
            delay7_valid_4 <= 0;
            delay7_valid_5 <= 0;
            delay7_valid_6 <= 0;
            delay7_valid_7 <= 0;

        end

        else begin

            // =================================================
            // ROW 1
            // =================================================

            delay1_data  <= act_in1;
            delay1_valid <= valid_in1;


            // =================================================
            // ROW 2
            // =================================================

            delay2_data_1 <= act_in2;
            delay2_data_2 <= delay2_data_1;

            delay2_valid_1 <= valid_in2;
            delay2_valid_2 <= delay2_valid_1;


            // =================================================
            // ROW 3
            // =================================================

            delay3_data_1 <= act_in3;
            delay3_data_2 <= delay3_data_1;
            delay3_data_3 <= delay3_data_2;

            delay3_valid_1 <= valid_in3;
            delay3_valid_2 <= delay3_valid_1;
            delay3_valid_3 <= delay3_valid_2;


            // =================================================
            // ROW 4
            // =================================================

            delay4_data_1 <= act_in4;
            delay4_data_2 <= delay4_data_1;
            delay4_data_3 <= delay4_data_2;
            delay4_data_4 <= delay4_data_3;

            delay4_valid_1 <= valid_in4;
            delay4_valid_2 <= delay4_valid_1;
            delay4_valid_3 <= delay4_valid_2;
            delay4_valid_4 <= delay4_valid_3;


            // =================================================
            // ROW 5
            // =================================================

            delay5_data_1 <= act_in5;
            delay5_data_2 <= delay5_data_1;
            delay5_data_3 <= delay5_data_2;
            delay5_data_4 <= delay5_data_3;
            delay5_data_5 <= delay5_data_4;

            delay5_valid_1 <= valid_in5;
            delay5_valid_2 <= delay5_valid_1;
            delay5_valid_3 <= delay5_valid_2;
            delay5_valid_4 <= delay5_valid_3;
            delay5_valid_5 <= delay5_valid_4;


            // =================================================
            // ROW 6
            // =================================================

            delay6_data_1 <= act_in6;
            delay6_data_2 <= delay6_data_1;
            delay6_data_3 <= delay6_data_2;
            delay6_data_4 <= delay6_data_3;
            delay6_data_5 <= delay6_data_4;
            delay6_data_6 <= delay6_data_5;

            delay6_valid_1 <= valid_in6;
            delay6_valid_2 <= delay6_valid_1;
            delay6_valid_3 <= delay6_valid_2;
            delay6_valid_4 <= delay6_valid_3;
            delay6_valid_5 <= delay6_valid_4;
            delay6_valid_6 <= delay6_valid_5;


            // =================================================
            // ROW 7
            // =================================================

            delay7_data_1 <= act_in7;
            delay7_data_2 <= delay7_data_1;
            delay7_data_3 <= delay7_data_2;
            delay7_data_4 <= delay7_data_3;
            delay7_data_5 <= delay7_data_4;
            delay7_data_6 <= delay7_data_5;
            delay7_data_7 <= delay7_data_6;

            delay7_valid_1 <= valid_in7;
            delay7_valid_2 <= delay7_valid_1;
            delay7_valid_3 <= delay7_valid_2;
            delay7_valid_4 <= delay7_valid_3;
            delay7_valid_5 <= delay7_valid_4;
            delay7_valid_6 <= delay7_valid_5;
            delay7_valid_7 <= delay7_valid_6;

        end

    end


    // ========================================================
    // OUTPUT CONNECTIONS
    // ========================================================

    assign act_out1   = delay1_data;
    assign valid_out1 = delay1_valid;

    assign act_out2   = delay2_data_2;
    assign valid_out2 = delay2_valid_2;

    assign act_out3   = delay3_data_3;
    assign valid_out3 = delay3_valid_3;

    assign act_out4   = delay4_data_4;
    assign valid_out4 = delay4_valid_4;

    assign act_out5   = delay5_data_5;
    assign valid_out5 = delay5_valid_5;

    assign act_out6   = delay6_data_6;
    assign valid_out6 = delay6_valid_6;

    assign act_out7   = delay7_data_7;
    assign valid_out7 = delay7_valid_7;


endmodule