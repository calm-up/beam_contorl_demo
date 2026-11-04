open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices xc7a200t*] 0]
if {$dev eq ""} {error "xc7a200t not detected"}
current_hw_device $dev
set root [file normalize [file join [file dirname [info script]] ..]]
set_property PROBES.FILE [file join $root output diag_sdo_raw beam_control_v03_debug.ltx] $dev
refresh_hw_device $dev
foreach ila [get_hw_ilas] {
    puts "ILA=$ila DEPTH=[get_property CONTROL.DATA_DEPTH $ila]"
    foreach probe [get_hw_probes -of_objects $ila] {
        puts "PROBE=$probe WIDTH=[get_property PROBE_PORT_BIT_COUNT $probe]"
    }
}
close_hw_manager
