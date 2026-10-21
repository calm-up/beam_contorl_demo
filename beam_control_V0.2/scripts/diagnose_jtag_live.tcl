open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets]
puts "JTAG_TARGETS=$targets"
foreach target $targets {
    current_hw_target $target
    report_property $target
    foreach hz {1000000 250000} {
        catch {close_hw_target $target}
        if {[catch {set_property PARAM.FREQUENCY $hz $target} msg]} {
            puts "SET_FREQ_FAILED requested=$hz message=$msg"
            continue
        }
        puts "SCAN_BEGIN target=$target requested_hz=$hz actual_hz=[get_property PARAM.FREQUENCY $target]"
        if {[catch {open_hw_target $target} msg]} {
            puts "SCAN_FAILED=$msg"
        } else {
            set devices [get_hw_devices -quiet]
            puts "SCAN_DEVICES=$devices"
            foreach device $devices {report_property $device}
            if {[llength $devices] > 0} {break}
        }
    }
}
disconnect_hw_server
close_hw_manager
exit
