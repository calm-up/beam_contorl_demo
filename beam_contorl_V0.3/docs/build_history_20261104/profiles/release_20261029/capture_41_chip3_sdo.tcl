open_hw_manager
connect_hw_server -url localhost:3121
set target [lindex [get_hw_targets] 0]
set_property PARAM.FREQUENCY 15000000 $target
open_hw_target $target
set device [lindex [get_hw_devices -filter {PART == xc7a200t}] 0]
set_property PROBES.FILE [file normalize output/diag_sdo_raw/beam_control_v03_debug.ltx] $device
refresh_hw_device $device
set ila [lindex [get_hw_ilas hw_ila_1] 0]
if {$ila eq ""} { error "ARRAY_ILA_NOT_FOUND" }
set probe [get_hw_probes rx_csb_o_OBUF -of_objects $ila]
if {[llength $probe] != 1} { error "RX_CSB_PROBE_NOT_FOUND" }
set_property CONTROL.DATA_DEPTH 8192 $ila
set_property CONTROL.TRIGGER_POSITION 128 $ila
set_property CONTROL.TRIGGER_CONDITION AND $ila
set_property TRIGGER_COMPARE_VALUE eq1'b0 $probe
run_hw_ila $ila
puts "ILA_ARMED core=$ila trigger=rx_csb_low"
flush stdout
wait_on_hw_ila -timeout 30 $ila
puts "ILA_STATUS=[get_property STATUS.CORE_STATUS $ila]"
set data [upload_hw_ila_data $ila]
set csv [file normalize output/release_20261029/ila_41_j1_chip3_sdo.csv]
write_hw_ila_data -csv_file $csv $data
puts "ILA_CAPTURE_SAVED=$csv"
close_hw_target
disconnect_hw_server
close_hw_manager
