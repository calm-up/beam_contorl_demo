open_hw_manager
connect_hw_server -url localhost:3121
set target [lindex [get_hw_targets] 0]
puts "TARGET=$target"
open_hw_target $target
set device [lindex [get_hw_devices -filter {PART == xc7a200t}] 0]
puts "DEVICE=$device"
set_property PROBES.FILE [file normalize output/diag_sdo_raw/beam_control_v03_debug.ltx] $device
refresh_hw_device $device
puts "PROGRAMMED=[get_property REGISTER.CONFIG_STATUS $device]"
puts "ILAS=[get_hw_ilas]"
close_hw_target
disconnect_hw_server
close_hw_manager
