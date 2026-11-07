# Read-only device-library check; no project, synthesis, or fitting is invoked.
package require ::quartus::device
puts "DEVICE_PREFLIGHT: installed families"
set families [get_family_list]
foreach family $families { puts "FAMILY: $family" }
if {[lsearch -exact $families "MAX 10"] < 0} {
    puts "DEVICE_PREFLIGHT: BLOCKED - MAX 10 support is not installed"
    exit 2
}
set parts [get_part_list -family "MAX 10"]
set candidates [lsearch -all -inline -glob $parts "10M16*"]
if {[llength $candidates] == 0} {
    puts "DEVICE_PREFLIGHT: BLOCKED - no 10M16 devices available"
    exit 2
}
foreach part $candidates { puts "10M16_PART: $part" }
puts "DEVICE_PREFLIGHT: PASS - full package and speed-grade selection still required"
