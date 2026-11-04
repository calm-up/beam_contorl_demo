set root [file normalize [file join [file dirname [info script]] ..]]
set flavor [expr {[info exists ::env(V03_BUILD_FLAVOR)] ? $::env(V03_BUILD_FLAVOR) : "base"}]
set bit [file join $root output $flavor beam_control_v03_${flavor}.bit]
set mcs [file join $root output $flavor beam_control_v03_u5_spix1_16m.mcs]
if {![file exists $bit]} { error "Verified base BIT not found: $bit" }
if {[file size $bit] >= 16*1024*1024} {
    error "BIT is larger than the 16 MiB U5 configuration memory"
}
write_cfgmem -force -format mcs -size 16 -interface spix1 \
    -loadbit [list up 0x00000000 $bit] -file $mcs
if {![file exists $mcs] || [file size $mcs] == 0} {
    error "MCS generation failed"
}
puts "V03_U5_MCS_PASS bit=$bit mcs=$mcs"
