source "helpers.tcl"
source "flow_helpers.tcl"
source "Nangate45/Nangate45.vars"

set design "gcd"
set top_module "gcd"
set synth_verilog "gcd_nangate45.v"
set sdc_file "gcd_nangate45.sdc"
set die_area {0 0 100.13 100.8}
set core_area {10.07 11.2 90.25 91}

puts "=== PHASE 1: Initial load and full run ==="
read_libraries
read_verilog $synth_verilog
link_design $top_module
read_sdc $sdc_file

initialize_floorplan -site $site \
  -die_area $die_area \
  -core_area $core_area
source $tracks_file
remove_buffers
eval tapcell $tapcell_args
source $pdn_cfg
pdngen
global_placement -density $global_place_density \
  -pad_left $global_place_pad -pad_right $global_place_pad -skip_io

estimate_parasitics -placement
report_worst_slack -min -digits 3
report_worst_slack -max -digits 3
report_tns -digits 3

puts "=== PHASE 2: clear_design (retaining PDK) ==="
clear_design

puts "=== PHASE 3: Second run reusing cached PDK ==="
read_verilog $synth_verilog
link_design $top_module
read_sdc $sdc_file

initialize_floorplan -site $site \
  -die_area $die_area \
  -core_area $core_area
source $tracks_file
remove_buffers
eval tapcell $tapcell_args
source $pdn_cfg
pdngen
global_placement -density $global_place_density \
  -pad_left $global_place_pad -pad_right $global_place_pad -skip_io

estimate_parasitics -placement
report_worst_slack -min -digits 3
report_worst_slack -max -digits 3
report_tns -digits 3

puts "=== PHASE 4: clear_design again ==="
clear_design

puts "=== PHASE 5: Third run with different placement parameters (parameter exploration) ==="
read_verilog $synth_verilog
link_design $top_module
read_sdc $sdc_file

initialize_floorplan -site $site \
  -die_area $die_area \
  -core_area $core_area
source $tracks_file
remove_buffers
eval tapcell $tapcell_args
source $pdn_cfg
pdngen
global_placement -density 0.8 \
  -pad_left 3 -pad_right 3 -skip_io

estimate_parasitics -placement
report_worst_slack -min -digits 3
report_worst_slack -max -digits 3
report_tns -digits 3
puts "=== MULTIPHASE TEST PASSED SUCCESSFULLY ==="
