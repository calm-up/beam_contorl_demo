set flavor diag_short
set bit_path [file normalize "output/$flavor/beam_control_v03_${flavor}.bit"]
set ltx_path [file normalize "output/$flavor/beam_control_v03_debug.ltx"]
if {![file exists $bit_path] || ![file exists $ltx_path]} {
    error "DEBUG_ARTIFACT_MISSING bit=$bit_path ltx=$ltx_path"
}
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets]
if {[llength $targets] != 1} { error "EXPECTED_ONE_TARGET $targets" }
set_property PARAM.FREQUENCY 15000000 [lindex $targets 0]
open_hw_target [lindex $targets 0]
set devices [get_hw_devices -filter {PART == xc7a200t}]
if {[llength $devices] != 1} { error "EXPECTED_ONE_DEVICE $devices" }
set device [lindex $devices 0]
set_property PROGRAM.FILE $bit_path $device
set_property PROBES.FILE $ltx_path $device
program_hw_devices $device
refresh_hw_device $device
puts "DEBUG_PROGRAMMED device=$device"
puts "ILA_COUNT=[llength [get_hw_ilas]]"
foreach ila [get_hw_ilas] {
    puts "ILA=$ila DATA_DEPTH=[get_property CONTROL.DATA_DEPTH $ila]"
    foreach probe [get_hw_probes -of_objects $ila] {
        puts "PROBE=$probe WIDTH=[get_property PROBE_PORT_BIT_COUNT $probe]"
    }
}
close_hw_target
disconnect_hw_server
close_hw_manager
