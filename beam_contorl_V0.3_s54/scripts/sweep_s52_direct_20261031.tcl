set root [file normalize [file join [file dirname [info script]] ..]]
set outdir [file join $root output s52 direct_sweep]
file mkdir $outdir
set python D:/anaconda/python.exe
foreach key {PYTHONHOME PYTHONPATH} {if {[info exists ::env($key)]} {unset ::env($key)}}
set input [open [file join $root output register_baseline_20261031.csv] r]
set records [split [string trim [read $input]] "\n"]
close $input
set summary [open [file join $outdir summary.csv] w]
puts $summary "chip,table,function,address,expected,result"
flush $summary
set bridge [open "|$python -u [file join $root scripts sdo_read_serial_bridge_20261031.py]" r+]
if {[gets $bridge ready] < 0 || $ready ne "READY"} {error "COM5 unavailable: $ready"}
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target [lindex [get_hw_targets *] 0]
set dev [lindex [get_hw_devices xc7a200t*] 0]
if {$dev eq ""} {error "xc7a200t not detected"}
current_hw_device $dev
set_property PROBES.FILE [file join $root output s52 beam_control_v03_debug.ltx] $dev
refresh_hw_device $dev
set ila ""
foreach candidate [get_hw_ilas] {
    if {[llength [get_hw_probes read_done -of_objects $candidate]]} {set ila $candidate; break}
}
if {$ila eq ""} {error "read_done probe missing; verify s52 BIT/LTX"}
set total 0
foreach record [lrange $records 1 end] {
    lassign [split [string trim $record] ,] chip table function address expected bits
    if {[info exists ::env(V03_TEST_LIMIT)] && $total >= $::env(V03_TEST_LIMIT)} {break}
    reset_hw_ila $ila
    set_property CONTROL.TRIGGER_CONDITION AND $ila
    set_property CONTROL.DATA_DEPTH 1024 $ila
    set_property CONTROL.TRIGGER_POSITION 128 $ila
    set_property TRIGGER_COMPARE_VALUE "eq1'b1" [get_hw_probes read_done -of_objects $ila]
    run_hw_ila $ila
    puts $bridge "READ $chip $function $address"
    flush $bridge
    if {[gets $bridge sent] < 0 || $sent ne "SENT READ $chip $function $address"} {error "Serial bridge failed: $sent"}
    wait_on_hw_ila -timeout 1 $ila
    set data [upload_hw_ila_data $ila]
    if {$data eq ""} {error "Capture failed: $chip $table $address"}
    set path [file join $outdir [format "chip%d_%s_%03d.csv" $chip $table $address]]
    write_hw_ila_data -force -csv_file $path $data
    set code [catch {exec $python [file join $root scripts verify_direct_register_capture_20261031.py] $path $chip $function $address $expected} result]
    puts $summary "$chip,$table,$function,$address,$expected,$result"
    flush $summary
    puts "$chip $table $address $result"
    flush stdout
    incr total
    if {$code} {error "Direct register comparison failed after $total captures"}
}
close $summary
close $bridge
close_hw_manager
puts "DIRECT_SWEEP_PASS count=$total"
