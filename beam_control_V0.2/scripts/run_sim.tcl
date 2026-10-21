set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set xpr [file join $project_dir build vivado beam_control.xpr]
set report_dir [file join $project_dir reports]
file mkdir $report_dir
open_project $xpr
set_property xsim.simulate.runtime all [get_filesets sim_1]
foreach sim_top {tb_beam_ctrl_top tb_array_write_engine tb_array_load_ctrl tb_beam_ctrl_core tb_debug_command_adapter tb_protocol_v02 tb_update_timing} {
    set_property top $sim_top [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    close_sim
    set sim_log [file join $project_dir build vivado beam_control.sim sim_1 behav xsim simulate.log]
    if {[file exists $sim_log]} {
        file copy -force $sim_log [file join $report_dir ${sim_top}.log]
    }
}
close_project
