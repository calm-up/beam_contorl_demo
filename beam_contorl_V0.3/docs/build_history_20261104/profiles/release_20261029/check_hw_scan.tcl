open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target [lindex [get_hw_targets] 0]
set device [lindex [get_hw_devices] 0]
foreach prop {BSCAN_SWITCH_USER_MASK JTAG_CLOCK_FREQ_HZ PROGRAM.FILE PROBES.FILE} {
    if {![catch {get_property $prop $device} value]} { puts "$prop=$value" }
}
foreach target [get_hw_targets] {
    foreach prop {FREQUENCY PARAM.FREQUENCY} {
        if {![catch {get_property $prop $target} value]} { puts "TARGET_$prop=$value" }
    }
}
close_hw_target
disconnect_hw_server
close_hw_manager
