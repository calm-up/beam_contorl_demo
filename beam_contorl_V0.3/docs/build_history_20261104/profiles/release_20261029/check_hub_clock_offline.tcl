open_checkpoint X:/build/diag_short/beam_control_v03.runs/impl_1/beam_ctrl_top_routed.dcp
set hub [get_debug_cores dbg_hub]
puts "HUB=$hub USER_SCAN_CHAIN=[get_property C_USER_SCAN_CHAIN $hub] CLK_META_HZ=[get_property C_CLK_INPUT_FREQ_HZ $hub]"
foreach pattern {dbg_hub/clk dbg_hub/CLK dbg_hub/clk_i} {
    set pins [get_pins -quiet $pattern]
    foreach pin $pins {
        puts "HUB_PIN=$pin NET=[get_nets -of_objects $pin] CLOCKS=[get_clocks -of_objects $pin]"
    }
}
puts "SYS_CLOCK_PORT=[get_ports sys_clk_i] CLOCKS=[get_clocks -of_objects [get_ports sys_clk_i]]"
close_design
