`timescale 1ns/1ps

module phase2_accel_tb;
    
    logic clk;
    logic rst_n;
    
    logic start;
    logic busy;
    logic done;
    
    logic        wr_en;
    logic        matrix_select;
    logic [2:0]  wr_row;
    logic [2:0]  wr_col;
    logic signed [7:0] wr_data;
    
    logic        rd_en;
    logic [5:0]  rd_addr;
    logic signed [31:0] rd_data;
    logic        rd_valid;
    
    accelerator #(
        .DW(8),
        .AW(32)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .wr_en(wr_en),
        .matrix_select(matrix_select),
        .wr_row(wr_row),
        .wr_col(wr_col),
        .wr_data(wr_data),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rd_valid(rd_valid)
    );
    
    // =========================================================
    // Clock: 10 ns period (100 MHz)
    // =========================================================
    initial clk = 0;
    always #5 clk = ~clk;
    
    // =========================================================
    // Global watchdog: 500,000 ns = 50,000 cycles max
    // =========================================================
    initial begin
        #500000;
        $display("FATAL: Watchdog timeout — simulation stuck");
        $finish;
    end
    
    // Global variables for tests
    logic signed [7:0]  A_mat [0:7][0:7];
    logic signed [7:0]  B_mat [0:7][0:7];
    logic signed [31:0] expected_C [0:7][0:7];
    
    integer r, c, k;
    integer start_time, end_time;
    integer tests_passed = 0;
    
    // =========================================================
    // Task: load_matrix
    //   sel=0 → A (activations), sel=1 → B (weights)
    // =========================================================
    task load_matrix(input logic sel);
        integer ri, ci;
        begin
            for (ri = 0; ri < 8; ri = ri + 1) begin
                for (ci = 0; ci < 8; ci = ci + 1) begin
                    @(posedge clk);
                    wr_en         <= 1;
                    matrix_select <= sel;
                    wr_row        <= ri[2:0];
                    wr_col        <= ci[2:0];
                    wr_data       <= (sel == 0) ? A_mat[ri][ci] : B_mat[ri][ci];
                end
            end
            @(posedge clk);
            wr_en <= 0;
        end
    endtask
    
    // =========================================================
    // Task: compute_expected  (reference SW model)
    // =========================================================
    task compute_expected();
        integer ri, ci, ki;
        begin
            for (ri = 0; ri < 8; ri = ri + 1)
                for (ci = 0; ci < 8; ci = ci + 1) begin
                    expected_C[ri][ci] = 0;
                    for (ki = 0; ki < 8; ki = ki + 1)
                        expected_C[ri][ci] = expected_C[ri][ci]
                                           + (A_mat[ri][ki] * B_mat[ki][ci]);
                end
        end
    endtask
    
    // =========================================================
    // Task: read_result  — read one output word
    //   output_buffer has 1-cycle registered read latency:
    //     cycle N  : rd_en=1, rd_addr=X  → sampled on posedge N
    //     cycle N+1: rd_valid=1, rd_data = bank[X]
    // =========================================================
    task read_result(
        input  [5:0]  addr,
        output [31:0] data
    );
        begin
            @(posedge clk);
            rd_en   <= 1;
            rd_addr <= addr;
            @(posedge clk);           // data_valid registered here
            rd_en <= 0;
            // rd_valid is now driven by the registered rd_en from last posedge
            // Give one more clock edge if still not valid (guard)
            if (!rd_valid) @(posedge clk);
            data = rd_data;
        end
    endtask
    
    // =========================================================
    // Task: run_test
    // =========================================================
    task run_test(input string label);
        logic [31:0] got;
        begin
            compute_expected();
            load_matrix(0);   // A
            load_matrix(1);   // B
            
            // Assert start for one cycle
            @(posedge clk);
            start <= 1;
            @(posedge clk);
            start <= 0;
            
            start_time = $time;
            
            // Wait for done
            @(posedge done);
            end_time = $time;
            
            // Allow one settle cycle after done
            @(posedge clk);
            
            // Read and verify all 64 outputs
            for (r = 0; r < 8; r = r + 1) begin
                for (c = 0; c < 8; c = c + 1) begin
                    read_result((r * 8) + c, got);
                    if (got !== expected_C[r][c]) begin
                        $display("FAIL [%s] C[%0d][%0d]: expected=%0d got=%0d",
                                 label, r, c, expected_C[r][c], got);
                        $finish;
                    end
                end
            end
            
            tests_passed = tests_passed + 1;
            $display("PASS [%s]  latency=%0d ns", label, end_time - start_time);
        end
    endtask
    
    // =========================================================
    // Main stimulus
    // =========================================================
    initial begin
        $dumpfile("sim/phase2_accel.vcd");
        $dumpvars(0, phase2_accel_tb);
        
        // Initialise
        start         = 0;
        wr_en         = 0;
        rd_en         = 0;
        rst_n         = 0;
        matrix_select = 0;
        wr_row        = 0;
        wr_col        = 0;
        wr_data       = 0;
        rd_addr       = 0;
        
        // Reset for 10 clock cycles
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(2)  @(posedge clk);
        
        // -------------------------------------------------------
        // Test 1: Zero matrices  → C = all zeros
        // -------------------------------------------------------
        for (r=0; r<8; r=r+1) for (c=0; c<8; c=c+1) begin
            A_mat[r][c] = 0; B_mat[r][c] = 0;
        end
        run_test("zero");
        
        // -------------------------------------------------------
        // Test 2: Identity A, all-ones B → C = B (all 1s)
        // -------------------------------------------------------
        for (r=0; r<8; r=r+1) for (c=0; c<8; c=c+1) begin
            A_mat[r][c] = (r == c) ? 8'sd1 : 8'sd0;
            B_mat[r][c] = 8'sd1;
        end
        run_test("identity");
        
        // -------------------------------------------------------
        // Test 3: Max-magnitude  A=-128, B=127
        //         Expected: -128*127*8 = -130,048  (fits INT32)
        // -------------------------------------------------------
        for (r=0; r<8; r=r+1) for (c=0; c<8; c=c+1) begin
            A_mat[r][c] = -8'sd128;
            B_mat[r][c] =  8'sd127;
        end
        run_test("max_neg");
        
        // -------------------------------------------------------
        // Test 4-8: Five random matrices
        // -------------------------------------------------------
        begin : rand_loop
            integer t;
            for (t = 0; t < 5; t = t + 1) begin
                for (r=0; r<8; r=r+1)
                    for (c=0; c<8; c=c+1) begin
                        A_mat[r][c] = $random;
                        B_mat[r][c] = $random;
                    end
                run_test("random");
            end
        end
        
        $display("========================================");
        $display("   STANDALONE ACCELERATOR REGRESSION    ");
        $display("              ALL PASS                  ");
        $display("       Tests passed: %0d / 8            ", tests_passed);
        $display("========================================");
        $finish;
    end

endmodule
