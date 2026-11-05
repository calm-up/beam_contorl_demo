# A new simulation set avoids reusing the old stopped-clock waveform/cache.
set continuous_root [file normalize [file join [file dirname [info script]] ..]]
if {![llength [get_filesets -quiet sim_continuous]]} {
    create_fileset -simset sim_continuous
}
set continuous_fs [get_filesets sim_continuous]
set continuous_tb [file join $continuous_root sim tb_protocol_v03_top.sv]
if {![llength [get_files -quiet -of_objects $continuous_fs $continuous_tb]]} {
    add_files -fileset sim_continuous -norecurse $continuous_tb
}
set_property SOURCE_SET sources_1 $continuous_fs
set_property top tb_protocol_v03_top $continuous_fs
set_property top_auto_set false $continuous_fs
set_property generic {} $continuous_fs
set_property xsim.simulate.runtime 0ns $continuous_fs
set_property xsim.elaborate.debug_level all $continuous_fs
set_property xsim.simulate.log_all_signals true $continuous_fs
set continuous_dir [file join [get_property DIRECTORY [current_project]] \
    [get_property NAME [current_project]].sim sim_continuous behav xsim]
file mkdir [file join $continuous_dir rtl rom]
file copy -force [file join $continuous_root rtl rom tri.mem] [file join $continuous_dir rtl rom tri.mem]
update_compile_order -fileset sim_continuous
current_fileset -simset $continuous_fs
