set root [file normalize [file join [file dirname [info script]] ..]]
set flavor [expr {[info exists ::env(V03_BUILD_FLAVOR)] ? $::env(V03_BUILD_FLAVOR) : "base"}]
set project [file join $root build $flavor beam_control_v03.xpr]
if {![file exists $project]} { error "Create project first: $project" }
open_project $project
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set status [get_property STATUS [get_runs synth_1]]
if {$status ne "synth_design Complete!"} { error "Synthesis failed: $status" }
set synth_log [file join $root build $flavor beam_control_v03.runs synth_1 runme.log]
set log_fd [open $synth_log r]
set log_text [read $log_fd]
close $log_fd
if {[string first "Net data in module/entity tri_ram does not have driver" $log_text] >= 0} {
    error "Trigonometric ROM was not synthesized from tri.mem"
}
if {[string first "Net rst in module/entity beam_phase_calc does not have driver" $log_text] >= 0} {
    error "Beam calculator reset is unconnected"
}
open_run synth_1
set report_dir [file join $root reports $flavor]
file mkdir $report_dir
report_utilization -file [file join $report_dir utilization_synth.rpt]
report_timing_summary -file [file join $report_dir timing_synth.rpt]
puts "V03_SYNTH_PASS flavor=$flavor"
close_project
