# Validate the portable GUI project without compiling it.
package require ::quartus::project
set here [file dirname [file normalize [info script]]]
project_open [file join $here uart_rx_circular]
if {[get_global_assignment -name DEVICE] ne "10M16SAE144C8G"} { error "Wrong device" }
if {[get_global_assignment -name TOP_LEVEL_ENTITY] ne "uart_rx_circular"} { error "Wrong top-level entity" }
if {[get_global_assignment -name SDC_FILE] ne "uart_rx_circular.sdc"} { error "Wrong SDC" }
puts "PORTABLE_PROJECT: PASS - 10M16SAE144C8G, uart_rx_circular, local SDC"
project_close
