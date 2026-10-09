`timescale 1ns/1ps

module output_buffer_ws #(
    parameter AW = 32
)(
    input wire clk,
    input wire rst_n,

    // ========================================================
    // CAPTURE CONTROL
    // ========================================================

    input wire       capture_en,
    input wire [3:0] diag_count,

    // ========================================================
    // 8 STREAMING PSUM INPUTS
    //
    // psum_out0 -> C[row][0]
    // psum_out1 -> C[row][1]
    // ...
    // psum_out7 -> C[row][7]
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
    // NORMAL OUTPUT READ INTERFACE
    //
    // address = row*8 + column
    // ========================================================

    input wire                  rd_en,
    input wire [5:0]            rd_addr,
    output reg signed [AW-1:0] rd_data,

    output reg                  data_valid,
    output reg                  matrix_done
);

    // ========================================================
    // 8 BANKS
    //
    // bank0[row] = C[row][0]
    // bank1[row] = C[row][1]
    // ...
    // bank7[row] = C[row][7]
    //
    // Each bank contains 8 results.
    //
    // Total:
    // 8 × 8 × AW
    // ========================================================

    reg signed [AW-1:0] bank0 [0:7];
    reg signed [AW-1:0] bank1 [0:7];
    reg signed [AW-1:0] bank2 [0:7];
    reg signed [AW-1:0] bank3 [0:7];

    reg signed [AW-1:0] bank4 [0:7];
    reg signed [AW-1:0] bank5 [0:7];
    reg signed [AW-1:0] bank6 [0:7];
    reg signed [AW-1:0] bank7 [0:7];

    integer i;

    // ========================================================
    // WRITE / CAPTURE
    //
    // For a given diagonal:
    //
    // column 0 -> row = diag_count
    // column 1 -> row = diag_count - 1
    // ...
    // column 7 -> row = diag_count - 7
    //
    // Only valid row/column combinations are written.
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

        else if (capture_en) begin

            // ------------------------------------------------
            // Column 0
            // ------------------------------------------------

            if (diag_count <= 7)
                bank0[diag_count] <= psum_in0;


            // ------------------------------------------------
            // Column 1
            // ------------------------------------------------

            if ((diag_count >= 1) &&
                (diag_count <= 8))
                bank1[diag_count - 1] <= psum_in1;


            // ------------------------------------------------
            // Column 2
            // ------------------------------------------------

            if ((diag_count >= 2) &&
                (diag_count <= 9))
                bank2[diag_count - 2] <= psum_in2;


            // ------------------------------------------------
            // Column 3
            // ------------------------------------------------

            if ((diag_count >= 3) &&
                (diag_count <= 10))
                bank3[diag_count - 3] <= psum_in3;


            // ------------------------------------------------
            // Column 4
            // ------------------------------------------------

            if ((diag_count >= 4) &&
                (diag_count <= 11))
                bank4[diag_count - 4] <= psum_in4;


            // ------------------------------------------------
            // Column 5
            // ------------------------------------------------

            if ((diag_count >= 5) &&
                (diag_count <= 12))
                bank5[diag_count - 5] <= psum_in5;


            // ------------------------------------------------
            // Column 6
            // ------------------------------------------------

            if ((diag_count >= 6) &&
                (diag_count <= 13))
                bank6[diag_count - 6] <= psum_in6;


            // ------------------------------------------------
            // Column 7
            // ------------------------------------------------

            if ((diag_count >= 7) &&
                (diag_count <= 14))
                bank7[diag_count - 7] <= psum_in7;

        end

    end


    // ========================================================
    // MATRIX DONE
    //
    // Diagonal 14 contains C[7][7].
    // ========================================================

    always @(posedge clk) begin

        if (!rst_n) begin
            matrix_done <= 1'b0;
        end
        else begin

            matrix_done <= 1'b0;

            if (capture_en && (diag_count == 4'd14))
                matrix_done <= 1'b1;

        end

    end


    // ========================================================
    // READ
    //
    // rd_addr:
    //
    // [5:3] = row
    // [2:0] = column
    //
    // address = row*8 + column
    // ========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            rd_data    <= 0;
            data_valid <= 1'b0;

        end

        else begin

            data_valid <= rd_en;

            if (rd_en) begin

                case (rd_addr[2:0])

                    3'd0:
                        rd_data <= bank0[rd_addr[5:3]];

                    3'd1:
                        rd_data <= bank1[rd_addr[5:3]];

                    3'd2:
                        rd_data <= bank2[rd_addr[5:3]];

                    3'd3:
                        rd_data <= bank3[rd_addr[5:3]];

                    3'd4:
                        rd_data <= bank4[rd_addr[5:3]];

                    3'd5:
                        rd_data <= bank5[rd_addr[5:3]];

                    3'd6:
                        rd_data <= bank6[rd_addr[5:3]];

                    3'd7:
                        rd_data <= bank7[rd_addr[5:3]];

                    default:
                        rd_data <= 0;

                endcase

            end

        end

    end

endmodule