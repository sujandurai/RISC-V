# ============================================================
#  constraints/zedboard.xdc — Physical & Timing Constraints
#
#  Target Board: Digilent ZedBoard (Rev D/E/F)
#  Target Device: AMD/Xilinx Zynq-7000 XC7Z020-CLG484-1
#  Design: PL-Only RISC-V SoC with 8x8 WS Systolic Accelerator
# ============================================================

# ------------------------------------------------------------
# 1. Primary Clock (100 MHz Oscillator on Pin Y9, Bank 13)
# ------------------------------------------------------------
set_property PACKAGE_PIN Y9 [get_ports clk_100m]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100m]

# Authoritative Specification v4.0 Section 11.1 Timing Constraint:
create_clock -period 10.000 -name clk_100m [get_ports clk_100m]

# ------------------------------------------------------------
# 2. System Reset (Active-Low ext_reset_n)
#    Mapped to SW0 (Pin F22, Bank 35, 2.5V/3.3V)
#    Switch UP (1) = Normal Run, Switch DOWN (0) = Reset Asserted
# ------------------------------------------------------------
set_property PACKAGE_PIN F22 [get_ports ext_reset_n]
set_property IOSTANDARD LVCMOS33 [get_ports ext_reset_n]
set_property PULLUP true [get_ports ext_reset_n]

# ------------------------------------------------------------
# 3. PL UART Peripheral (115200 baud, 8N1, 3.3V on Pmod JA, Bank 13)
#    JA1 (Pin Y11)  = uart_rx (Board Input from Host USB-UART TX)
#    JA2 (Pin AA11) = uart_tx (Board Output to Host USB-UART RX)
# ------------------------------------------------------------
set_property PACKAGE_PIN Y11 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
set_property PULLUP true [get_ports uart_rx]

set_property PACKAGE_PIN AA11 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property DRIVE 8 [get_ports uart_tx]
set_property SLEW SLOW [get_ports uart_tx]

# ------------------------------------------------------------
# 4. Timing Exceptions & CDC Rules
#    v4.0 Rule: No false-path exception may hide the UART RX synchronizer.
# ------------------------------------------------------------
# Set input/output delays relative to 100 MHz clock for I/O ports
set_input_delay -clock clk_100m -max 3.000 [get_ports {ext_reset_n uart_rx}]
set_input_delay -clock clk_100m -min 0.500 [get_ports {ext_reset_n uart_rx}]
set_output_delay -clock clk_100m -max 3.000 [get_ports uart_tx]
set_output_delay -clock clk_100m -min 0.500 [get_ports uart_tx]

# UART TX is asynchronous serial at 115200 baud to external USB-UART adapter
set_false_path -to [get_ports uart_tx]

# Accelerator local reset is asserted for 5 full clock cycles by software FSM
# and is functionally a multicycle control path to 3,721 PE/buffer registers.
set_multicycle_path 2 -setup -from [get_cells -hier *acc_local_rst_n_reg*]
set_multicycle_path 1 -hold  -from [get_cells -hier *acc_local_rst_n_reg*]

# Configuration options for bitstream generation
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
