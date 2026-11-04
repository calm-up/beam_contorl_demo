set root [file normalize [file join [file dirname [info script]] ..]]
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target [lindex [get_hw_targets *] 0]
set dev [lindex [get_hw_devices xc7a200t*] 0]
current_hw_device $dev
set_property PROBES.FILE [file join $root output c30 beam_control_v03_debug.ltx] $dev
refresh_hw_device $dev
foreach ila [get_hw_ilas] {
    puts "ILA=$ila STATUS=[get_property STATUS.CORE_STATUS $ila]"
    foreach probe [get_hw_probes -of_objects $ila] {
        puts "PROBE=$probe WIDTH=[get_property PROBE_PORT_BIT_COUNT $probe]"
    }
}
close_hw_manager
