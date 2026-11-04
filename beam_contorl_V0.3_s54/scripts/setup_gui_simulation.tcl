# Source this in an OPEN Vivado project. Does not change synthesis RTL/generics.
set sim_root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] eq ""} {error "Open the S53 XPR first"}
set sim_cases {
    sim_sdo_pipeline tb_chip_sdo_pipeline
    sim_sdo_alignment tb_array_write_sdo
    sim_spi_timing tb_tr_spi_timing
    sim_write_load tb_tr_pipeline_model
    sim_initialization tb_ccar10405l_init
    sim_protocol tb_protocol_v03_top
    sim_formula tb_beam_formula_calc
    sim_pulse tb_pulse_gate_110
    sim_flash tb_u22_flash_device
}
foreach {sim_set sim_top} $sim_cases {
    if {![llength [get_filesets -quiet $sim_set]]} {create_fileset -simset $sim_set}
    set fs [get_filesets $sim_set]
    add_files -fileset $sim_set -norecurse [file join $sim_root sim ${sim_top}.sv]
    set_property SOURCE_SET sources_1 $fs
    set_property TOP $sim_top $fs
    set_property TOP_AUTO_SET 0 $fs
    set_property xsim.simulate.runtime all $fs
    set_property xsim.elaborate.debug_level all $fs
    set_property xsim.simulate.log_all_signals true $fs
    set_property xsim.simulate.tcl.pre [file join $sim_root scripts gui_sim_prepare.tcl] $fs
    update_compile_order -fileset $sim_set
}
current_fileset -simset [get_filesets sim_sdo_pipeline]
puts "GUI_SIMULATION_READY active=sim_sdo_pipeline top=tb_chip_sdo_pipeline"
puts "Use Run Simulation > Run Behavioral Simulation; to switch: current_fileset -simset \[get_filesets sim_spi_timing\]"
