set root [file normalize [file join [file dirname [info script]] ..]]
create_project -force gui_sim_check [file join $root build gui_sim_check] -part xc7a200tfbg484-1
add_files [glob [file join $root rtl *.sv]]
add_files [glob [file join $root reference bjn110_cal_phase *.v]]
add_files [file join $root rtl rom tri.mem]
set_property top beam_ctrl_top [get_filesets sources_1]
source [file join $root scripts setup_gui_simulation.tcl]
launch_simulation -simset sim_sdo_pipeline -mode behavioral
close_sim
puts "GUI_SDO_SIM_CHECK_PASS"
close_project
