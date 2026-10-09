// ============================================================
//  phase3_matrix_tb.sv  —  Phase 3 Full SoC Matrix Integration Testbench
//
//  Tests complete CPU-driven flow:
//    PicoRV32 executing firmware/phase3_matrix.hex
//    → DMA configuration
//    → ACT_LOAD (64 bytes)
//    → WEIGHT_LOAD (64 bytes)
//    → Explicit CPU Accelerator START
//    → Fixed IP Execution & DONE
//    → DMA RESULT_STORE (256 bytes)
//    → CPU verification of all 64 INT32 results
//    → PASS marker (0x900D0001) written to 0x0000_8180
// ============================================================

`timescale 1ns/1ps

module phase3_matrix_tb;

    logic clk;
    logic rst_n;
    logic uart_rx;
    logic uart_tx;

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    soc_top #(
        .HEX_FILE("firmware/phase3_matrix.hex")
    ) dut (
        .clk_100m   (clk),
        .ext_reset_n(rst_n),
        .uart_rx    (uart_rx),
        .uart_tx    (uart_tx)
    );

    initial begin
        if ($test$plusargs("DUMP")) begin
            $dumpfile("phase3_matrix.vcd");
            $dumpvars(1, phase3_matrix_tb);
            $dumpvars(1, dut);
        end

        uart_rx = 1'b1;
        rst_n   = 1'b0;
        #100;
        rst_n   = 1'b1;
        $display("[SoC TB] Reset released. PicoRV32 executing phase3_matrix firmware...");

        // Safety simulation timeout (100,000 cycles = 1 ms)
        #1000000;
        $display("[SoC TB] FAIL: Simulation watchdog timeout reached (1,000,000 ns)");
        $finish;
    end

    // Monitor DMEM writes for PASS/FAIL markers
    always @(posedge clk) begin
        if (dut.mem_valid && dut.mem_ready && (dut.mem_wstrb == 4'b1111)) begin
            if (dut.mem_addr == 32'h0000_8180) begin
                if (dut.mem_wdata == 32'h900D_0001) begin
                    $display("\n========================================================");
                    $display("                  PHASE3_MATRIX_PASS                    ");
                    $display("========================================================");
                    $display("  All 64 INT32 matrix multiplication results bit-exact!");
                    $display("  Firmware successfully orchestrated DMA + Accelerator flow.");
                    $display("  PASS marker 0x900D0001 confirmed at DMEM address 0x8180.");
                    $display("  Total execution time: %0d ns (%0d cycles)", $time, $time / 10);
                    $display("========================================================\n");
                    $finish;
                end else if (dut.mem_wdata == 32'hBAD0_0001) begin
                    $display("\n========================================================");
                    $display("                  PHASE3_MATRIX_FAIL                    ");
                    $display("========================================================");
                    $display("  FAIL marker 0xBAD00001 written to 0x8180.");
                    $display("  Matrix results did not match expected values.");
                    $display("========================================================\n");
                    $finish;
                end
            end
        end
    end

    // Assertions and monitors
    always @(posedge clk) begin
        if (rst_n) begin
            // Check for illegal CPU/DMA memory write collision
            if (dut.dmem_collision) begin
                $display("[ASSERTION FAILED] CPU and DMA simultaneous write collision at time %0t!", $time);
            end

            // Check for sticky bus errors
            if (dut.bus_error) begin
                $display("[WARNING] Native interconnect reported bus error at cycle %0d", $time/10);
            end
        end
    end

    // Bus hang watchdog
    integer stall_counter = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) stall_counter <= 0;
        else begin
            if (dut.mem_valid && !dut.mem_ready) begin
                stall_counter <= stall_counter + 1;
                if (stall_counter > 20) begin
                    $display("[ASSERTION FAILED] Permanent CPU bus stall detected (>20 cycles) at addr=0x%08x", dut.mem_addr);
                    $finish;
                end
            end else begin
                stall_counter <= 0;
            end
        end
    end

endmodule
