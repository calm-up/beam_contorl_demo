set sim_root [file normalize [file join [file dirname [info script]] ..]]
file mkdir [file join [pwd] build manual_compare]
foreach input [list [file join $sim_root ccar10405l_expected_frames.mem] [file join $sim_root rtl rom tri.mem]] {
    if {[file exists $input] && [file normalize $input] ne [file normalize [file join [pwd] [file tail $input]]]} {
        file copy -force $input [file join [pwd] [file tail $input]]
    }
}
