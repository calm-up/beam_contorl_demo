set root [file normalize [file join [file dirname [info script]] ..]]
set debug_enabled [expr {[info exists ::env(V03_ENABLE_ILA)] && $::env(V03_ENABLE_ILA) eq "1"}]
set flavor [expr {[info exists ::env(V03_BUILD_FLAVOR)] ?
    $::env(V03_BUILD_FLAVOR) : ($debug_enabled ? "debug" : "base")}]
set build_dir [file join $root build $flavor]
file mkdir $build_dir
create_project -force beam_control_v03 $build_dir -part xc7a200t-fbg484-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set sources [list \
    beam_cmd_pkg.sv array_write_engine.sv array_load_ctrl.sv \
    array_reset_ctrl.sv array_output_router.sv beam_ctrl_core.sv \
    uart_rx.sv channel_executor.sv protocol_v03_parser.sv \
    uart_tx_byte.sv protocol_v03_response.sv array_target_reset.sv \
    pulse_gate_110.sv u22_spi_master.sv u22_flash_probe.sv u22_flash_device.sv \
    u22_flash_record_service.sv \
    protocol_v03_dispatcher.sv beam_ctrl_top.sv]
foreach source $sources {
    add_files -norecurse [file join $root rtl $source]
}
set_property file_type SystemVerilog [get_files [file join $root rtl *.sv]]
set_property top beam_ctrl_top [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $root constr beam_ctrl.xdc]
add_files -fileset constrs_1 -norecurse [file join $root constr clock_route_impl.xdc]
set_property USED_IN_SYNTHESIS false [get_files [file join $root constr clock_route_impl.xdc]]
set_property target_constrs_file [file join $root constr beam_ctrl.xdc] [get_filesets constrs_1]
if {$debug_enabled} {
    source [file join $root scripts create_debug_ila.tcl]
    set_property generic {ENABLE_DEBUG_ILA=1} [get_filesets sources_1]
}
update_compile_order -fileset sources_1
puts "V03_PROJECT_CREATED flavor=$flavor root=$root"
close_project
