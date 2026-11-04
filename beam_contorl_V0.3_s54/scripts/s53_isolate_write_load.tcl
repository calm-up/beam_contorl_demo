set root [file normalize [file join [file dirname [info script]] ..]]
set outdir [file join $root output s53 isolate_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
file mkdir $outdir
foreach key {PYTHONHOME PYTHONPATH} {if {[info exists ::env($key)]} {unset ::env($key)}}
set bridge ""
try {
 set bridge [open "|D:/anaconda/python.exe -u [file join $root scripts sdo_read_serial_bridge_20261031.py]" r+]
 if {[gets $bridge ready]<0 || $ready ne "READY"} {error "COM5 unavailable"}
 open_hw_manager
 connect_hw_server -url localhost:3121
 open_hw_target [lindex [get_hw_targets *] 0]
 set dev [lindex [get_hw_devices xc7a200t*] 0]
 current_hw_device $dev
 set_property PROBES.FILE [file join $root output s53 beam_control_v03_debug.ltx] $dev
 refresh_hw_device $dev
 foreach candidate [get_hw_ilas] {
  if {[llength [get_hw_probes rx_csb_o_OBUF -of_objects $candidate]]} {set pins $candidate}
  if {[llength [get_hw_probes read_done -of_objects $candidate]]} {set result $candidate}
 }
 proc capture {tag command trigger} {
  global pins result bridge outdir
  reset_hw_ila $pins
  set_property CONTROL.DATA_DEPTH 1024 $pins
  set_property CONTROL.TRIGGER_POSITION 64 $pins
  set_property CONTROL.TRIGGER_CONDITION AND $pins
  foreach probe {rx_csb_o_OBUF rx_ldb_o_OBUF} {
   set_property TRIGGER_COMPARE_VALUE "eq1'bX" [get_hw_probes $probe -of_objects $pins]
  }
  set_property TRIGGER_COMPARE_VALUE "eq1'b0" [get_hw_probes $trigger -of_objects $pins]
  run_hw_ila $pins
  set reading [string match "READ*" $command]
  if {$reading} {
   reset_hw_ila $result
   set_property CONTROL.DATA_DEPTH 1024 $result
   set_property CONTROL.TRIGGER_POSITION 128 $result
   set_property TRIGGER_COMPARE_VALUE "eq1'bX" [get_hw_probes read_done -of_objects $result]
   set_property TRIGGER_COMPARE_VALUE "eq1'b1" [get_hw_probes read_busy -of_objects $result]
   run_hw_ila $result
  }
  puts $bridge $command
  flush $bridge
  if {[gets $bridge sent]<0 || $sent ne "SENT $command"} {error "Serial failed $tag"}
  wait_on_hw_ila -timeout 3 $pins
  set data [upload_hw_ila_data $pins]
  write_hw_ila_data -force -csv_file [file join $outdir ${tag}_pins.csv] $data
  if {$reading} {
   wait_on_hw_ila -timeout 3 $result
   set data [upload_hw_ila_data $result]
   write_hw_ila_data -force -csv_file [file join $outdir ${tag}_result.csv] $data
  }
  puts "CAPTURE $tag $command"
  flush stdout
 }
 puts $bridge RESET
 flush $bridge
 if {[gets $bridge ack]<0 || $ack ne "SENT RESET"} {error "Reset send failed"}
 after 2000
 capture init_control "READ 3 4 0" rx_csb_o_OBUF
 capture init_rxps "READ 3 5 131" rx_csb_o_OBUF
 capture init_rxatt "READ 3 7 1" rx_csb_o_OBUF
 capture baseline "READ 3 2 1" rx_csb_o_OBUF
 set baseline_file [open [file join $outdir baseline_result.csv] r]
 set baseline_text [read $baseline_file]
 close $baseline_file
 set valid 0
 foreach row [lrange [split $baseline_text "\n"] 2 end] {
  set cells [split [string trim $row] ,]
  if {[lindex $cells 17] eq "1" && [lindex $cells 16] eq "0"} {set valid 1}
 }
 if {!$valid} {error "BASELINE_INVALID: $outdir; separation experiment stopped"}
 foreach rep {1 2 3} {
  foreach data {040 080} {
   set tag r${rep}_d${data}
   capture ${tag}_write "WRITE 3 321$data" rx_csb_o_OBUF
   capture ${tag}_before "READ 3 2 1" rx_csb_o_OBUF
   capture ${tag}_load "LOAD" rx_ldb_o_OBUF
   capture ${tag}_after "READ 3 2 1" rx_csb_o_OBUF
  }
 }
 puts "ISOLATE_DIR=$outdir"
} finally {
 if {$bridge ne ""} {close $bridge}
 catch {close_hw_manager}
}
