open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices xc7a200t_0] 0]
if {$dev eq ""} {error "xc7a200t_0 not found"}
current_hw_device $dev
puts "BOOT_START=[clock format [clock seconds] -format {%H:%M:%S}]"
set boot_result [catch {boot_hw_device -timeout 60 $dev} boot_message]
puts "BOOT_END=[clock format [clock seconds] -format {%H:%M:%S}]"
puts "BOOT_RESULT=$boot_result"
puts "BOOT_MESSAGE=$boot_message"
refresh_hw_device $dev
foreach property [list_property $dev] {
    if {[regexp {^REGISTER\.CONFIG_STATUS(\.BIT(00|04|08|09|10|11|12|13|14|15|25|29)|$)|^REGISTER\.BOOT_STATUS(\.BIT(00|01|04|05)|$)} $property]} {
        puts "STATUS $property=[get_property $property $dev]"
    }
}
close_hw_manager
