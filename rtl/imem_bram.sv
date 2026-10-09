module imem_bram #(
    parameter HEX_FILE = "firmware/phase1.hex"
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        valid,
    input  logic [14:0] addr,
    output logic [31:0] rdata,
    output logic        ready
);
    // 8192 words x 32-bit = 32 KB
    (* ram_style = "block" *) logic [31:0] mem [0:8191];

    initial begin
        $readmemh(HEX_FILE, mem);
    end

    logic read_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_pending <= 1'b0;
        end else begin
            if (valid && !ready) begin
                read_pending <= 1'b1;
            end else begin
                read_pending <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (valid && !ready) begin
            rdata <= mem[addr[14:2]];
        end
    end
    
    assign ready = read_pending;
endmodule
