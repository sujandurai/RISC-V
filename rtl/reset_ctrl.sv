module reset_ctrl (
    input  logic clk,
    input  logic ext_reset_n,
    output logic sys_rst_n
);
    logic [1:0] sync_rst_n;
    
    // Asynchronous assertion, synchronous deassertion
    always_ff @(posedge clk or negedge ext_reset_n) begin
        if (!ext_reset_n) begin
            sync_rst_n <= 2'b00;
        end else begin
            sync_rst_n <= {sync_rst_n[0], 1'b1};
        end
    end
    
    assign sys_rst_n = sync_rst_n[1];
endmodule
