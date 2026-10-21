set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set dcp_file    [file join $project_dir reports step3_post_synth.dcp]
set report_file [file join $project_dir reports v9_clock_check.txt]

set fp [open $report_file w]
puts $fp "V9 system clock feasibility check"

# Case 1: V9 used without weakening dedicated-clock checks.
open_checkpoint $dcp_file
reset_property PACKAGE_PIN [get_ports sys_clk_i]
set_property PACKAGE_PIN V9 [get_ports sys_clk_i]
set result [catch {place_design -directive Quick} message options]
if {$result == 0} {
    puts $fp "V9_DEDICATED PASS_UNEXPECTED"
} else {
    puts $fp "V9_DEDICATED FAIL_EXPECTED $message"
}
close_design

# Case 2: Force general interconnect to show what the proposed workaround needs.
open_checkpoint $dcp_file
reset_property PACKAGE_PIN [get_ports sys_clk_i]
set_property PACKAGE_PIN V9 [get_ports sys_clk_i]
set clock_input_net [get_nets -quiet sys_clk_i_IBUF]
if {[llength $clock_input_net] != 1} {
    error "Expected sys_clk_i_IBUF net was not found"
}
set_property CLOCK_DEDICATED_ROUTE FALSE $clock_input_net
set result [catch {place_design -directive Quick} message options]
if {$result == 0} {
    puts $fp "V9_FORCED_GENERAL_ROUTE PLACE_PASS"
    report_drc -file [file join $project_dir reports v9_forced_post_place_drc.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained \
        -check_timing_verbose -file [file join $project_dir reports v9_forced_post_place_timing.rpt]
} else {
    puts $fp "V9_FORCED_GENERAL_ROUTE PLACE_FAIL $message"
}
close_design
close $fp
