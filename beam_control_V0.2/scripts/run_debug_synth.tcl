set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set report_dir  [file join $project_dir reports]
set vio_xci     [file join $project_dir build debug_ip debug_ip_project.srcs sources_1 ip vio_debug vio_debug.xci]
set build_dir   [file join $project_dir build debug_vio_synth]
file mkdir $report_dir

if {![file exists $vio_xci]} {
    error "VIO IP is missing; run create_debug_vio.tcl first: $vio_xci"
}

create_project -force debug_vio_synth $build_dir -part xc7a200t-fbg484-1
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
add_files -norecurse $vio_xci
set_property generate_synth_checkpoint false [get_files $vio_xci]
generate_target synthesis [get_ips vio_debug]
update_compile_order -fileset sources_1
synth_design -top beam_ctrl_top -part xc7a200t-fbg484-1 \
    -generic ENABLE_DEBUG_VIO=1
report_utilization -file [file join $report_dir debug_vio_utilization.rpt]

set vio_cells [get_cells -hier -filter {REF_NAME =~ vio_debug*}]
if {[llength $vio_cells] == 0} {
    error "Debug build did not retain a vio_debug instance"
}
puts "DEBUG_VIO_SYNTH_PASS cells=[llength $vio_cells] ports=[llength [get_ports]]"
