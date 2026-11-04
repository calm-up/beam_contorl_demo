set root [file normalize [file join [file dirname [info script]] ..]]
set checkpoint [file join $root build release_20261029 beam_control_v03.runs impl_1 beam_ctrl_top_routed.dcp]
set output_dir [file join $root output spix1_explicit_20261029]
set bit [file join $output_dir beam_control_v03_spix1_explicit.bit]
set mcs [file join $output_dir beam_control_v03_spix1_explicit_16m.mcs]

if {![file exists $checkpoint]} {error "Routed checkpoint missing: $checkpoint"}
file mkdir $output_dir
open_checkpoint $checkpoint
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CONFIG_MODE SPIx1 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 3 [current_design]
foreach property {CFGBVS CONFIG_VOLTAGE CONFIG_MODE BITSTREAM.CONFIG.SPI_BUSWIDTH BITSTREAM.CONFIG.CONFIGRATE} {
    puts "BOOT_PROPERTY $property=[get_property $property [current_design]]"
}
write_bitstream -force $bit
write_cfgmem -force -format mcs -size 16 -interface spix1 \
    -loadbit [list up 0x00000000 $bit] -file $mcs
puts "SPIX1_EXPLICIT_PASS bit=$bit mcs=$mcs"
close_design
