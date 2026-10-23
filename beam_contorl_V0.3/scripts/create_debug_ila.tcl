# Sourced with the V0.3 project open. Both ILA clocks are the free-running sys_clk.
create_ip -name ila -vendor xilinx.com -library ip -module_name ila_v03_protocol
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {9} CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_PROBE0_WIDTH {8} CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {6} CONFIG.C_PROBE3_WIDTH {8} \
    CONFIG.C_PROBE4_WIDTH {4} CONFIG.C_PROBE5_WIDTH {8} \
    CONFIG.C_PROBE6_WIDTH {8} CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {4}] [get_ips ila_v03_protocol]
create_ip -name ila -vendor xilinx.com -library ip -module_name ila_v03_array
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {8} CONFIG.C_DATA_DEPTH {8192} \
    CONFIG.C_PROBE0_WIDTH {4} CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {24} CONFIG.C_PROBE7_WIDTH {8}] [get_ips ila_v03_array]
generate_target all [get_ips {ila_v03_protocol ila_v03_array}]
puts "V03_ILA_CREATED protocol=9 array=8"
