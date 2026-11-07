# Quartus flow

Target: MAX 10 **10M16SAE144C8G**, Quartus Prime Lite 20.1.1. The user has authorized
arbitrary I/O for this build. Projects use automatic pin placement, provisional
3.3-V LVTTL, and ideal same-clock external I/O delays of zero. The source SDC is
[uart_rx_circular.sdc](uart_rx_circular.sdc); it defines the 75 MHz clock,
uncertainty, I/O delays, and the asynchronous input-to-first-stage exception.
The synchronizer's stage-to-stage path remains timed. For GUI use, open
[uart_rx_circular.qpf](uart_rx_circular.qpf); the QSF uses relative source paths.
These project files and the SDC are not ignored generated outputs. Initial
automatic pin choices are saved in [provisional_pins.qsf](provisional_pins.qsf).
See the [user manual](../USER_Manual.md) for interface and integration examples.

Run from the repository root:

```powershell
.\fpga\build.ps1 -BaudRate 4000000 -Stage Map
.\fpga\build.ps1 -BaudRate 4000000 -Stage Fit
.\fpga\build.ps1 -BaudRate 4000000 -Stage Timing
```

`-Stage All` performs mapping, fitting, timing, assembly, and power analysis in
order. `-BaudRate 115200` builds the
default-rate configuration in a separate directory. Every invocation rechecks
the simulation gate and source hashes. Errors and unresolved mapping warnings
stop the flow. Other diagnostic analysis can continue with warnings explicitly
recorded; this does not make a warning-bearing build clean. Only LogicLock 292013
and power 16562/215044 are accepted/deferred by the user.
An initial failed synthesis attempt exposed unsupported output-port reads in
the Quartus front end; internal signals resolve that compatibility issue and the
full ModelSim regression has passed again.

`check_devices.tcl` confirms MAX 10/10M16 entries in the installed device database.
`create_project.tcl` generates the VHDL-2008 project, area-oriented settings and
verified parameters. Sources, project files, logs and tool outputs are kept under
`build/quartus/4m` or `build/quartus/115200`. The first passing mapping resource
summary and source hashes are preserved in `fpga/results/first-map-<rate>.json`
and reported before further optimization.

The current [implementation report](results/IMPLEMENTATION.md) and normalized
[results](results/implementation.json) record successful builds at both baud
rates. `report_results.ps1` validates fitted reports and all nine nonnegative
timing checks per build and retains diagnostics. `check_project.tcl` validates
loading the portable GUI project without compiling it.

Automatic pins and provisional electrical constraints are for implementation
estimates. Replace them with the actual board requirements before hardware use
or final board timing sign-off. This flow does not program hardware.
