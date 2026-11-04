set root [file normalize [file join [file dirname [info script]] ..]]
set debug_enabled 1
set flavor s54
set project [file join $root build $flavor beam_control_v03.xpr]
if {![file exists $project]} { error "Create project first: $project" }
set out_dir [file join $root output $flavor]
set report_dir [file join $root reports $flavor]
file mkdir $out_dir
file mkdir $report_dir
open_project $project
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1
report_utilization -file [file join $report_dir utilization_synth.rpt]
report_timing_summary -file [file join $report_dir timing_synth.rpt]
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Implementation failed: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
set cfg_log [open [file join $report_dir spi_config_properties.txt] w]
foreach {property expected} {CFGBVS VCCO CONFIG_VOLTAGE 3.3 CONFIG_MODE SPIx1 BITSTREAM.CONFIG.SPI_BUSWIDTH 1 BITSTREAM.CONFIG.CONFIGRATE 3} {
    set actual [get_property $property [current_design]]
    puts $cfg_log "$property=$actual expected=$expected"
    if {![string equal -nocase $actual $expected] &&
        !([string is double -strict $actual] && [string is double -strict $expected] && $actual == $expected)} {
        close $cfg_log
        error "SPI configuration mismatch: $property=$actual expected=$expected"
    }
}
close $cfg_log
report_drc -file [file join $report_dir drc_impl.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report_dir timing_impl.rpt]
report_utilization -file [file join $report_dir utilization_impl.rpt]
close_design
set bit [file join $root build $flavor beam_control_v03.runs impl_1 beam_ctrl_top.bit]
file copy -force $bit [file join $out_dir beam_control_v03_${flavor}.bit]
if {$debug_enabled} {
    set ltx [file join $root build $flavor beam_control_v03.runs impl_1 beam_ctrl_top.ltx]
    if {![file exists $ltx]} { error "Debug bitstream has no LTX: $ltx" }
    file copy -force $ltx [file join $out_dir beam_control_v03_debug.ltx]
}
puts "V03_BUILD_PASS flavor=$flavor bit=[file join $out_dir beam_control_v03_${flavor}.bit]"
close_project
