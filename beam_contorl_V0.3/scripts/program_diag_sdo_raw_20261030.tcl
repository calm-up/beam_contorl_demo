set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root output diag_sdo_raw beam_control_v03_diag_sdo_raw.bit]
set ltx [file join $root output diag_sdo_raw beam_control_v03_debug.ltx]
if {![file exists $bit] || ![file exists $ltx]} {error "Diagnostic BIT or LTX missing"}

open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets *]
puts "TARGETS=$targets"
if {[llength $targets] == 0} {error "No JTAG hardware target detected"}
open_hw_target [lindex $targets 0]
set dev [lindex [get_hw_devices xc7a200t*] 0]
if {$dev eq ""} {error "xc7a200t not detected"}
current_hw_device $dev
puts "DEVICE=$dev"
set_property PROGRAM.FILE $bit $dev
set_property PROBES.FILE $ltx $dev
set_property BSCAN_SWITCH_USER_MASK 0001 $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "PROGRAM_FILE=[get_property PROGRAM.FILE $dev]"
foreach property {REGISTER.CONFIG_STATUS.BIT13_DONE_INTERNAL_SIGNAL_STATUS REGISTER.CONFIG_STATUS.BIT14_DONE_PIN} {
    puts "STATUS $property=[get_property $property $dev]"
}
puts "ILAS=[get_hw_ilas]"
puts "JTAG_DIAG_PROGRAM_PASS"
close_hw_manager
