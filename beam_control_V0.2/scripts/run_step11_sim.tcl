set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set xpr         [file join $project_dir build vivado beam_control.xpr]
set report_dir  [file join $project_dir reports]
file mkdir $report_dir

open_project $xpr
set_property top tb_update_timing [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
close_sim
set sim_log [file join $project_dir build vivado beam_control.sim sim_1 behav xsim simulate.log]
file copy -force $sim_log [file join $report_dir tb_update_timing.log]
close_project
