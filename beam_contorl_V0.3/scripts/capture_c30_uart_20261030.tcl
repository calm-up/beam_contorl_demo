set root [file normalize [file join [file dirname [info script]] ..]]
set flavor [expr {[info exists ::env(V03_CAPTURE_FLAVOR)] ? $::env(V03_CAPTURE_FLAVOR) : "c30"}]
set capture_name [expr {[info exists ::env(V03_CAPTURE_NAME)] ? $::env(V03_CAPTURE_NAME) : "capture"}]
set trigger_probe [expr {[info exists ::env(V03_TRIGGER_PROBE)] ? $::env(V03_TRIGGER_PROBE) : "core_load_done"}]
set trigger_position [expr {[info exists ::env(V03_TRIGGER_POSITION)] ? $::env(V03_TRIGGER_POSITION) : 768}]
set ila_index [expr {[info exists ::env(V03_ILA_INDEX)] ? $::env(V03_ILA_INDEX) : 0}]
set trigger_compare [expr {[info exists ::env(V03_TRIGGER_COMPARE)] ? $::env(V03_TRIGGER_COMPARE) : "eq1'b1"}]
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target [lindex [get_hw_targets *] 0]
set dev [lindex [get_hw_devices xc7a200t*] 0]
current_hw_device $dev
set_property PROBES.FILE [file join $root output $flavor beam_control_v03_debug.ltx] $dev
refresh_hw_device $dev
set ila [lindex [get_hw_ilas] $ila_index]
reset_hw_ila $ila
set_property CONTROL.DATA_DEPTH 1024 $ila
set_property CONTROL.TRIGGER_POSITION $trigger_position $ila
set_property TRIGGER_COMPARE_VALUE $trigger_compare [get_hw_probes $trigger_probe -of_objects $ila]
run_hw_ila $ila
puts "UART_ILA_ARMED"
flush stdout
wait_on_hw_ila -timeout 1 $ila
set data [upload_hw_ila_data $ila]
write_hw_ila_data -force -csv_file [file join $root output $flavor ${capture_name}.csv] $data
puts "ATT_CAPTURE_DONE"
close_hw_manager
