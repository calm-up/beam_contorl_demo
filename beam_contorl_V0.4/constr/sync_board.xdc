# J18 8/18 (SYNC_PULSE) is wavefront, 7/17 (SIG_PULSE) is apply.
set_property PACKAGE_PIN U6 [get_ports sync_clk_i]
set_property PACKAGE_PIN B2 [get_ports wavefront_i]
set_property PACKAGE_PIN B1 [get_ports beam_apply_i]
set_property PACKAGE_PIN D19 [get_ports external_t_i]
set_property PACKAGE_PIN D17 [get_ports external_r_i]
set_property IOSTANDARD LVCMOS33 [get_ports {sync_clk_i wavefront_i beam_apply_i external_t_i external_r_i}]
create_clock -name sync_clk -period 100.000 -waveform {0.000 50.000} [get_ports sync_clk_i]

# Restrict exceptions to the first register of the actual single-bit CDC.
set sync_first_stage [get_cells -quiet -hierarchical -filter {
    NAME =~ */wave_q_reg[0] || NAME =~ */apply_q_reg[0] ||
    NAME =~ */byte_sync_q_reg[0] || NAME =~ */seal_sync_q_reg[0] ||
    NAME =~ */done_sync_q_reg[0] || NAME =~ */request_sync_q_reg[0] ||
    NAME =~ *external_t_q_reg[0] || NAME =~ *external_r_q_reg[0]
}]
set_false_path -to [get_pins -of_objects $sync_first_stage -filter {REF_PIN_NAME == D}]

# Bundled data is sampled after the synchronized event. Bound its physical
# delay independently of the phase between the two unrelated clocks.
set_max_delay -datapath_only 20 -from [get_cells -hier -filter {NAME =~ */rx_byte_q_reg*}] -to [get_cells -hier -filter {NAME =~ */byte_o_reg*}]
set_max_delay -datapath_only 20 -from [get_cells -hier -filter {NAME =~ */partial_q_reg}] -to [get_cells -hier -filter {NAME =~ */partial_o_reg}]
set_max_delay -datapath_only 40 -from [get_cells -hier -filter {NAME =~ */response_q_reg* && REF_NAME =~ FD*}] -to [get_cells -hier -filter {NAME =~ */tx_shift_q_reg* && REF_NAME =~ FD*}]
