# Source with the implemented design open and these variables set in ns.
# Input arrival is relative to the incoming rising clock at the FPGA port.
# Output required timing is relative to the falling clock, including the
# outward clock flight and feedback return flight to the host.
foreach name {sync_in_min sync_in_max sync_out_min sync_out_max} {
    if {![info exists $name] || ![string is double -strict [set $name]]} {
        error "Set $name from the measured board/host timing budget before sourcing this file"
    }
}
if {$sync_in_min > $sync_in_max || $sync_out_min > $sync_out_max} {
    error "SYNC minimum delays must not exceed maximum delays"
}
set_input_delay -clock sync_clk -min $sync_in_min [get_ports rs422_rx_i]
set_input_delay -clock sync_clk -max $sync_in_max [get_ports rs422_rx_i]
set_output_delay -clock sync_clk -clock_fall -min $sync_out_min [get_ports rs422_tx_o]
set_output_delay -clock sync_clk -clock_fall -max $sync_out_max [get_ports rs422_tx_o]
