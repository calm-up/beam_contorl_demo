# Batch-read J1 Control_Reg addresses with the existing s50 BIT and array ILA.
# Optional environment variables: V03_SWEEP_ADDRESSES (Tcl list), V03_SWEEP_CHIPS.
set root [file normalize [file join [file dirname [info script]] ..]]
set sweep_name [expr {[info exists ::env(V03_SWEEP_NAME)] ? $::env(V03_SWEEP_NAME) : "sweep_20261031"}]
set outdir [file join $root output s50 $sweep_name]
file mkdir $outdir
set python D:/anaconda/python.exe
# Vivado prepends its bundled Python 3.8 paths; do not pass them to Anaconda.
foreach name {PYTHONHOME PYTHONPATH} {
    if {[info exists ::env($name)]} {
        set saved_python_env($name) $::env($name)
        unset ::env($name)
    }
}
set addresses [expr {[info exists ::env(V03_SWEEP_ADDRESSES)] ? $::env(V03_SWEEP_ADDRESSES) : {}}]
if {[llength $addresses] == 0} {
    for {set address 0} {$address < 128} {incr address} {lappend addresses $address}
}
set chips [expr {[info exists ::env(V03_SWEEP_CHIPS)] ? $::env(V03_SWEEP_CHIPS) : {0 1 2 3}}]
set fh [open [file join $root ccar10405l_expected_frames.mem] r]
set oracle [split [string trim [read $fh]] "\n"]
close $fh
set summary [open [file join $outdir summary.csv] w]
puts $summary "chip,address,expected,result"
flush $summary

open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target [lindex [get_hw_targets *] 0]
set dev [lindex [get_hw_devices xc7a200t*] 0]
if {$dev eq ""} {error "xc7a200t not detected"}
current_hw_device $dev
set_property PROBES.FILE [file join $root output s50 beam_control_v03_debug.ltx] $dev
refresh_hw_device $dev
set ila [lindex [get_hw_ilas] 0]
if {$ila eq ""} {error "Array ILA not found; program s50 BIT first"}
set_property CONTROL.DATA_DEPTH 1024 $ila
set_property CONTROL.TRIGGER_POSITION 64 $ila

set total 0
set passed 0
set failed 0
set stop 0
foreach address $addresses {
    if {$address < 0 || $address > 127} {error "Invalid control address $address"}
    scan [lindex $oracle $address] %x frame
    set expected [expr {$frame & 255}]
    foreach chip $chips {
        if {$chip < 0 || $chip > 3} {error "Invalid chip $chip"}
        set capture [file join $outdir [format "chip%d_addr%03d.csv" $chip $address]]
        reset_hw_ila $ila
        set_property TRIGGER_COMPARE_VALUE "eq1'b0" [get_hw_probes rx_csb_o_OBUF -of_objects $ila]
        run_hw_ila $ila
        puts [format "ARMED chip=%d address=%d expected=%02X" $chip $address $expected]
        flush stdout
        exec $python [file join $root scripts attenuation_live_20261030.py] read \
            --chip $chip --function 4 --address $address --no-ack
        wait_on_hw_ila -timeout 1 $ila
        if {[catch {set data [upload_hw_ila_data $ila]} upload_error]} {
            puts $summary "$chip,$address,[format %02X $expected],NO_CAPTURE"
            flush $summary
            puts "NO_CAPTURE $upload_error"
            set stop 1
            break
        }
        write_hw_ila_data -force -csv_file $capture $data
        set verify [list $python [file join $root scripts verify_sdo_read_capture_20261031.py] \
            $capture $chip $address [format %02X $expected]]
        set verify_status [catch {exec {*}$verify} result]
        set result [lindex [split [string trim $result] "\n"] 0]
        puts $result
        puts $summary "$chip,$address,[format %02X $expected],$result"
        flush $summary
        incr total
        if {!$verify_status} {incr passed} else {incr failed}
        if {[string first "reconstructed=FFFFFF" $result] >= 0} {
            puts "STOP_SDO_ALL_HIGH"
            set stop 1
            break
        }
        if {[string first "INVALID_CAPTURE" $result] >= 0 ||
            [string first "INVALID_SDI" $result] >= 0} {
            puts "STOP_CAPTURE_INVALID"
            set stop 1
            break
        }
    }
    if {$stop} {break}
}
puts "SWEEP_RESULT total=$total passed=$passed failed=$failed stopped=$stop"
close $summary
close_hw_manager
foreach name [array names saved_python_env] {set ::env($name) $saved_python_env($name)}
