open_checkpoint X:/build/diag_short/beam_control_v03.runs/impl_1/beam_ctrl_top_routed.dcp
puts "DEBUG_CORES=[get_debug_cores]"
foreach core [get_debug_cores] {
    puts "CORE=$core"
    foreach prop {C_USER_SCAN_CHAIN C_CLK_INPUT_FREQ_HZ C_ENABLE_CLK_DIVIDER} {
        if {![catch {get_property $prop $core} value]} { puts "$prop=$value" }
    }
}
puts "CLOCK_PORT=[get_ports sys_clk_i] PACKAGE_PIN=[get_property PACKAGE_PIN [get_ports sys_clk_i]]"
close_design
