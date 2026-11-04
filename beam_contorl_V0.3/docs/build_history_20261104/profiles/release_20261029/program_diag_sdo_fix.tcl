set bit_path [file normalize output/diag_sdo_fix/beam_control_v03_diag_sdo_fix.bit]
set ltx_path [file normalize output/diag_sdo_fix/beam_control_v03_debug.ltx]
open_hw_manager
connect_hw_server -url localhost:3121
set target [lindex [get_hw_targets] 0]
set_property PARAM.FREQUENCY 15000000 $target
open_hw_target $target
set device [lindex [get_hw_devices -filter {PART == xc7a200t}] 0]
set_property PROGRAM.FILE $bit_path $device
set_property PROBES.FILE $ltx_path $device
program_hw_devices $device
refresh_hw_device $device
puts "PROGRAMMED=$device ILAS=[llength [get_hw_ilas]]"
close_hw_target
disconnect_hw_server
close_hw_manager
