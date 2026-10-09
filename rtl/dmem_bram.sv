// ============================================================
//  dmem_bram.sv  —  Dual-port data memory (224 KB)
//
//  Authoritative v4.0 Specification:
//    - 224 KiB contiguous data storage (57,344 × 32-bit words)
//    - Covers address range: 0x0000_8000 to 0x0003_FFFF
//        * 0x0000_8000 - 0x0000_FFFF : DMEM scratchpad (32 KiB)
//        * 0x0001_0000 - 0x0001_3FFF : INPUT buffer    (16 KiB)
//        * 0x0001_4000 - 0x0002_BFFF : WEIGHTS         (96 KiB)
//        * 0x0002_C000 - 0x0003_3FFF : FEATURE_A       (32 KiB)
//        * 0x0003_4000 - 0x0003_BFFF : FEATURE_B       (32 KiB)
//        * 0x0003_C000 - 0x0003_FFFF : OUTPUT          (16 KiB)
//
//  Port A : CPU  (read/write, byte-enable wstrb)
//  Port B : DMA  (read=wstrb=0000, write=wstrb=1111 only)
//
//  Both ports have 1-cycle registered latency on reads.
//  ready is asserted for exactly one cycle after valid.
//
//  Collision detection:
//    Both ports writing the same word address in the same
//    cycle → collision_error pulse (simulation assertion).
// ============================================================

`timescale 1ns/1ps

module dmem_bram #(
    parameter int WORDS = 57344, // 224 KB (57,344 × 32-bit words)
    parameter     WEIGHTS_FILE = "weights/cnn_weights.hex"
)(
    input  logic        clk,
    input  logic        rst_n,

    // ---- Port A : CPU -------------------------------------------
    input  logic        cpu_valid,
    input  logic [3:0]  cpu_wstrb,
    input  logic [17:0] cpu_addr, // Relative byte offset from 0x0000_8000
    input  logic [31:0] cpu_wdata,
    output logic [31:0] cpu_rdata,
    output logic        cpu_ready,

    // ---- Port B : DMA -------------------------------------------
    input  logic        dma_valid,
    input  logic [3:0]  dma_wstrb,
    input  logic [17:0] dma_addr, // Relative byte offset from 0x0000_8000
    input  logic [31:0] dma_wdata,
    output logic [31:0] dma_rdata,
    output logic        dma_ready,

    // ---- Collision detection (sim only) -------------------------
    output logic        collision_error
);
    // 57,344 × 32-bit = 224 KB BRAM storage
    (* ram_style = "block" *) logic [31:0] mem [0:WORDS-1];

    initial begin
        $readmemh(WEIGHTS_FILE, mem, 12288);
        cpu_rdata = 32'h0;
        dma_rdata = 32'h0;
    end

    logic cpu_op_pending;
    logic dma_op_pending;

    // ---- Collision: both ports writing same word address --------
    assign collision_error =
        cpu_valid && (cpu_wstrb != 4'b0000) && !cpu_ready &&
        dma_valid && (dma_wstrb != 4'b0000) && !dma_ready &&
        (cpu_addr[17:2] == dma_addr[17:2]);

    // ---- Control Registers (Handshake) --------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_op_pending <= 1'b0;
        end else begin
            if (cpu_valid && !cpu_ready) begin
                cpu_op_pending <= 1'b1;
            end else begin
                cpu_op_pending <= 1'b0;
            end
        end
    end
    assign cpu_ready = cpu_op_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_op_pending <= 1'b0;
        end else begin
            if (dma_valid && !dma_ready) begin
                dma_op_pending <= 1'b1;
            end else begin
                dma_op_pending <= 1'b0;
            end
        end
    end
    assign dma_ready = dma_op_pending;

    // ---- Port A (CPU) RAM Array Access --------------------------
    // Synchronous with NO reset — canonical UG901 BRAM template
    always_ff @(posedge clk) begin
        if (cpu_valid && !cpu_ready) begin
            if (cpu_wstrb[0]) mem[cpu_addr[17:2]][7:0]   <= cpu_wdata[7:0];
            if (cpu_wstrb[1]) mem[cpu_addr[17:2]][15:8]  <= cpu_wdata[15:8];
            if (cpu_wstrb[2]) mem[cpu_addr[17:2]][23:16] <= cpu_wdata[23:16];
            if (cpu_wstrb[3]) mem[cpu_addr[17:2]][31:24] <= cpu_wdata[31:24];
            cpu_rdata <= mem[cpu_addr[17:2]];
        end
    end

    // ---- Port B (DMA) RAM Array Access --------------------------
    // Synchronous with NO reset — canonical UG901 BRAM template
    always_ff @(posedge clk) begin
        if (dma_valid && !dma_ready) begin
            if (dma_wstrb[0]) mem[dma_addr[17:2]][7:0]   <= dma_wdata[7:0];
            if (dma_wstrb[1]) mem[dma_addr[17:2]][15:8]  <= dma_wdata[15:8];
            if (dma_wstrb[2]) mem[dma_addr[17:2]][23:16] <= dma_wdata[23:16];
            if (dma_wstrb[3]) mem[dma_addr[17:2]][31:24] <= dma_wdata[31:24];
            dma_rdata <= mem[dma_addr[17:2]];
        end
    end

endmodule
