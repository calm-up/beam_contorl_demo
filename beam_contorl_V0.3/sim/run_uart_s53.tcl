# Vivado Tcl console: source D:/beam_control/beam_control_demo/beam_contorl_demo/beam_contorl_V0.3/sim/run_uart_s53.tcl
# Configure sim_1 with a driven UART testbench, then retain a WDB for inspection.
set uart_sim_root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] eq ""} {
    open_project [file join $uart_sim_root build s53 beam_control_v03.xpr]
}
catch {close_sim}
set uart_sim_fs [get_filesets sim_1]
set uart_sim_tb [file join $uart_sim_root sim tb_protocol_v03_top.sv]
if {![llength [get_files -quiet -of_objects $uart_sim_fs $uart_sim_tb]]} {
    add_files -fileset sim_1 -norecurse $uart_sim_tb
}
set_property top tb_protocol_v03_top $uart_sim_fs
set_property top_auto_set false $uart_sim_fs
# Hardware top-level generics do not belong to the parameterless testbench.
set_property generic {} $uart_sim_fs
set_property xsim.simulate.runtime 0ns $uart_sim_fs
set_property xsim.elaborate.debug_level all $uart_sim_fs
set_property xsim.simulate.log_all_signals true $uart_sim_fs
set_property xsim.simulate.tcl.pre [file join $uart_sim_root scripts gui_sim_prepare.tcl] $uart_sim_fs
current_fileset -simset $uart_sim_fs
update_compile_order -fileset sim_1
# beam_phase_rom uses $readmemh("rtl/rom/tri.mem"); exporting tri.mem alone is
# insufficient when XSim changes its working directory to the run folder.
set uart_sim_dir [file join [get_property DIRECTORY [current_project]] \
    [get_property NAME [current_project]].sim sim_1 behav xsim]
file mkdir [file join $uart_sim_dir rtl rom]
file copy -force [file join $uart_sim_root rtl rom tri.mem] \
    [file join $uart_sim_dir rtl rom tri.mem]
launch_simulation -simset sim_1 -mode behavioral
log_wave -r /tb_protocol_v03_top/*
add_wave /tb_protocol_v03_top/sys_clk_i
add_wave /tb_protocol_v03_top/debug_rx_i
add_wave /tb_protocol_v03_top/debug_tx_o
add_wave /tb_protocol_v03_top/active_command
add_wave /tb_protocol_v03_top/frame_count
add_wave /tb_protocol_v03_top/load_count
add_wave /tb_protocol_v03_top/dut/rx_sdi_o
add_wave /tb_protocol_v03_top/dut/rx_clk_o
add_wave /tb_protocol_v03_top/dut/rx_csb_o
add_wave /tb_protocol_v03_top/dut/rx_ldb_o
run all
puts "UART_SIM_FINISHED: check TB_V03_PASS; waveform is in sim_1/behav/xsim"
