`timescale 1ns/1ps

module activation_buffer_ws #(
    parameter DW = 8
)(
    input wire clk,
    input wire rst_n,

    // ========================================================
    // LOAD INTERFACE
    //
    // One element loaded per cycle.
    //
    // A[wr_row][wr_col] <= wr_data
    // ========================================================

    input wire                 wr_en,
    input wire [2:0]           wr_row,
    input wire [2:0]           wr_col,
    input wire signed [DW-1:0] wr_data,

    // ========================================================
    // COMPUTE READ INTERFACE
    //
    // rd_row selects one complete row.
    //
    // rd_row = 0:
    // A[0][0] A[0][1] ... A[0][7]
    //
    // rd_row = 1:
    // A[1][0] A[1][1] ... A[1][7]
    // ========================================================

    input wire                 rd_en,
    input wire [2:0]           rd_row,

    output reg signed [DW-1:0] act0,
    output reg signed [DW-1:0] act1,
    output reg signed [DW-1:0] act2,
    output reg signed [DW-1:0] act3,

    output reg signed [DW-1:0] act4,
    output reg signed [DW-1:0] act5,
    output reg signed [DW-1:0] act6,
    output reg signed [DW-1:0] act7,

    output reg                 data_valid
);

    // ========================================================
    // 8 ROW BANKS
    //
    // bank0[col] = A[0][col]
    // bank1[col] = A[1][col]
    // ...
    // bank7[col] = A[7][col]
    // ========================================================

    reg signed [DW-1:0] bank0 [0:7];
    reg signed [DW-1:0] bank1 [0:7];
    reg signed [DW-1:0] bank2 [0:7];
    reg signed [DW-1:0] bank3 [0:7];

    reg signed [DW-1:0] bank4 [0:7];
    reg signed [DW-1:0] bank5 [0:7];
    reg signed [DW-1:0] bank6 [0:7];
    reg signed [DW-1:0] bank7 [0:7];

    integer i;

    // ========================================================
    // WRITE
    // ========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            for (i = 0; i < 8; i = i + 1) begin

                bank0[i] <= 0;
                bank1[i] <= 0;
                bank2[i] <= 0;
                bank3[i] <= 0;

                bank4[i] <= 0;
                bank5[i] <= 0;
                bank6[i] <= 0;
                bank7[i] <= 0;

            end

        end

        else if (wr_en) begin

            case (wr_row)

                3'd0: bank0[wr_col] <= wr_data;
                3'd1: bank1[wr_col] <= wr_data;
                3'd2: bank2[wr_col] <= wr_data;
                3'd3: bank3[wr_col] <= wr_data;

                3'd4: bank4[wr_col] <= wr_data;
                3'd5: bank5[wr_col] <= wr_data;
                3'd6: bank6[wr_col] <= wr_data;
                3'd7: bank7[wr_col] <= wr_data;

                default: begin
                end

            endcase

        end

    end

    // ========================================================
    // READ ONE COMPLETE MATRIX ROW
    //
    // Synchronous read.
    // ========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            act0 <= 0;
            act1 <= 0;
            act2 <= 0;
            act3 <= 0;

            act4 <= 0;
            act5 <= 0;
            act6 <= 0;
            act7 <= 0;

            data_valid <= 1'b0;

        end

        else begin

            data_valid <= rd_en;

            if (rd_en) begin

                case (rd_row)

                    3'd0: begin
                        act0 <= bank0[0];
                        act1 <= bank0[1];
                        act2 <= bank0[2];
                        act3 <= bank0[3];
                        act4 <= bank0[4];
                        act5 <= bank0[5];
                        act6 <= bank0[6];
                        act7 <= bank0[7];
                    end

                    3'd1: begin
                        act0 <= bank1[0];
                        act1 <= bank1[1];
                        act2 <= bank1[2];
                        act3 <= bank1[3];
                        act4 <= bank1[4];
                        act5 <= bank1[5];
                        act6 <= bank1[6];
                        act7 <= bank1[7];
                    end

                    3'd2: begin
                        act0 <= bank2[0];
                        act1 <= bank2[1];
                        act2 <= bank2[2];
                        act3 <= bank2[3];
                        act4 <= bank2[4];
                        act5 <= bank2[5];
                        act6 <= bank2[6];
                        act7 <= bank2[7];
                    end

                    3'd3: begin
                        act0 <= bank3[0];
                        act1 <= bank3[1];
                        act2 <= bank3[2];
                        act3 <= bank3[3];
                        act4 <= bank3[4];
                        act5 <= bank3[5];
                        act6 <= bank3[6];
                        act7 <= bank3[7];
                    end

                    3'd4: begin
                        act0 <= bank4[0];
                        act1 <= bank4[1];
                        act2 <= bank4[2];
                        act3 <= bank4[3];
                        act4 <= bank4[4];
                        act5 <= bank4[5];
                        act6 <= bank4[6];
                        act7 <= bank4[7];
                    end

                    3'd5: begin
                        act0 <= bank5[0];
                        act1 <= bank5[1];
                        act2 <= bank5[2];
                        act3 <= bank5[3];
                        act4 <= bank5[4];
                        act5 <= bank5[5];
                        act6 <= bank5[6];
                        act7 <= bank5[7];
                    end

                    3'd6: begin
                        act0 <= bank6[0];
                        act1 <= bank6[1];
                        act2 <= bank6[2];
                        act3 <= bank6[3];
                        act4 <= bank6[4];
                        act5 <= bank6[5];
                        act6 <= bank6[6];
                        act7 <= bank6[7];
                    end

                    3'd7: begin
                        act0 <= bank7[0];
                        act1 <= bank7[1];
                        act2 <= bank7[2];
                        act3 <= bank7[3];
                        act4 <= bank7[4];
                        act5 <= bank7[5];
                        act6 <= bank7[6];
                        act7 <= bank7[7];
                    end

                    default: begin
                    end

                endcase

            end

        end

    end

endmodule