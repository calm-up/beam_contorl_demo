set root [file normalize [file join [file dirname [info script]] ..]]
set mcs [file join $root output spix1_explicit_20261029 beam_control_v03_spix1_explicit_16m.mcs]
if {![file exists $mcs]} {error "MCS missing: $mcs"}

open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices xc7a200t_0] 0]
if {$dev eq ""} {error "xc7a200t_0 not found"}
current_hw_device $dev

set part [lindex [get_cfgmem_parts {w25q128bv-spi-x1_x2_x4}] 0]
if {$part eq ""} {error "W25Q128BV SPI configuration memory part unavailable"}
puts "PROGRAM_PART=$part"
puts "PROGRAM_MCS=$mcs"
set cfg [create_hw_cfgmem -hw_device $dev $part]
set_property PROGRAM.FILES $mcs $cfg
set_property PROGRAM.ERASE 1 $cfg
set_property PROGRAM.BLANK_CHECK 1 $cfg
set_property PROGRAM.CFG_PROGRAM 1 $cfg
set_property PROGRAM.VERIFY 1 $cfg

set indirect [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
create_hw_bitstream -hw_device $dev $indirect
program_hw_devices $dev
refresh_hw_device $dev
program_hw_cfgmem $cfg
puts "PROGRAM_VERIFY_PASS"

boot_hw_device -timeout 60 $dev
refresh_hw_device $dev
foreach property {REGISTER.CONFIG_STATUS REGISTER.BOOT_STATUS} {
    puts "AFTER_BOOT $property=[get_property $property $dev]"
}
foreach property [list_property $dev] {
    if {[regexp {^REGISTER\.CONFIG_STATUS\.BIT(04|11|12|13|14|25)_} $property]} {
        puts "AFTER_BOOT $property=[get_property $property $dev]"
    }
}
close_hw_manager
