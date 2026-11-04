set root [file normalize [file join [file dirname [info script]] ..]]
set python D:/anaconda/python.exe
foreach key {PYTHONHOME PYTHONPATH} {if {[info exists ::env($key)]} {unset ::env($key)}}
set bridge [open "|$python -u [file join $root scripts sdo_read_serial_bridge_20261031.py]" r+]
if {[gets $bridge ready] < 0 || $ready ne "READY"} {error "COM5 unavailable"}
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target [lindex [get_hw_targets *] 0]
set dev [lindex [get_hw_devices xc7a200t*] 0]
current_hw_device $dev
set_property PROBES.FILE [file join $root output s52 beam_control_v03_debug.ltx] $dev
refresh_hw_device $dev
set ila ""
foreach candidate [get_hw_ilas] {if {[llength [get_hw_probes read_done -of_objects $candidate]]} {set ila $candidate; break}}
foreach channel {0 1 2 3} {
    reset_hw_ila $ila
    set_property CONTROL.DATA_DEPTH 1024 $ila
    set_property CONTROL.TRIGGER_POSITION 128 $ila
    set_property TRIGGER_COMPARE_VALUE "eq1'b1" [get_hw_probes read_done -of_objects $ila]
    run_hw_ila $ila
    puts $bridge "READ 3 2 $channel"
    flush $bridge
    if {[gets $bridge sent] < 0} {error "bridge failed"}
    wait_on_hw_ila -timeout 1 $ila
    set data [upload_hw_ila_data $ila]
    if {$data eq ""} {error "No read_done channel=$channel"}
    set path [file join $root output s52 [format "chip3_dynamic_channel%d.csv" $channel]]
    write_hw_ila_data -force -csv_file $path $data
    puts "CAPTURED channel=$channel $path"
}
close $bridge
close_hw_manager
