set root [file normalize [file join [file dirname [info script]] ..]]
set python D:/anaconda/python.exe
foreach name {PYTHONHOME PYTHONPATH} {
    if {[info exists ::env($name)]} {unset ::env($name)}
}
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target [lindex [get_hw_targets *] 0]
set dev [lindex [get_hw_devices xc7a200t*] 0]
if {$dev eq ""} {error "xc7a200t not detected"}
current_hw_device $dev
set_property PROBES.FILE [file join $root output s52 beam_control_v03_debug.ltx] $dev
refresh_hw_device $dev
set ila ""
foreach candidate [get_hw_ilas] {
    if {[llength [get_hw_probes rx_csb_o_OBUF -of_objects $candidate]]} {
        set ila $candidate
        break
    }
}
if {$ila eq ""} {error "Array ILA not found"}
reset_hw_ila $ila
set_property CONTROL.TRIGGER_CONDITION AND $ila
set_property CONTROL.DATA_DEPTH 1024 $ila
set_property CONTROL.TRIGGER_POSITION 64 $ila
set_property TRIGGER_COMPARE_VALUE "eq1'b0" [get_hw_probes rx_csb_o_OBUF -of_objects $ila]
run_hw_ila $ila
puts "ARRAY_ILA_ARMED"
flush stdout
exec $python [file join $root scripts attenuation_live_20261030.py] set \
    --chip 3 --channel 0 --att 1 --no-ack
wait_on_hw_ila -timeout 2 $ila
set data [upload_hw_ila_data $ila]
if {$data eq ""} {error "No array capture"}
set capture [file join $root output s52 chip3_rf1_att01_write.csv]
write_hw_ila_data -force -csv_file $capture $data
puts "CAPTURED $capture"
close_hw_manager


