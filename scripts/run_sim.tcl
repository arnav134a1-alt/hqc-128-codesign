# Vivado batch simulation runner for HQC-128 PKE accelerator
# Usage: vivado -mode batch -source scripts/run_sim.tcl

set PROJECT_NAME "hqc_pke_sim"
set TOP_MODULE   "tb_top_full"
set PART         "xc7a35tcsg324-1"

puts "== Creating in-memory project for ${TOP_MODULE} =="
create_project -in_memory -part ${PART}

# Add core, AXI bridge, and RS-RM codec RTL
add_files [glob hw/core/*.v]
add_files [glob hw/axi/*.v]
add_files [glob hw/codec/*.v]
set_property include_dirs [list "hw/codec"] [get_filesets sources_1]
set_property include_dirs [list "hw/codec"] [get_filesets sim_1]

# Add testbench and simulation vector memory files
add_files -fileset sim_1 hw/tb/${TOP_MODULE}.v
add_files -fileset sim_1 [glob sim/vectors/*.mem]
set_property top ${TOP_MODULE} [get_filesets sim_1]

# Set simulation parameters
set_property -name {xsim.simulate.runtime} -value {1000us} -objects [get_filesets sim_1]

# Run behavioral simulation
puts "== Launching XSim =="
launch_simulation -simset sim_1 -mode behavioral

puts "== Simulation completed =="
exit
