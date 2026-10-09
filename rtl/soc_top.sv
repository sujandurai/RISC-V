// ============================================================
//  soc_top.sv  —  Phase 4 Complete Edge-AI SoC Top-Level
//
//  Authoritative v4.0 Integration:
//    - PicoRV32 RV32IM core (native valid/ready bus)
//    - 32 KiB Instruction BRAM (imem_bram)
//    - 224 KiB Dual-Port Data BRAM (dmem_bram)
//    - System registers at 0x4000_0000 (sys_regs)
//    - Fixed 8×8 WS Systolic Accelerator Wrapper at 0x4000_0100 (acc_wrapper)
//    - Tile DMA Engine at 0x4000_0200 (dma_engine)
//    - PL UART at 0x4000_0300 (uart)
//    - Synchronous reset controller (reset_ctrl)
//    - Single 100 MHz clock domain
// ============================================================

`timescale 1ns/1ps

module soc_top #(
    parameter HEX_FILE     = "firmware/phase4_cnn.hex",
    parameter WEIGHTS_FILE = "weights/cnn_weights.hex"
)(
    input  logic clk_100m,
    input  logic ext_reset_n,
    input  logic uart_rx,
    output logic uart_tx
);

    logic sys_rst_n;
    reset_ctrl reset_inst (
        .clk(clk_100m),
        .ext_reset_n(ext_reset_n),
        .sys_rst_n(sys_rst_n)
    );
    
    // CPU signals
    logic        mem_valid;
    logic        mem_ready;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [3:0]  mem_wstrb;
    logic [31:0] mem_rdata;
    logic        mem_instr;
    
    logic cpu_trap;
    
    picorv32 #(
        .ENABLE_REGS_16_31(1),
        .ENABLE_REGS_DUALPORT(1),
        .ENABLE_COUNTERS(1),
        .ENABLE_COUNTERS64(1),
        .TWO_STAGE_SHIFT(1),
        .BARREL_SHIFTER(0),
        .COMPRESSED_ISA(0),
        .ENABLE_MUL(0),
        .ENABLE_FAST_MUL(1),
        .ENABLE_DIV(1),
        .ENABLE_IRQ(0),
        .CATCH_MISALIGN(1),
        .CATCH_ILLINSN(1),
        .PROGADDR_RESET(32'h0000_0000),
        .STACKADDR(32'h0000_FFF0)
    ) cpu (
        .clk(clk_100m),
        .resetn(sys_rst_n),
        
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        
        .trap(cpu_trap)
    );
    
    logic        imem_valid;
    logic        imem_ready;
    logic [31:0] imem_rdata;
    
    logic        dmem_valid;
    logic        dmem_ready;
    logic [31:0] dmem_rdata;
    
    logic        sys_valid;
    logic        sys_ready;
    logic [31:0] sys_rdata;
    
    logic        acc_valid;
    logic        acc_ready;
    logic [31:0] acc_rdata;
    
    logic        dma_mmio_valid;
    logic        dma_mmio_ready;
    logic [31:0] dma_mmio_rdata;

    logic        uart_mmio_valid;
    logic        uart_mmio_ready;
    logic [31:0] uart_mmio_rdata;

    logic        bus_error;
    
    native_interconnect ic (
        .clk(clk_100m),
        .rst_n(sys_rst_n),
        
        .cpu_valid(mem_valid),
        .cpu_ready(mem_ready),
        .cpu_addr(mem_addr),
        .cpu_wdata(mem_wdata),
        .cpu_wstrb(mem_wstrb),
        .cpu_rdata(mem_rdata),
        
        .imem_valid(imem_valid),
        .imem_ready(imem_ready),
        .imem_rdata(imem_rdata),
        
        .dmem_valid(dmem_valid),
        .dmem_ready(dmem_ready),
        .dmem_rdata(dmem_rdata),
        
        .sys_valid(sys_valid),
        .sys_ready(sys_ready),
        .sys_rdata(sys_rdata),
        
        .acc_valid(acc_valid),
        .acc_ready(acc_ready),
        .acc_rdata(acc_rdata),
        
        .dma_valid(dma_mmio_valid),
        .dma_ready(dma_mmio_ready),
        .dma_rdata(dma_mmio_rdata),

        .uart_valid(uart_mmio_valid),
        .uart_ready(uart_mmio_ready),
        .uart_rdata(uart_mmio_rdata),

        .bus_error(bus_error)
    );
    
    imem_bram #(
        .HEX_FILE(HEX_FILE)
    ) imem (
        .clk(clk_100m),
        .rst_n(sys_rst_n),
        .valid(imem_valid),
        .addr(mem_addr[14:0]),
        .rdata(imem_rdata),
        .ready(imem_ready)
    );
    
    // DMA data memory signals (Port B)
    logic        dma_mem_valid;
    logic [3:0]  dma_mem_wstrb;
    logic [31:0] dma_mem_addr;
    logic [31:0] dma_mem_wdata;
    logic [31:0] dma_mem_rdata;
    logic        dma_mem_ready;
    logic        dmem_collision;

    // Relative byte addresses from 0x0000_8000
    logic [17:0] dmem_cpu_addr;
    logic [17:0] dmem_dma_addr;

    assign dmem_cpu_addr = mem_addr[17:0] - 18'h08000;
    assign dmem_dma_addr = dma_mem_addr[17:0] - 18'h08000;

    dmem_bram #(
        .WEIGHTS_FILE(WEIGHTS_FILE)
    ) dmem (
        .clk(clk_100m),
        .rst_n(sys_rst_n),
        // Port A: CPU
        .cpu_valid(dmem_valid),
        .cpu_wstrb(mem_wstrb),
        .cpu_addr(dmem_cpu_addr),
        .cpu_wdata(mem_wdata),
        .cpu_rdata(dmem_rdata),
        .cpu_ready(dmem_ready),
        // Port B: DMA
        .dma_valid(dma_mem_valid),
        .dma_wstrb(dma_mem_wstrb),
        .dma_addr(dmem_dma_addr),
        .dma_wdata(dma_mem_wdata),
        .dma_rdata(dma_mem_rdata),
        .dma_ready(dma_mem_ready),
        .collision_error(dmem_collision)
    );
    
    logic clear_bus_error;
    
    sys_regs sys (
        .clk(clk_100m),
        .rst_n(sys_rst_n),
        .valid(sys_valid),
        .wstrb(mem_wstrb),
        .addr(mem_addr[7:0]),
        .wdata(mem_wdata),
        .rdata(sys_rdata),
        .ready(sys_ready),
        .cpu_trap_in(cpu_trap),
        .bus_error_in(bus_error),
        .clear_bus_error_out(clear_bus_error)
    );
    
    // DMA-Accelerator native signals
    logic        dma_owner_sig;
    logic        dma_acc_wr_en;
    logic        dma_acc_matrix_sel;
    logic [2:0]  dma_acc_wr_row;
    logic [2:0]  dma_acc_wr_col;
    logic [7:0]  dma_acc_wr_data;
    logic        dma_acc_rd_en;
    logic [5:0]  dma_acc_rd_addr;
    logic [31:0] dma_acc_rd_data;
    logic        dma_acc_rd_valid;

    acc_wrapper acc_wrap (
        .clk(clk_100m),
        .rst_n(sys_rst_n),
        .cpu_valid(acc_valid),
        .cpu_ready(acc_ready),
        .cpu_wstrb(mem_wstrb),
        .cpu_addr(mem_addr[7:0]),
        .cpu_wdata(mem_wdata),
        .cpu_rdata(acc_rdata),
        .dma_owner(dma_owner_sig),
        .dma_wr_en(dma_acc_wr_en),
        .dma_matrix_sel(dma_acc_matrix_sel),
        .dma_wr_row(dma_acc_wr_row),
        .dma_wr_col(dma_acc_wr_col),
        .dma_wr_data(dma_acc_wr_data),
        .dma_rd_en(dma_acc_rd_en),
        .dma_rd_addr(dma_acc_rd_addr),
        .dma_rd_data(dma_acc_rd_data),
        .dma_rd_valid(dma_acc_rd_valid)
    );

    // DMA Engine
    logic dma_busy_sig;
    logic dma_done_sig;
    logic dma_error_sig;

    dma_engine dma_inst (
        .clk(clk_100m),
        .rst_n(sys_rst_n),
        // MMIO slave
        .mmio_valid(dma_mmio_valid),
        .mmio_ready(dma_mmio_ready),
        .mmio_wstrb(mem_wstrb),
        .mmio_addr(mem_addr[7:0]),
        .mmio_wdata(mem_wdata),
        .mmio_rdata(dma_mmio_rdata),
        // DMEM Port B master
        .mem_valid(dma_mem_valid),
        .mem_wstrb(dma_mem_wstrb),
        .mem_addr(dma_mem_addr),
        .mem_wdata(dma_mem_wdata),
        .mem_rdata(dma_mem_rdata),
        .mem_ready(dma_mem_ready),
        // Accelerator master
        .dma_owner(dma_owner_sig),
        .acc_wr_en(dma_acc_wr_en),
        .acc_matrix_sel(dma_acc_matrix_sel),
        .acc_wr_row(dma_acc_wr_row),
        .acc_wr_col(dma_acc_wr_col),
        .acc_wr_data(dma_acc_wr_data),
        .acc_rd_en(dma_acc_rd_en),
        .acc_rd_addr(dma_acc_rd_addr),
        .acc_rd_data(dma_acc_rd_data),
        .acc_rd_valid(dma_acc_rd_valid),
        // Status
        .busy(dma_busy_sig),
        .done(dma_done_sig),
        .error(dma_error_sig)
    );
    
    // PL UART Peripheral (0x4000_0300)
    uart uart_inst (
        .clk(clk_100m),
        .rst_n(sys_rst_n),
        // External pins
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        // Native MMIO interface
        .mmio_valid(uart_mmio_valid),
        .mmio_ready(uart_mmio_ready),
        .mmio_wstrb(mem_wstrb),
        .mmio_addr(mem_addr[7:0]),
        .mmio_wdata(mem_wdata),
        .mmio_rdata(uart_mmio_rdata)
    );

endmodule
