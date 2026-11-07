# Provisional build constraints. Physical I/O is automatically assigned by Quartus.
# Zero external delays model ideal same-clock source/capture endpoints only.
# Replace these assumptions with the actual board interface before hardware use.
# TimeQuest 20.1 uses picosecond precision. 13.333 ns is slightly stricter than
# the exact 75 MHz period and avoids recurring-decimal truncation warnings.
create_clock -name clk -period 13.333 [get_ports {clk}]
derive_clock_uncertainty
set_input_delay -clock clk -max 0.0 [get_ports {rst rd_req clear_status}]
set_input_delay -clock clk -min 0.0 [get_ports {rst rd_req clear_status}]
set_output_delay -clock clk -max 0.0 [all_outputs]
set_output_delay -clock clk -min 0.0 [all_outputs]
# Only the asynchronous pad-to-first-stage path is excluded. The synchronizer
# stage-to-stage path remains a timed synchronous path.
set_false_path -from [get_ports {uart_rx_i}] -to [get_registers {*sync_inst*rx_meta}]
