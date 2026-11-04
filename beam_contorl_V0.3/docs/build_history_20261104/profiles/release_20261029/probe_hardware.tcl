open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets]
puts "HW_TARGETS=$targets"
foreach target $targets {
    open_hw_target $target
    puts "TARGET=$target DEVICES=[get_hw_devices]"
    foreach device [get_hw_devices] {
        puts "DEVICE=$device PART=[get_property PART $device]"
    }
    close_hw_target
}
disconnect_hw_server
close_hw_manager
