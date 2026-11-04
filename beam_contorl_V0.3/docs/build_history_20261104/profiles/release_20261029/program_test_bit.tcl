set bit_path [file normalize "output/release_20261029/beam_control_v03_release_20261029.bit"]
if {![file exists $bit_path]} { error "BIT_NOT_FOUND $bit_path" }
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets]
if {[llength $targets] != 1} { error "EXPECTED_ONE_TARGET got=$targets" }
set_property PARAM.FREQUENCY 15000000 [lindex $targets 0]
open_hw_target [lindex $targets 0]
set devices [get_hw_devices -filter {PART == xc7a200t}]
if {[llength $devices] != 1} { error "EXPECTED_ONE_XC7A200T got=$devices" }
set device [lindex $devices 0]
puts "PROGRAM_DEVICE=$device BIT=$bit_path"
set_property PROGRAM.FILE $bit_path $device
program_hw_devices $device
refresh_hw_device $device
puts "PROGRAM_COMPLETE device=$device"
foreach property {REGISTER.CONFIG_STATUS REGISTER.CONFIG_STATUS.DONE STATUS} {
    if {![catch {get_property $property $device} value]} {
        puts "$property=$value"
    }
}
close_hw_target
disconnect_hw_server
close_hw_manager
