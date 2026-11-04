set root [file normalize [file join [file dirname [info script]] ..]]
set outdir [file join $root output s51 attenuation_20261031]
file mkdir $outdir
set python D:/anaconda/python.exe
foreach name {PYTHONHOME PYTHONPATH} {
    if {[info exists ::env($name)]} {unset ::env($name)}
}
set bridge [open "|$python -u [file join $root scripts sdo_read_serial_bridge_20261031.py]" r+]
if {[gets $bridge ready] < 0 || $ready ne "READY"} {
    error "COM5 bridge failed: $ready"
}
puts "COM5_RESERVED"

open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target [lindex [get_hw_targets *] 0]
set dev [lindex [get_hw_devices xc7a200t*] 0]
if {$dev eq ""} {error "xc7a200t not detected"}
current_hw_device $dev
set_property PROBES.FILE [file join $root output s51 beam_control_v03_debug.ltx] $dev
refresh_hw_device $dev
set ila ""
foreach candidate [get_hw_ilas] {
    if {[llength [get_hw_probes rx_csb_o_OBUF -of_objects $candidate]]} {
        set ila $candidate
        break
    }
}
if {$ila eq ""} {error "Array ILA not found"}

foreach {name request} {
    rxatt_00 {READ 3 7 0}
    rxatt_31 {READ 3 7 31}
    rf1_att_00 {SET 3 0 0}
    rf1_att_31 {SET 3 0 31}
} {
    reset_hw_ila $ila
    set_property CONTROL.TRIGGER_CONDITION AND $ila
    set_property CONTROL.DATA_DEPTH 1024 $ila
    set_property CONTROL.TRIGGER_POSITION 64 $ila
    set_property TRIGGER_COMPARE_VALUE "eq1'b0" [get_hw_probes rx_csb_o_OBUF -of_objects $ila]
    run_hw_ila $ila
    puts "ARMED $name request=$request"
    flush stdout
    puts $bridge $request
    flush $bridge
    if {[gets $bridge sent] < 0} {error "COM5 bridge closed at $name"}
    puts $sent
    wait_on_hw_ila -timeout 2 $ila
    set data [upload_hw_ila_data $ila]
    if {$data eq ""} {error "No ILA capture at $name"}
    set capture [file join $outdir "$name.csv"]
    write_hw_ila_data -force -csv_file $capture $data
    puts "CAPTURED $capture"
    flush stdout
}
close_hw_manager
close $bridge
puts "ATTENUATION_CAPTURE_PASS"
