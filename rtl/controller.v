`timescale 1ns/1ps

module controller (
    input wire clk,
    input wire rst_n,

    // ========================================================
    // START / STATUS
    // ========================================================

    input wire start,

    output reg busy,
    output reg done,

    // ========================================================
    // ACTIVATION BUFFER READ CONTROL
    // ========================================================

    output reg       act_rd_en,
    output reg [2:0] act_rd_row,

    // ========================================================
    // WEIGHT BUFFER READ CONTROL
    // ========================================================

    output reg       weight_rd_en,
    output reg [2:0] weight_rd_row,
    output reg [2:0] weight_rd_col,

    // ========================================================
    // LOAD WEIGHT INTO SELECTED PE
    // ========================================================

    output reg       load_weight,
    output reg [2:0] load_weight_row,
    output reg [2:0] load_weight_col,

    // ========================================================
    // COMPUTATION CONTROL
    // ========================================================

    output reg clear_psum,
    output reg mac_en,

    // ========================================================
    // OUTPUT CAPTURE CONTROL
    // ========================================================

    output reg       capture_en,
    output reg [3:0] diag_count
);

    // ========================================================
    // FSM STATES
    // ========================================================

    localparam S_IDLE        = 4'd0;
    localparam S_WEIGHT_READ = 4'd1;
    localparam S_WEIGHT_LOAD = 4'd2;
    localparam S_CLEAR       = 4'd3;
    localparam S_COMPUTE     = 4'd4;
    localparam S_WAIT_OUTPUT = 4'd5;
    localparam S_CAPTURE     = 4'd6;
    localparam S_DONE        = 4'd7;


    reg [3:0] state;
    reg [3:0] next_state;


    // ========================================================
    // WEIGHT ADDRESS
    //
    // 64 weights:
    //
    // row = 0..7
    // col = 0..7
    // ========================================================

    reg [2:0] weight_row;
    reg [2:0] weight_col;


    // ========================================================
    // ACTIVATION ROW COUNTER
    //
    // 0..7
    // ========================================================

    reg [2:0] act_row;


    // ========================================================
    // OUTPUT DIAGONAL COUNTER
    //
    // 0..14
    // ========================================================

    reg [3:0] capture_diag;


    // ========================================================
    // FSM STATE REGISTER
    // ========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            state <= S_IDLE;

        end

        else begin

            state <= next_state;

        end

    end


    // ========================================================
    // NEXT-STATE LOGIC
    // ========================================================

    always @(*) begin

        next_state = state;

        case (state)

            // ------------------------------------------------
            // IDLE
            // ------------------------------------------------

            S_IDLE: begin

                if (start)
                    next_state = S_WEIGHT_READ;

            end


            // ------------------------------------------------
            // REQUEST WEIGHT FROM BUFFER
            // ------------------------------------------------

            S_WEIGHT_READ: begin

                next_state = S_WEIGHT_LOAD;

            end


            // ------------------------------------------------
            // LOAD REQUESTED WEIGHT INTO PE
            // ------------------------------------------------

            S_WEIGHT_LOAD: begin

                if ((weight_row == 3'd7) &&
                    (weight_col == 3'd7)) begin

                    next_state = S_CLEAR;

                end

                else begin

                    next_state = S_WEIGHT_READ;

                end

            end


            // ------------------------------------------------
            // CLEAR ALL PE PSUMs
            // ------------------------------------------------

            S_CLEAR: begin

                next_state = S_COMPUTE;

            end


            // ------------------------------------------------
            // READ 8 ACTIVATION ROWS
            // ------------------------------------------------

            S_COMPUTE: begin

                if (act_row == 3'd7)
                    next_state = S_WAIT_OUTPUT;

            end


            // ------------------------------------------------
            // ONE PIPELINE WAIT CYCLE
            // ------------------------------------------------

            S_WAIT_OUTPUT: begin

                next_state = S_CAPTURE;

            end


            // ------------------------------------------------
            // CAPTURE 15 OUTPUT DIAGONALS
            // ------------------------------------------------

            S_CAPTURE: begin

                if (capture_diag == 4'd14)
                    next_state = S_DONE;

            end


            // ------------------------------------------------
            // DONE
            // ------------------------------------------------

            S_DONE: begin

                next_state = S_IDLE;

            end


            default: begin

                next_state = S_IDLE;

            end

        endcase

    end


    // ========================================================
    // COUNTER LOGIC
    // ========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            weight_row  <= 3'd0;
            weight_col  <= 3'd0;

            act_row     <= 3'd0;

            capture_diag <= 4'd0;

        end

        else begin

            case (state)

                // ============================================
                // START
                // ============================================

                S_IDLE: begin

                    if (start) begin

                        weight_row <= 3'd0;
                        weight_col <= 3'd0;

                        act_row <= 3'd0;

                        capture_diag <= 4'd0;

                    end

                end


                // ============================================
                // AFTER WEIGHT LOAD
                //
                // Move to next B address.
                // ============================================

                S_WEIGHT_LOAD: begin

                    if ((weight_row != 3'd7) ||
                        (weight_col != 3'd7)) begin

                        if (weight_col == 3'd7) begin

                            weight_col <= 3'd0;
                            weight_row <= weight_row + 3'd1;

                        end

                        else begin

                            weight_col <= weight_col + 3'd1;

                        end

                    end

                end


                // ============================================
                // COMPUTE
                // ============================================

                S_COMPUTE: begin

                    if (act_row != 3'd7)
                        act_row <= act_row + 3'd1;

                end


                // ============================================
                // START CAPTURE
                // ============================================

                S_WAIT_OUTPUT: begin

                    capture_diag <= 4'd0;

                end


                // ============================================
                // CAPTURE
                // ============================================

                S_CAPTURE: begin

                    if (capture_diag != 4'd14)
                        capture_diag <= capture_diag + 4'd1;

                end


                default: begin
                end

            endcase

        end

    end


    // ========================================================
    // OUTPUT CONTROL LOGIC
    //
    // Moore-style outputs based on current state.
    // ========================================================

    always @(*) begin

        // ----------------------------------------------------
        // DEFAULTS
        // ----------------------------------------------------

        busy = 1'b1;
        done = 1'b0;

        act_rd_en = 1'b0;
        act_rd_row = act_row;

        weight_rd_en = 1'b0;
        weight_rd_row = weight_row;
        weight_rd_col = weight_col;

        load_weight = 1'b0;
        load_weight_row = weight_row;
        load_weight_col = weight_col;

        clear_psum = 1'b0;
        mac_en = 1'b0;

        capture_en = 1'b0;
        diag_count = capture_diag;


        case (state)

            // =================================================
            // IDLE
            // =================================================

            S_IDLE: begin

                busy = 1'b0;

            end


            // =================================================
            // WEIGHT READ
            // =================================================

            S_WEIGHT_READ: begin

                busy = 1'b1;

                weight_rd_en  = 1'b1;
                weight_rd_row = weight_row;
                weight_rd_col = weight_col;

            end


            // =================================================
            // WEIGHT LOAD
            // =================================================

            S_WEIGHT_LOAD: begin

                busy = 1'b1;

                load_weight     = 1'b1;
                load_weight_row = weight_row;
                load_weight_col = weight_col;

            end


            // =================================================
            // CLEAR PSUM
            // =================================================

            S_CLEAR: begin

                busy = 1'b1;

                clear_psum = 1'b1;

            end


            // =================================================
            // COMPUTE
            // =================================================

            S_COMPUTE: begin

                busy = 1'b1;

                act_rd_en  = 1'b1;
                act_rd_row = act_row;

                mac_en = 1'b1;

            end


            // =================================================
            // WAIT FOR FIRST OUTPUT
            // =================================================

            S_WAIT_OUTPUT: begin

                busy = 1'b1;

                mac_en = 1'b1;

            end


            // =================================================
            // CAPTURE
            // =================================================

            S_CAPTURE: begin

                busy = 1'b1;

                mac_en = 1'b1;

                capture_en = 1'b1;
                diag_count = capture_diag;

            end


            // =================================================
            // DONE
            // =================================================

            S_DONE: begin

                busy = 1'b0;
                done = 1'b1;

            end


            default: begin

                busy = 1'b0;

            end

        endcase

    end

endmodule