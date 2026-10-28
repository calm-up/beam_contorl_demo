set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set report_dir  [file join $project_dir reports]
set output_dir  [file join $project_dir output]
set dcp_file    [file join $report_dir step3_post_synth.dcp]
file mkdir $report_dir
file mkdir $output_dir

if {![file exists $dcp_file]} {
    error "Post-synthesis checkpoint is missing; run run_build.tcl first"
}

open_checkpoint $dcp_file
opt_design
report_drc -file [file join $report_dir post_opt_drc.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $report_dir post_opt_timing_summary.rpt]

set status_file [file join $report_dir implementation_status.txt]
set fp [open $status_file w]
puts $fp "STEP10_IMPLEMENTATION_ATTEMPT"
puts $fp "part=[get_property PART [current_design]]"
puts $fp "top=[get_property TOP [current_design]]"

set place_result [catch {place_design} place_message place_options]
if {$place_result != 0} {
    puts $fp "status=BLOCKED"
    puts $fp "stage=place_design"
    puts $fp "reason=$place_message"
    puts $fp "known_drc=PLCK-12,PLIO-9"
    close $fp
    report_drc -file [file join $report_dir implementation_blocker_drc.rpt]
    puts "STEP10_IMPLEMENTATION_BLOCKED $place_message"
    close_design
    exit 2
}

write_checkpoint -force [file join $report_dir post_place.dcp]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $report_dir post_place_timing_summary.rpt]
report_drc -file [file join $report_dir post_place_drc.rpt]

set route_result [catch {route_design} route_message route_options]
if {$route_result != 0} {
    puts $fp "status=BLOCKED"
    puts $fp "stage=route_design"
    puts $fp "reason=$route_message"
    close $fp
    puts "STEP10_IMPLEMENTATION_BLOCKED $route_message"
    close_design
    exit 3
}

set_property CONFIG_MODE SPIx1 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1 [current_design]
write_checkpoint -force [file join $report_dir post_route.dcp]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $report_dir post_route_timing_summary.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_io -file [file join $report_dir post_route_io.rpt]
write_bitstream -force [file join $output_dir beam_control_v02_v20.bit]
puts $fp "status=PASS"
puts $fp "bitstream=[file join $output_dir beam_control_v02_v20.bit]"
close $fp
puts "STEP10_IMPLEMENTATION_PASS"
