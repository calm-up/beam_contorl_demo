set root [file normalize [file join [file dirname [info script]] ..]]
set capture_name [expr {[info exists ::env(V03_CAPTURE_NAME)] ?
    $::env(V03_CAPTURE_NAME) : "read_values"}]
set outdir [file join $root output s51 $capture_name]
file mkdir $outdir
set addresses [expr {[info exists ::env(V03_CAPTURE_ADDRESSES)] ?
    $::env(V03_CAPTURE_ADDRESSES) : {86 87 92 97}}]
set chips [expr {[info exists ::env(V03_CAPTURE_CHIPS)] ?
    $::env(V03_CAPTURE_CHIPS) : {0 1 2 3}}]
set target_byte "02"
if {[info exists ::env(V03_CAPTURE_BYTE)]} {
    set target_byte $::env(V03_CAPTURE_BYTE)
}
set python D:/anaconda/python.exe
foreach name {PYTHONHOME PYTHONPATH} {
    if {[info exists ::env($name)]} {unset ::env($name)}
}

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
    if {[llength [get_hw_probes response_byte_valid -of_objects $candidate]]} {
        set ila $candidate
        break
    }
}
if {$ila eq ""} {error "Protocol ILA or response_byte_valid probe not found"}
puts "PROTOCOL_ILA=$ila"
puts "PROBES=[get_hw_probes -of_objects $ila]"
foreach address $addresses {
    foreach chip $chips {
        reset_hw_ila $ila
        set_property CONTROL.TRIGGER_CONDITION AND $ila
        set_property CONTROL.DATA_DEPTH 1024 $ila
        set_property CONTROL.TRIGGER_POSITION 128 $ila
        set_property TRIGGER_COMPARE_VALUE "eq1'b1" [get_hw_probes response_byte_valid -of_objects $ila]
        set_property TRIGGER_COMPARE_VALUE "eq8'h$target_byte" [get_hw_probes response_byte -of_objects $ila]
        run_hw_ila $ila
        puts "ARMED chip=$chip address=$address"
        flush stdout
        exec $python [file join $root scripts attenuation_live_20261030.py] read \
            --chip $chip --function 4 --address $address --no-ack
        wait_on_hw_ila -timeout 2 $ila
        set data [upload_hw_ila_data $ila]
        if {$data eq ""} {error "No response capture chip=$chip address=$address"}
        set capture [file join $outdir [format "chip%d_addr%03d.csv" $chip $address]]
        write_hw_ila_data -force -csv_file $capture $data
        puts "CAPTURED $capture"
        flush stdout
    }
}
close_hw_manager
