set root [file normalize [file join [file dirname [info script]] ..]]
set python D:/anaconda/python.exe
foreach key {PYTHONHOME PYTHONPATH} {if {[info exists ::env($key)]} {unset ::env($key)}}
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target [lindex [get_hw_targets *] 0]
set dev [lindex [get_hw_devices xc7a200t*] 0]
current_hw_device $dev
set_property PROBES.FILE [file join $root output s52 beam_control_v03_debug.ltx] $dev
refresh_hw_device $dev
set ila ""
foreach candidate [get_hw_ilas] {if {[llength [get_hw_probes read_done -of_objects $candidate]]} {set ila $candidate; break}}
reset_hw_ila $ila
set_property CONTROL.DATA_DEPTH 1024 $ila
set_property CONTROL.TRIGGER_POSITION 128 $ila
set_property TRIGGER_COMPARE_VALUE "eq1'b1" [get_hw_probes read_done -of_objects $ila]
run_hw_ila $ila
exec $python [file join $root scripts attenuation_live_20261030.py] read --chip 0 --function 2 --address 0 --no-ack
wait_on_hw_ila -timeout 1 $ila
set data [upload_hw_ila_data $ila]
if {$data eq ""} {error "No read_done"}
set path [file join $root output s52 chip0_rf1_dynamic_read.csv]
write_hw_ila_data -force -csv_file $path $data
catch {exec $python [file join $root scripts verify_direct_register_capture_20261031.py] $path 0 2 0 7C0} result
puts "DYNAMIC_CHECK $result"
close_hw_manager

