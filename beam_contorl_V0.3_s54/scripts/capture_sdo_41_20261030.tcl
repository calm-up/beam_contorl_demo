set root [file normalize [file join [file dirname [info script]] ..]]
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices xc7a200t*] 0]
if {$dev eq ""} {error "xc7a200t not detected"}
current_hw_device $dev
set_property PROBES.FILE [file join $root output diag_sdo_raw beam_control_v03_debug.ltx] $dev
refresh_hw_device $dev
set ila [lindex [get_hw_ilas hw_ila_1] 0]
if {$ila eq ""} {error "SDO ILA not detected"}
catch {set_property CONTROL.TRIGGER_MODE BASIC_ONLY $ila}
set_property CONTROL.TRIGGER_CONDITION AND $ila
set_property CONTROL.DATA_DEPTH 2048 $ila
set_property CONTROL.TRIGGER_POSITION 256 $ila
set_property TRIGGER_COMPARE_VALUE eq1'b0 [get_hw_probes rx_csb_o_OBUF -of_objects $ila]
run_hw_ila $ila
puts "SDO_ILA_ARMED"
flush stdout
wait_on_hw_ila -timeout 1 $ila
if {[get_property STATUS.CORE_STATUS $ila] ne "IDLE"} {
    puts "ILA_STATUS=[get_property STATUS.CORE_STATUS $ila]"
}
set data [upload_hw_ila_data $ila]
if {$data eq ""} {error "ILA did not capture data"}
set out [file join $root output diag_sdo_raw ila_41_j1_chip0_20261030.csv]
write_hw_ila_data -force -csv_file $out $data
puts "SDO_ILA_CSV=$out"
close_hw_manager
