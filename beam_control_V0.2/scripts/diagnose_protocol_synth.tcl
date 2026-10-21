set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
create_project -in_memory -part xc7a200t-fbg484-1
read_verilog -sv [file join $project_dir rtl beam_cmd_pkg.sv]
read_verilog -sv [file join $project_dir rtl protocol_v02_controller.sv]
synth_design -top protocol_v02_controller -part xc7a200t-fbg484-1
puts "PROTOCOL_CONTROLLER_SYNTH_PASS"
