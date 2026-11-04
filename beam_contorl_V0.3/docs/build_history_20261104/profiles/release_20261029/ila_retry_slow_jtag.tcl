open_hw_manager
connect_hw_server -url localhost:3121
set target [lindex [get_hw_targets] 0]
set_property PARAM.FREQUENCY 1000000 $target
open_hw_target $target
set device [lindex [get_hw_devices] 0]
set_property PROBES.FILE [file normalize output/diag_short/beam_control_v03_debug.ltx] $device
refresh_hw_device $device
puts "TARGET_FREQ=[get_property PARAM.FREQUENCY $target] BSCAN_MASK=[get_property BSCAN_SWITCH_USER_MASK $device]"
puts "ILA_COUNT=[llength [get_hw_ilas]] ILAS=[get_hw_ilas]"
foreach ila [get_hw_ilas] {
    puts "ILA=$ila"
    foreach probe [get_hw_probes -of_objects $ila] { puts "PROBE=$probe" }
}
close_hw_target
disconnect_hw_server
close_hw_manager
