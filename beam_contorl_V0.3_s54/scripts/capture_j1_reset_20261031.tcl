set root [file normalize [file join [file dirname [info script]] ..]]
set output [file join $root output s52 j1_reset_20261031.csv]
set python D:/anaconda/python.exe
foreach name {PYTHONHOME PYTHONPATH} {if {[info exists ::env($name)]} {unset ::env($name)}}
set bridge ""
try {
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
    foreach candidate [get_hw_ilas] {
        if {[llength [get_hw_probes rx_rstn_o_OBUF -of_objects $candidate]]} {set ila $candidate; break}
    }
    if {$ila eq ""} {error "RX array ILA missing"}
    reset_hw_ila $ila
    set_property CONTROL.TRIGGER_CONDITION AND $ila
    set_property CONTROL.DATA_DEPTH 4096 $ila
    set_property CONTROL.TRIGGER_POSITION 128 $ila
    set_property TRIGGER_COMPARE_VALUE "eq1'b0" [get_hw_probes rx_rstn_o_OBUF -of_objects $ila]
    run_hw_ila $ila
    puts $bridge RESET
    flush $bridge
    if {[gets $bridge sent] < 0 || $sent ne "SENT RESET"} {error "Reset send failed"}
    wait_on_hw_ila -timeout 3 $ila
    set data [upload_hw_ila_data $ila]
    if {$data eq ""} {error "No reset waveform captured"}
    write_hw_ila_data -force -csv_file $output $data
    puts "RESET_CAPTURE=$output"
} finally {
    if {$bridge ne ""} {close $bridge}
    catch {close_hw_manager}
}
