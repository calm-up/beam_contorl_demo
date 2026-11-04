set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root output s52 beam_control_v03_s52.bit]
set ltx [file join $root output s52 beam_control_v03_debug.ltx]
set props [file join $root reports s52 spi_config_properties.txt]
foreach file [list $bit $ltx $props] {if {![file exists $file]} {error "Required artifact missing: $file"}}
open_hw_manager
connect_hw_server -url localhost:3121
set target [lindex [get_hw_targets *] 0]
if {$target eq ""} {error "No JTAG target"}
open_hw_target $target
set dev [lindex [get_hw_devices xc7a200t*] 0]
if {$dev eq ""} {error "xc7a200t not detected"}
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
set_property PROBES.FILE $ltx $dev
set_property BSCAN_SWITCH_USER_MASK 0001 $dev
program_hw_devices $dev
refresh_hw_device $dev
set done [get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $dev]
puts "DONE=$done ILAS=[get_hw_ilas]"
if {$done ne "1"} {error "FPGA DONE not asserted"}
puts "PROGRAM_S52_PASS"
close_hw_manager
