# Vivado batch synthesis, placement, and routing script for HQC-128 PKE core
# Usage: vivado -mode batch -source scripts/run_impl.tcl

set TOP_MODULE "top_full"
set PART       "xc7a35tcsg324-1"
# To target Artix-7 xc7a200t-2, set PART "xc7a200tfbg676-2"

puts "== Creating in-memory project for ${TOP_MODULE} on ${PART} =="
create_project -in_memory -part ${PART}

add_files [glob hw/core/*.v]
add_files [glob hw/codec/*.v]
set_property include_dirs [list "hw/codec"] [current_fileset]
set_property top ${TOP_MODULE} [current_fileset]

# Synthesize out-of-context at 100 MHz (10.0 ns clock period)
synth_design -top ${TOP_MODULE} -part ${PART} -mode out_of_context
create_clock -period 10.000 -name clk [get_ports clk]

# Place and route
opt_design
place_design
phys_opt_design
route_design

# Generate utilization and timing reports
report_utilization -file reports/utilization_${PART}.rpt
report_timing_summary -file reports/timing_${PART}.rpt

puts "== Implementation completed for ${PART} =="
exit
