// ============================================================
//  native_interconnect.sv  —  Phase 4 Native Bus Interconnect
//
//  Authoritative v4.0 Memory Map:
//    0x0000_0000 - 0x0000_7FFF : IMEM      (32 KiB)
//    0x0000_8000 - 0x0003_FFFF : DMEM      (224 KiB)
//        * 0x0000_8000 - 0x0000_FFFF : DMEM scratchpad (32 KiB)
//        * 0x0001_0000 - 0x0001_3FFF : INPUT           (16 KiB)
//        * 0x0001_4000 - 0x0002_BFFF : WEIGHTS         (96 KiB)
//        * 0x0002_C000 - 0x0003_3FFF : FEATURE_A       (32 KiB)
//        * 0x0003_4000 - 0x0003_BFFF : FEATURE_B       (32 KiB)
//        * 0x0003_C000 - 0x0003_FFFF : OUTPUT          (16 KiB)
//    0x4000_0000 - 0x4000_00FF : SYS MMIO  (256 B)
//    0x4000_0100 - 0x4000_01FF : ACC MMIO  (256 B)
//    0x4000_0200 - 0x4000_02FF : DMA MMIO  (256 B)
//    0x4000_0300 - 0x4000_03FF : UART MMIO (256 B)
//    All other addresses       : Invalid (bus_error, read=0)
// ============================================================

`timescale 1ns/1ps

module native_interconnect (
    input  logic        clk,
    input  logic        rst_n,

    // CPU interface
    input  logic        cpu_valid,
    output logic        cpu_ready,
    input  logic [31:0] cpu_addr,
    input  logic [31:0] cpu_wdata,
    input  logic [3:0]  cpu_wstrb,
    output logic [31:0] cpu_rdata,

    // IMEM interface
    output logic        imem_valid,
    input  logic        imem_ready,
    input  logic [31:0] imem_rdata,

    // DMEM interface (224 KiB contiguous)
    output logic        dmem_valid,
    input  logic        dmem_ready,
    input  logic [31:0] dmem_rdata,

    // SYS MMIO interface
    output logic        sys_valid,
    input  logic        sys_ready,
    input  logic [31:0] sys_rdata,

    // ACC MMIO interface
    output logic        acc_valid,
    input  logic        acc_ready,
    input  logic [31:0] acc_rdata,

    // DMA MMIO interface
    output logic        dma_valid,
    input  logic        dma_ready,
    input  logic [31:0] dma_rdata,

    // UART MMIO interface
    output logic        uart_valid,
    input  logic        uart_ready,
    input  logic [31:0] uart_rdata,

    // Bus error reporting
    output logic        bus_error
);
    // Address decoding
    logic sel_imem, sel_dmem, sel_sys;
    logic sel_acc, sel_dma, sel_uart;

    assign sel_imem = (cpu_addr >= 32'h0000_0000 && cpu_addr < 32'h0000_8000);
    assign sel_dmem = (cpu_addr >= 32'h0000_8000 && cpu_addr < 32'h0004_0000);
    assign sel_sys  = (cpu_addr >= 32'h4000_0000 && cpu_addr < 32'h4000_0100);
    assign sel_acc  = (cpu_addr >= 32'h4000_0100 && cpu_addr < 32'h4000_0200);
    assign sel_dma  = (cpu_addr >= 32'h4000_0200 && cpu_addr < 32'h4000_0300);
    assign sel_uart = (cpu_addr >= 32'h4000_0300 && cpu_addr < 32'h4000_0400);

    logic is_unmapped;
    assign is_unmapped = !(sel_imem || sel_dmem || sel_sys || sel_acc || sel_dma || sel_uart);

    logic is_unimplemented;
    assign is_unimplemented = 1'b0; // All v4.0 regions are now fully implemented

    logic unaligned;
    assign unaligned = (cpu_addr[1:0] != 2'b00);

    logic is_mmio;
    assign is_mmio = sel_sys || sel_acc || sel_dma || sel_uart;

    logic partial_mmio_write;
    assign partial_mmio_write = is_mmio && (cpu_wstrb != 4'b0000) && (cpu_wstrb != 4'b1111);

    logic access_fault;
    assign access_fault = is_unmapped || is_unimplemented || unaligned || partial_mmio_write;

    logic fault_pending;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_pending <= 1'b0;
        end else begin
            if (cpu_valid && access_fault && !fault_pending) begin
                fault_pending <= 1'b1;
            end else begin
                fault_pending <= 1'b0;
            end
        end
    end

    logic fault_ready;
    assign fault_ready = fault_pending;

    // Routing
    assign imem_valid = cpu_valid && sel_imem && !access_fault;
    assign dmem_valid = cpu_valid && sel_dmem && !access_fault;
    assign sys_valid  = cpu_valid && sel_sys  && !access_fault;
    assign acc_valid  = cpu_valid && sel_acc  && !access_fault;
    assign dma_valid  = cpu_valid && sel_dma  && !access_fault;
    assign uart_valid = cpu_valid && sel_uart && !access_fault;

    // Mux responses
    always_comb begin
        if (fault_ready) begin
            cpu_ready = 1'b1;
            cpu_rdata = 32'h0;
            bus_error = 1'b1;
        end else if (imem_ready) begin
            cpu_ready = 1'b1;
            cpu_rdata = imem_rdata;
            bus_error = 1'b0;
        end else if (dmem_ready) begin
            cpu_ready = 1'b1;
            cpu_rdata = dmem_rdata;
            bus_error = 1'b0;
        end else if (sys_ready) begin
            cpu_ready = 1'b1;
            cpu_rdata = sys_rdata;
            bus_error = 1'b0;
        end else if (acc_ready) begin
            cpu_ready = 1'b1;
            cpu_rdata = acc_rdata;
            bus_error = 1'b0;
        end else if (dma_ready) begin
            cpu_ready = 1'b1;
            cpu_rdata = dma_rdata;
            bus_error = 1'b0;
        end else if (uart_ready) begin
            cpu_ready = 1'b1;
            cpu_rdata = uart_rdata;
            bus_error = 1'b0;
        end else begin
            cpu_ready = 1'b0;
            cpu_rdata = 32'h0;
            bus_error = 1'b0;
        end
    end

endmodule
