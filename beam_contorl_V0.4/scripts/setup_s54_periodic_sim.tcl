set s54_root [file normalize [file join [file dirname [info script]] ..]]
if {![llength [get_filesets -quiet sim_s54_periodic]]} {
    create_fileset -simset sim_s54_periodic
}
set s54_fs [get_filesets sim_s54_periodic]
foreach name {s53_reference_array_write_engine.sv tb_s54_periodic_clock.sv} {
    set f [file join $s54_root sim $name]
    if {![llength [get_files -quiet -of_objects $s54_fs $f]]} {
        add_files -fileset sim_s54_periodic -norecurse $f
    }
}
set_property SOURCE_SET sources_1 $s54_fs
set_property top tb_s54_periodic_clock $s54_fs
set_property top_auto_set false $s54_fs
set_property generic {} $s54_fs
set_property xsim.simulate.runtime 0ns $s54_fs
set_property xsim.elaborate.debug_level all $s54_fs
set_property xsim.simulate.log_all_signals true $s54_fs
update_compile_order -fileset sim_s54_periodic
current_fileset -simset [get_filesets sim_1]
