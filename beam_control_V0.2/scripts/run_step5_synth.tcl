set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set report_dir  [file join $project_dir reports]
file mkdir $report_dir

create_project -in_memory -part xc7a200t-fbg484-1
read_verilog -sv [file join $project_dir rtl beam_cmd_pkg.sv]
read_verilog -sv [file join $project_dir rtl array_write_engine.sv]
synth_design -mode out_of_context -top array_write_engine \
    -part xc7a200t-fbg484-1
create_clock -name sys_clk -period 20.000 [get_ports clk_i]
report_utilization -file [file join $report_dir step5_engine_utilization.rpt]
report_timing_summary -file [file join $report_dir step5_engine_timing.rpt]
write_checkpoint -force [file join $report_dir step5_engine_post_synth.dcp]
puts "STEP5_ENGINE_SYNTH_PASS"
