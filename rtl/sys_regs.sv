module sys_regs (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        valid,
    input  logic [3:0]  wstrb,
    input  logic [7:0]  addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,
    output logic        ready,
    
    // Status inputs
    input  logic        cpu_trap_in,
    input  logic        bus_error_in,
    // Control outputs
    output logic        clear_bus_error_out
);
    
    logic [31:0] cycle_counter;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_counter <= 32'h0;
        else cycle_counter <= cycle_counter + 1;
    end
    
    logic sticky_cpu_trap;
    logic sticky_bus_error;
    
    // Write side effect processing
    logic do_clear_bus_error;
    logic do_clear_cpu_trap;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sticky_cpu_trap <= 1'b0;
            sticky_bus_error <= 1'b0;
        end else begin
            if (cpu_trap_in) sticky_cpu_trap <= 1'b1;
            else if (do_clear_cpu_trap) sticky_cpu_trap <= 1'b0;
            
            if (bus_error_in) sticky_bus_error <= 1'b1;
            else if (do_clear_bus_error) sticky_bus_error <= 1'b0;
        end
    end

    logic op_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_pending <= 1'b0;
            rdata <= 32'h0;
            do_clear_bus_error <= 1'b0;
            do_clear_cpu_trap <= 1'b0;
        end else begin
            // Default pulse to 0
            do_clear_bus_error <= 1'b0;
            do_clear_cpu_trap <= 1'b0;
            
            if (valid && !ready) begin
                op_pending <= 1'b1;
                
                // Reads
                if (wstrb == 4'b0000) begin
                    case (addr)
                        8'h00: rdata <= 32'hA5A5_0001; // SYS_ID
                        8'h04: rdata <= {27'h0, 1'b0 /* DMA_ERROR */, 1'b0 /* ACC_FAULT */, sticky_cpu_trap, sticky_bus_error, 1'b1 /* READY */};
                        8'h0C: rdata <= cycle_counter;
                        default: rdata <= 32'h0;
                    endcase
                end 
                // Writes (full-word only)
                else if (wstrb == 4'b1111) begin
                    if (addr == 8'h08) begin
                        do_clear_bus_error <= wdata[1];
                        do_clear_cpu_trap <= wdata[2];
                    end
                end
            end else begin
                op_pending <= 1'b0;
            end
        end
    end
    
    assign ready = op_pending;
    assign clear_bus_error_out = do_clear_bus_error;

endmodule
