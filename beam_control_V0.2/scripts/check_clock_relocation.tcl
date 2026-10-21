set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set dcp_file    [file join $project_dir reports step3_post_synth.dcp]
set report_file [file join $project_dir reports clock_relocation_candidates.txt]

set fp [open $report_file w]
puts $fp "XC7A200T-FBG484 clock relocation placement check"

foreach candidate {U20_SWAP U15 E19} {
    open_checkpoint $dcp_file
    if {$candidate eq "U20_SWAP"} {
        # Put the clock on the P side and reuse the former N side as ordinary SDI IO.
        reset_property PACKAGE_PIN [get_ports {sys_clk_i rx_sdi_o[10]}]
        set_property PACKAGE_PIN V20 [get_ports {rx_sdi_o[10]}]
        set_property PACKAGE_PIN U20 [get_ports {sys_clk_i}]
    } else {
        reset_property PACKAGE_PIN [get_ports {sys_clk_i}]
        set_property PACKAGE_PIN $candidate [get_ports {sys_clk_i}]
    }

    set result [catch {place_design -directive Quick} message options]
    if {$result == 0} {
        set clock_pin [get_property PACKAGE_PIN [get_ports sys_clk_i]]
        puts $fp "$candidate PASS sys_clk=$clock_pin"
        puts "CLOCK_CANDIDATE_PASS $candidate sys_clk=$clock_pin"
    } else {
        puts $fp "$candidate FAIL $message"
        puts "CLOCK_CANDIDATE_FAIL $candidate $message"
    }
    close_design
}

close $fp
