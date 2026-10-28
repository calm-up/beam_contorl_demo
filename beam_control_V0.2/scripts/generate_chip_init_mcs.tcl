set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set bit_file [file join $project_dir output beam_control_v02_ccar10405l_init_2024.bit]
set mcs_file [file join $project_dir output beam_control_v02_ccar10405l_init_2024_spix1_16MiB.mcs]
if {![file exists $bit_file]} {
    error "Build the CCAR10405L initialization BIT first: $bit_file"
}
write_cfgmem -force -format mcs -interface spix1 -size 16 \
    -loadbit "up 0x0 $bit_file" -file $mcs_file
puts "CHIP_INIT_MCS=$mcs_file"
