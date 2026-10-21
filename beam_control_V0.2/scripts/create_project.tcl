set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set build_dir   [file join $project_dir build vivado]
set part_name   xc7a200t-fbg484-1

file mkdir $build_dir
create_project -force beam_control $build_dir -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]

add_files -fileset sources_1 -norecurse [list \
    [file join $project_dir rtl beam_cmd_pkg.sv] \
    [file join $project_dir rtl array_write_engine.sv] \
    [file join $project_dir rtl array_load_ctrl.sv] \
    [file join $project_dir rtl array_reset_ctrl.sv] \
    [file join $project_dir rtl array_output_router.sv] \
    [file join $project_dir rtl beam_ctrl_core.sv] \
    [file join $project_dir rtl uart_rx.sv] \
    [file join $project_dir rtl protocol_v02_parser.sv] \
    [file join $project_dir rtl protocol_v02_controller.sv] \
    [file join $project_dir rtl debug_command_adapter.sv] \
    [file join $project_dir rtl debug_vio_bridge.sv] \
    [file join $project_dir rtl beam_ctrl_top.sv]]
set_property file_type SystemVerilog [get_files [file join $project_dir rtl *.sv]]
set_property top beam_ctrl_top [get_filesets sources_1]

add_files -fileset sim_1 -norecurse [list \
    [file join $project_dir sim tb_beam_ctrl_top.sv] \
    [file join $project_dir sim tb_array_write_engine.sv] \
    [file join $project_dir sim tb_array_load_ctrl.sv] \
    [file join $project_dir sim tb_beam_ctrl_core.sv] \
    [file join $project_dir sim tb_debug_command_adapter.sv] \
    [file join $project_dir sim tb_protocol_v02.sv] \
    [file join $project_dir sim tb_update_timing.sv]]
set_property file_type SystemVerilog [get_files [file join $project_dir sim *.sv]]
set_property top tb_beam_ctrl_top [get_filesets sim_1]

add_files -fileset constrs_1 -norecurse [file join $project_dir constr beam_ctrl.xdc]
set_property target_constrs_file [file join $project_dir constr beam_ctrl.xdc] [get_filesets constrs_1]
add_files -fileset utils_1 -norecurse [file join $script_dir pre_synth.tcl]
set_property STEPS.SYNTH_DESIGN.TCL.PRE [file join $script_dir pre_synth.tcl] [get_runs synth_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "STEP3_PROJECT_CREATED part=$part_name path=$build_dir"
close_project
