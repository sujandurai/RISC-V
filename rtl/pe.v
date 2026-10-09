`timescale 1ns/1ps

module pe_ws #(
    parameter DW = 8,
    parameter AW = 32
)(
    input wire                  clk,
    input wire                  rst_n,

    // ========================================================
    // WEIGHT LOADING
    // ========================================================

    input wire                  load_weight,
    input wire signed [DW-1:0]  weight_in,

    // ========================================================
    // ACTIVATION PATH
    // Left -> Right
    // ========================================================

    input wire signed [DW-1:0]  act_in,
    output reg signed [DW-1:0]  act_out,

    // ========================================================
    // PARTIAL-SUM PATH
    // Top -> Bottom
    // ========================================================

    input wire signed [AW-1:0]  psum_in,
    output reg signed [AW-1:0]  psum_out,

    // ========================================================
    // COMPUTATION CONTROL
    // ========================================================

    input wire                  mac_en,
    input wire                  clear_psum
);

    // ========================================================
    // STATIONARY WEIGHT
    //
    // This register holds the weight during computation.
    // ========================================================

    reg signed [DW-1:0] weight_reg;


    // ========================================================
    // PE
    // ========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            weight_reg <= 0;
            act_out    <= 0;
            psum_out   <= 0;

        end

        else begin

            // ------------------------------------------------
            // Load weight
            //
            // Used only during the weight-loading phase.
            // ------------------------------------------------

            if (load_weight) begin
                weight_reg <= weight_in;
            end


            // ------------------------------------------------
            // Activation forwarding
            //
            // Activation moves left -> right.
            // ------------------------------------------------

            act_out <= act_in;


            // ------------------------------------------------
            // Partial-sum operation
            // ------------------------------------------------

            if (clear_psum) begin

                psum_out <= 0;

            end

            else if (mac_en) begin

                psum_out <= psum_in +
                            (act_in * weight_reg);

            end

        end

    end

endmodule