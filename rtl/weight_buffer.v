`timescale 1ns/1ps

module weight_buffer_ws #(
    parameter DW = 8
)(
    input wire clk,
    input wire rst_n,

    // ========================================================
    // WRITE B MATRIX
    // ========================================================

    input wire                 wr_en,
    input wire [2:0]           wr_row,
    input wire [2:0]           wr_col,
    input wire signed [DW-1:0] wr_data,

    // ========================================================
    // READ ONE WEIGHT FOR PE LOADING
    //
    // B[rd_row][rd_col]
    // ========================================================

    input wire                 rd_en,
    input wire [2:0]           rd_row,
    input wire [2:0]           rd_col,

    output reg signed [DW-1:0] rd_data,
    output reg                 data_valid
);

    reg signed [DW-1:0] mem [0:63];

    integer i;

    wire [5:0] wr_addr;
    wire [5:0] rd_addr;

    assign wr_addr = {wr_row, wr_col};
    assign rd_addr = {rd_row, rd_col};

    // ========================================================
    // WRITE
    // ========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            for (i = 0; i < 64; i = i + 1)
                mem[i] <= 0;

        end

        else if (wr_en) begin

            mem[wr_addr] <= wr_data;

        end

    end

    // ========================================================
    // READ
    // ========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            rd_data    <= 0;
            data_valid <= 1'b0;

        end

        else begin

            data_valid <= rd_en;

            if (rd_en)
                rd_data <= mem[rd_addr];

        end

    end

endmodule