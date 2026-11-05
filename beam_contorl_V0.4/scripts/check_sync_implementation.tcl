# Engineering run. No bitstream is generated.
set root [file normalize [file join [file dirname [info script]] ..]]
set report_dir [file join $root build sync_implementation]
if {[info exists ::env(V04_REPORT_DIR)]} {
    set report_dir [file normalize $::env(V04_REPORT_DIR)]
}
file mkdir $report_dir
open_project [file join $root build v04 beam_control_v03.xpr]
set_property generic {ENABLE_DEBUG_ILA=0} [get_filesets sources_1]
synth_design -top beam_ctrl_top -part xc7a200t-fbg484-1
write_checkpoint -force [file join $report_dir synthesized.dcp]
report_cdc -details -file [file join $report_dir cdc_synth.rpt]
opt_design
if {[catch {place_design} reason]} {
    puts stderr "V04_PLACE_FAILED: $reason"
    report_drc -file [file join $report_dir drc_place_failure.rpt]
    if {![info exists ::env(V04_TRIAL_U6_FABRIC)] || $::env(V04_TRIAL_U6_FABRIC) ne "1"} {
        exit 1
    }
    # Explicit lab trial only. The routed DCP does not qualify the board I/O.
    set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets sync_clk_i_IBUF]
    place_design
}
route_design
write_checkpoint -force [file join $report_dir routed.dcp]
report_clock_utilization -file [file join $report_dir clocks.rpt]
report_cdc -details -file [file join $report_dir cdc_routed.rpt]
report_timing_summary -report_unconstrained -file [file join $report_dir timing.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_timing -from [get_ports rs422_rx_i] -max_paths 5 -file [file join $report_dir sync_input.rpt]
report_timing -to [get_ports rs422_tx_o] -max_paths 5 -file [file join $report_dir sync_output.rpt]
