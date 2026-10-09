module phase1_tb;

    logic clk;
    logic rst_n;
    logic uart_rx;
    logic uart_tx;

    soc_top dut (
        .clk_100m(clk),
        .ext_reset_n(rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end

    initial begin
        $dumpfile("phase1.vcd");
        $dumpvars(0, phase1_tb);
        
        uart_rx = 1;
        rst_n = 0;
        #100;
        rst_n = 1;
        
        // Wait for PASS marker write
        #5000;
        $display("FAIL: Simulation did not reach PASS marker");
        $finish;
    end

    // Monitor memory writes to detect the PASS marker
    always @(posedge clk) begin
        if (dut.mem_valid && dut.mem_ready && dut.mem_wstrb == 4'b1111) begin
            if (dut.mem_addr == 32'h0000_8004 && dut.mem_wdata == 32'h50415353) begin
                $display("========================================");
                $display("           PHASE1_PASS                  ");
                $display("========================================");
                $display("Cycle count: %0d", dut.sys.cycle_counter);
                $finish;
            end
        end
    end

    // Assertions
    // Valid transaction must complete within 10 cycles
    integer stall_counter;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) stall_counter <= 0;
        else begin
            if (dut.mem_valid && !dut.mem_ready) stall_counter <= stall_counter + 1;
            else stall_counter <= 0;
            
            if (stall_counter > 10) begin
                $display("FAIL: ASSERTION FAILED: Permanent bus stall detected");
                $finish;
            end
        end
    end

endmodule
