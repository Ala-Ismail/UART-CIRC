# Environment supplied by run.ps1. Do not downgrade assertion failures.
onerror {quit -force -code 1}
onbreak {quit -force -code 1}
set BreakOnAssertion 2
set command [list vsim -t 1ps -wlf $env(UART_WAVE)]
if {[info exists env(UART_GENERICS)]} {
    foreach parameter $env(UART_GENERICS) {lappend command $parameter}
}
lappend command work.$env(UART_TEST)
eval $command
if {$env(UART_LOG_WAVES) eq "1"} {log -r /*}
run -all
quit -force -code 0
