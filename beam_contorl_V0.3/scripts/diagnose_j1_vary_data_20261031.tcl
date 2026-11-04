set root [file normalize [file join [file dirname [info script]] ..]]
set outdir [file join $root output s52 J1_vary_data_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
file mkdir $outdir
set python D:/anaconda/python.exe
foreach key {PYTHONHOME PYTHONPATH} {if {[info exists ::env($key)]} {unset ::env($key)}}
set bridge ""
try {
    set bridge [open "|$python -u [file join $root scripts sdo_read_serial_bridge_20261031.py]" r+]
    if {[gets $bridge ready] < 0 || $ready ne "READY"} {error "COM5 unavailable: $ready"}
    open_hw_manager
    connect_hw_server -url localhost:3121
    open_hw_target [lindex [get_hw_targets *] 0]
    set dev [lindex [get_hw_devices xc7a200t*] 0]
    if {$dev eq ""} {error "No FPGA"}
    current_hw_device $dev
    set_property PROBES.FILE [file join $root output s52 beam_control_v03_debug.ltx] $dev
    refresh_hw_device $dev
    set array_ila ""
    set result_ila ""
    foreach candidate [get_hw_ilas] {
        if {[llength [get_hw_probes rx_csb_o_OBUF -of_objects $candidate]]} {set array_ila $candidate}
        if {[llength [get_hw_probes read_done -of_objects $candidate]]} {set result_ila $candidate}
    }
    if {$array_ila eq "" || $result_ila eq ""} {error "Required s52 ILAs missing"}
    foreach chip {3} {
      foreach channel {1 0} {
       set baseout $outdir
       foreach attenuation {2 0 3 1} {
       set outdir [file join $baseout ch${channel}_att${attenuation}]
       file mkdir $outdir
       set stem "chip${chip}_channel${channel}"
       foreach op {write read} {
        reset_hw_ila $array_ila
        set_property CONTROL.TRIGGER_CONDITION AND $array_ila
        set_property CONTROL.DATA_DEPTH 1024 $array_ila
        set_property CONTROL.TRIGGER_POSITION 64 $array_ila
        set_property TRIGGER_COMPARE_VALUE "eq1'b0" [get_hw_probes rx_csb_o_OBUF -of_objects $array_ila]
        run_hw_ila $array_ila
        if {$op eq "read"} {
            reset_hw_ila $result_ila
            set_property CONTROL.TRIGGER_CONDITION AND $result_ila
            set_property CONTROL.DATA_DEPTH 1024 $result_ila
            set_property CONTROL.TRIGGER_POSITION 128 $result_ila
            set_property TRIGGER_COMPARE_VALUE "eq1'b1" [get_hw_probes read_done -of_objects $result_ila]
            set_property TRIGGER_COMPARE_VALUE "eq1'bX" [get_hw_probes read_error -of_objects $result_ila]
            run_hw_ila $result_ila
            set command "READ $chip 2 $channel"
        } else {set command "SET $chip $channel $attenuation"}
        puts $bridge $command
        flush $bridge
        if {[gets $bridge sent] < 0 || $sent ne "SENT $command"} {error "Serial send failed: $sent"}
        puts $sent
        wait_on_hw_ila -timeout 3 $array_ila
        set data [upload_hw_ila_data $array_ila]
        if {$data eq ""} {error "No $op pin capture"}
        write_hw_ila_data -force -csv_file [file join $outdir ${stem}_${op}_pins.csv] $data
        if {$op eq "read"} {
            wait_on_hw_ila -timeout 3 $result_ila
            set data [upload_hw_ila_data $result_ila]
            if {$data eq ""} {error "No read completion capture"}
            write_hw_ila_data -force -csv_file [file join $outdir ${stem}_read_result.csv] $data
        }
       }
       exec $python [file join $root scripts decode_chip3_rf1_recheck_20261031.py] $outdir $chip $channel $attenuation >@stdout
       puts "COMPLETE chip=$chip channel=$channel"
       flush stdout
       set outdir $baseout
       }
      }
    }
    puts "RECHECK_CAPTURE_DIR=$outdir"
} finally {
    if {$bridge ne ""} {close $bridge}
    catch {close_hw_manager}
}
