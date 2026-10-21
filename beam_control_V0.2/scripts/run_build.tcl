set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set report_dir  [file join $project_dir reports]
file mkdir $report_dir

create_project -in_memory -part xc7a200t-fbg484-1
set_msg_config -id {Synth 8-3917} -suppress
read_verilog -sv [file join $project_dir rtl beam_cmd_pkg.sv]
read_verilog -sv [file join $project_dir rtl array_write_engine.sv]
read_verilog -sv [file join $project_dir rtl array_load_ctrl.sv]
read_verilog -sv [file join $project_dir rtl array_reset_ctrl.sv]
read_verilog -sv [file join $project_dir rtl array_output_router.sv]
read_verilog -sv [file join $project_dir rtl beam_ctrl_core.sv]
read_verilog -sv [file join $project_dir rtl uart_rx.sv]
read_verilog -sv [file join $project_dir rtl protocol_v02_parser.sv]
read_verilog -sv [file join $project_dir rtl protocol_v02_controller.sv]
read_verilog -sv [file join $project_dir rtl debug_command_adapter.sv]
read_verilog -sv [file join $project_dir rtl debug_vio_bridge.sv]
read_verilog -sv [file join $project_dir rtl beam_ctrl_top.sv]
synth_design -top beam_ctrl_top -part xc7a200t-fbg484-1
read_xdc [file join $project_dir constr beam_ctrl.xdc]
write_checkpoint -force [file join $report_dir step3_post_synth.dcp]

set ports_without_pin {}
set ports_without_standard {}
foreach port [get_ports] {
    if {[get_property PACKAGE_PIN $port] eq ""} { lappend ports_without_pin $port }
    if {[get_property IOSTANDARD $port] eq "DEFAULT"} { lappend ports_without_standard $port }
}
if {[llength $ports_without_pin] != 0} {
    error "Ports without PACKAGE_PIN: $ports_without_pin"
}
if {[llength $ports_without_standard] != 0} {
    error "Ports without explicit IOSTANDARD: $ports_without_standard"
}

report_drc -file [file join $report_dir post_synth_drc.rpt]
report_io -file [file join $report_dir post_synth_io.rpt]
report_clocks -file [file join $report_dir post_synth_clocks.rpt]
check_timing -verbose -file [file join $report_dir post_synth_check_timing.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $report_dir post_synth_timing_summary.rpt]
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_high_fanout_nets -timing -load_types -max_nets 25 \
    -file [file join $report_dir post_synth_high_fanout.rpt]

set critical_drc [get_drc_violations -filter {SEVERITY == Error || SEVERITY == Critical_Warning}]
puts "STEP3_SYNTH_STATUS complete"
puts "STEP3_PART [get_property PART [current_design]]"
puts "STEP3_TOP [get_property TOP [current_design]]"
puts "STEP3_USER_PORTS [llength [get_ports]]"
puts "STEP3_PACKAGE_PIN_COUNT [expr {[llength [get_ports]] - [llength $ports_without_pin]}]"
puts "STEP3_IOSTANDARD_COUNT [expr {[llength [get_ports]] - [llength $ports_without_standard]}]"
puts "STEP3_CRITICAL_DRC [llength $critical_drc]"
foreach item $critical_drc { puts "STEP3_DRC_ITEM $item" }
