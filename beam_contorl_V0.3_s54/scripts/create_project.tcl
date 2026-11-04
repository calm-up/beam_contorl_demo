set root [file normalize [file join [file dirname [info script]] ..]]
set debug_enabled 1
set flavor s54
set build_dir [file join $root build $flavor]
file mkdir $build_dir
create_project -force beam_control_v03 $build_dir -part xc7a200t-fbg484-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set sources [list \
    beam_cmd_pkg.sv beam_phase_rom.sv beam_formula_calc.sv beam_phase_calc.sv \
    array_write_engine.sv array_load_ctrl.sv \
    array_reset_ctrl.sv array_output_router.sv beam_ctrl_core.sv \
    uart_rx.sv channel_executor.sv protocol_v03_parser.sv \
    uart_tx_byte.sv protocol_v03_response.sv array_target_reset.sv \
    pulse_gate_110.sv u22_spi_master.sv u22_flash_probe.sv u22_flash_device.sv \
    u22_flash_record_service.sv \
    protocol_v03_dispatcher.sv protocol_v03_rs485_port.sv \
    chip_sdo_reader.sv beam_ctrl_top.sv]
foreach source $sources {
    add_files -norecurse [file join $root rtl $source]
}
foreach source {tri_fun.v cal_formula.v} {
    add_files -norecurse [file join $root reference bjn110_cal_phase $source]
}
add_files -norecurse [file join $root rtl rom tri.mem]
set_property file_type SystemVerilog [get_files [file join $root rtl *.sv]]
set_property top beam_ctrl_top [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $root constr beam_ctrl.xdc]
add_files -fileset constrs_1 -norecurse [file join $root constr clock_route_impl.xdc]
set_property USED_IN_SYNTHESIS false [get_files [file join $root constr clock_route_impl.xdc]]
set_property target_constrs_file [file join $root constr beam_ctrl.xdc] [get_filesets constrs_1]
if {$debug_enabled} {
    source [file join $root scripts create_debug_ila.tcl]
}
set generics [list LDB_LOW_CYCLES=5]
if {$debug_enabled} {lappend generics ENABLE_DEBUG_ILA=1}
if {[llength $generics] > 0} {
    set_property generic $generics [get_filesets sources_1]
}
add_files -fileset sim_1 -norecurse [file join $root sim tb_protocol_v03_top.sv]
set_property top tb_protocol_v03_top [get_filesets sim_1]
set_property top_auto_set false [get_filesets sim_1]
set_property generic {} [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
set_property xsim.elaborate.debug_level all [get_filesets sim_1]
set_property xsim.simulate.log_all_signals true [get_filesets sim_1]
file mkdir [file join $build_dir beam_control_v03.sim sim_1 behav xsim rtl rom]
file copy -force [file join $root rtl rom tri.mem] [file join $build_dir beam_control_v03.sim sim_1 behav xsim rtl rom tri.mem]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
source [file join $root scripts setup_s54_periodic_sim.tcl]
source [file join $root scripts setup_s54_continuous_sim.tcl]
puts "V03_PROJECT_CREATED flavor=$flavor root=$root"
close_project
