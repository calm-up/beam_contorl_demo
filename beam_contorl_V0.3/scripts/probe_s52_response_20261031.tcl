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
foreach candidate [get_hw_ilas] {if {[llength [get_hw_probes response_byte_valid -of_objects $candidate]]} {set ila $candidate; break}}
reset_hw_ila $ila
set_property CONTROL.DATA_DEPTH 1024 $ila
set_property CONTROL.TRIGGER_POSITION 512 $ila
set_property TRIGGER_COMPARE_VALUE "eq1'b1" [get_hw_probes response_byte_valid -of_objects $ila]
run_hw_ila $ila
puts "ARMED_RESPONSE"
flush stdout
exec $python [file join $root scripts attenuation_live_20261030.py] read --chip 0 --function 4 --address 0 --no-ack
wait_on_hw_ila -timeout 1 $ila
set data [upload_hw_ila_data $ila]
if {$data eq ""} {error "No response event"}
write_hw_ila_data -force -csv_file [file join $root output s52 response_diagnostic.csv] $data
close_hw_manager
