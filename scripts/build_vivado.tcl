# ============================================================
#  scripts/build_vivado.tcl — Non-Project Mode Synthesis & P&R
#
#  Target Device: AMD/Xilinx Zynq-7000 XC7Z020-CLG484-1 (ZedBoard)
#  Top Module: soc_top
# ============================================================

# Resolve base directory from script location and cd into it
# This avoids path-with-spaces issues in Vivado Tcl commands
set script_path [file normalize [info script]]
set base_dir [file dirname [file dirname $script_path]]
puts "Base directory: $base_dir"
cd $base_dir

set output_dir [file normalize "build"]
set report_dir [file normalize "reports"]
file mkdir $output_dir
file mkdir $report_dir

set_part xc7z020clg484-1

# Read Verilog and SystemVerilog RTL sources (relative paths — no spaces)
read_verilog rtl/picorv32.v
read_verilog rtl/pe.v
read_verilog rtl/weight_buffer.v
read_verilog rtl/activation_buffer.v
read_verilog rtl/output_buffer.v
read_verilog rtl/skew.v
read_verilog rtl/controller.v
read_verilog rtl/data_path.v
read_verilog rtl/systolic_8x8.v
read_verilog rtl/accelerator_top.v

read_verilog -sv rtl/imem_bram.sv
read_verilog -sv rtl/dmem_bram.sv
read_verilog -sv rtl/reset_ctrl.sv
read_verilog -sv rtl/sys_regs.sv
read_verilog -sv rtl/acc_wrapper.sv
read_verilog -sv rtl/dma_engine.sv
read_verilog -sv rtl/uart.sv
read_verilog -sv rtl/native_interconnect.sv
read_verilog -sv rtl/soc_top.sv

# Read Constraints
read_xdc constraints/zedboard.xdc

# ------------------------------------------------------------
# 1. Synthesis
# ------------------------------------------------------------
puts "============================================================"
puts "  STARTING SYNTHESIS: soc_top (Target: xc7z020clg484-1)"
puts "============================================================"
synth_design -top soc_top -part xc7z020clg484-1 -fanout_limit 200

write_checkpoint -force "$output_dir/post_synth.dcp"
report_utilization -file "$report_dir/synth_utilization.rpt"
report_timing_summary -file "$report_dir/synth_timing.rpt"

# ------------------------------------------------------------
# 2. Logic Optimization & Placement
# ------------------------------------------------------------
puts "============================================================"
puts "  STARTING LOGIC OPTIMIZATION & PLACEMENT"
puts "============================================================"
opt_design
place_design
phys_opt_design
write_checkpoint -force "$output_dir/post_place.dcp"
report_clock_utilization -file "$report_dir/clock_utilization.rpt"

# ------------------------------------------------------------
# 3. Routing
# ------------------------------------------------------------
puts "============================================================"
puts "  STARTING ROUTING"
puts "============================================================"
route_design
phys_opt_design
write_checkpoint -force "$output_dir/post_route.dcp"

# ------------------------------------------------------------
# 4. Final Reports (Post-Route)
# ------------------------------------------------------------
puts "============================================================"
puts "  GENERATING POST-ROUTE REPORTS"
puts "============================================================"
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -file "$report_dir/timing_summary.rpt"
report_utilization -file "$report_dir/utilization.rpt"
report_utilization -hierarchical -file "$report_dir/utilization_hierarchical.rpt"
report_power -file "$report_dir/power.rpt"
report_drc -file "$report_dir/drc.rpt"

# ------------------------------------------------------------
# 5. Bitstream Generation
# ------------------------------------------------------------
puts "============================================================"
puts "  GENERATING BITSTREAM: $output_dir/soc_top.bit"
puts "============================================================"
write_bitstream -force "$output_dir/soc_top.bit"

puts "============================================================"
puts "  BUILD COMPLETED SUCCESSFULLY!"
puts "============================================================"
