set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set ip_dir      [file join $project_dir build debug_ip]
file mkdir $ip_dir

create_project -force debug_ip_project $ip_dir -part xc7a200t-fbg484-1
create_ip -name vio -vendor xilinx.com -library ip -module_name vio_debug
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {3} \
    CONFIG.C_NUM_PROBE_OUT {11} \
    CONFIG.C_PROBE_IN0_WIDTH {40} \
    CONFIG.C_PROBE_IN1_WIDTH {1} \
    CONFIG.C_PROBE_IN2_WIDTH {1} \
    CONFIG.C_PROBE_OUT0_WIDTH {1} \
    CONFIG.C_PROBE_OUT1_WIDTH {2} \
    CONFIG.C_PROBE_OUT2_WIDTH {3} \
    CONFIG.C_PROBE_OUT3_WIDTH {2} \
    CONFIG.C_PROBE_OUT4_WIDTH {24} \
    CONFIG.C_PROBE_OUT5_WIDTH {1} \
    CONFIG.C_PROBE_OUT6_WIDTH {2} \
    CONFIG.C_PROBE_OUT7_WIDTH {8} \
    CONFIG.C_PROBE_OUT8_WIDTH {1} \
    CONFIG.C_PROBE_OUT9_WIDTH {1} \
    CONFIG.C_PROBE_OUT10_WIDTH {1}] [get_ips vio_debug]
generate_target all [get_ips vio_debug]
puts "DEBUG_VIO_CREATED [get_property IP_FILE [get_ips vio_debug]]"
close_project
