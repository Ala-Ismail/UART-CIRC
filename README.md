# UART-CIRC

FPGA UART receiver with a circular FIFO, using a Quartus and ModelSim development
flow. VHDL RTL and self-checking testbenches are implemented and pass the
ModelSim simulation gate after an RTL area and fan-in optimization. FPGA
implementation and timing analysis have completed for 10M16SAE144C8G with
provisional I/O. The FPGA has not been programmed.

See [USER_Manual.md](USER_Manual.md) for setup, interface use, VHDL integration,
simulation, Quartus builds, and troubleshooting.

## Design targets

| Item | Specification |
| --- | --- |
| Implementation language | VHDL-2008 for RTL and self-checking testbenches (`.vhd`) |
| Target FPGA | Altera MAX 10, 10M16SAE144C8G |
| System clock | 75 MHz |
| UART format | 8N1, LSB first |
| Maximum intended line rate | 4 Mbaud; ModelSim verification passed, hardware validation pending |
| Default baud parameter | 115200 baud |
| FIFO capacity | 512 bytes (4096 data bits), all locations usable |
| FIFO pointers / occupancy | 9-bit read and write pointers; 10-bit occupancy counter |
| Capacity at 4 Mbaud | 1.28 ms nominal buffering; 400,000 payload bytes/s |
| Full FIFO behavior | Drop arriving byte; set sticky overflow flag and count drops |
| Empty read behavior | Ignore request; no valid response and no underflow flag |

## Current status

Status as of 2026-11-07:

| Stage | Status | Evidence / remaining work |
| --- | --- | --- |
| Design documentation | Complete | [Architecture and interface contract](UART-circular.md) |
| Test planning | Complete | [Test cases and acceptance criteria](UART-circular-test-plan.md) |
| Agent workflow instructions | Complete | [.agent](.agent), discovered through [AGENTS.md](AGENTS.md) |
| Local tool discovery | Complete | Quartus and ModelSim executables located; version commands succeeded |
| RTL and testbench generation | Complete | [VHDL top level](rtl/uart_rx_circular.vhd), unit tests and serial scoreboard in `sim/` |
| RTL area/fan-in review | Complete | Reduced timer widths, fixed shift wiring and shared arithmetic; [review](rtl/AREA_REVIEW.md); fitted results recorded |
| ModelSim compilation and elaboration | Complete | Internal signals replace output-port reads; all configurations compile/elaborate with zero warnings/errors |
| ModelSim regression and functional coverage | Complete | All 32 configurations pass after the compatibility fix; only the latest verified result set is retained |
| Quartus device preflight | Complete | Installed database includes MAX 10 and 10M16SAE144C8G; zero errors/warnings |
| Quartus project and constraints | Complete for provisional build | Portable [QPF](fpga/uart_rx_circular.qpf), [QSF](fpga/uart_rx_circular.qsf), and [SDC](fpga/uart_rx_circular.sdc); loading validated |
| Quartus synthesis and mapping | Complete at both baud rates | First successful 4 Mbaud pass: 279 LEs/167 registers (one RAM warning); clean mapping: 247 LEs/140 registers; [first-pass report](fpga/results/FIRST_PASS.md) |
| Quartus fitting and timing analysis | Complete for provisional constraints | 4 Mbaud: 241 LEs, 132 registers, one M9K; Fmax 91.21 MHz; all timing checks pass; [implementation report](fpga/results/IMPLEMENTATION.md) |
| Quartus assembly and power analysis | Complete with deferred advisories | Programming files generated; no hardware programmed; power warnings deferred by user; board validation pending |
| Hardware validation | Not run | Requires a completed FPGA build and target board |

ModelSim and Quartus mapping, fitting, timing, assembly, and power analysis have
run successfully. Mapping, assembly and timing report zero errors/warnings;
fitter and power advisories remain visible. LogicLock and power advisories are
accepted/deferred by the user. I/O is provisional and board validation has not
run. Simulation coverage is functional coverage from cases and assertions;
no code-coverage percentage is claimed.

At 4 Mbaud, fitted utilization is **241/15,840 LEs (1.52%)**, **132 registers**,
**1/61 M9Ks**, **4096 data bits**, and **79/101 pins**. Worst setup slack is
**+2.369 ns**, worst hold slack **+0.102 ns**, and reported Fmax **91.21 MHz**.
The 115200-baud configuration uses 249 LEs and 139 registers and also passes
timing. See the [full report](fpga/results/IMPLEMENTATION.md) for assumptions,
diagnostics, and both configurations.

The current RTL, including the Quartus compatibility fix, passes all 32 required
configurations with matching source hashes and zero warnings/errors. The matrix covers both 115200 baud and
4 Mbaud at five transmitter mismatch values (-2%, -1%, 0%, +1%, +2%) and 32 start
offsets per value, sending every byte plus random bursts. Ten stress seeds each
complete 10,220 frames with errors, resets, status clears, and consumer stalls.
Overflow tests include a full FIFO with a simultaneous read/arrival and a
600-frame UART burst without reads, retaining 512 bytes and counting 88 drops.

## Local toolchain

| Tool | Detected version | Executable directory |
| --- | --- | --- |
| Quartus Prime Lite | 20.1.1 Build 720 | `C:\intelFPGA_lite\20.1\quartus\bin64` |
| ModelSim Intel FPGA Starter Edition | 2020.1 | `C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem` |

ModelSim commands are available on `PATH`. Quartus commands currently require
their full paths; `QUARTUS_ROOTDIR` points to
`C:\intelFPGA_lite\20.1\quartus`. These are the detected paths on the current
development machine, not portable installation requirements.

## Required development flow

Generate VHDL-2008 RTL and self-checking testbenches, then compile with
`vcom -2008`, elaborate, and simulate in ModelSim. Configure Quartus for
VHDL-2008. Resolve all errors, warnings, assertion failures, scoreboard
mismatches, and timeouts, and complete the applicable regression and coverage
requirements before running Quartus synthesis or FPGA mapping.

After that gate passes, run Quartus Analysis & Synthesis, followed by fitting and
TimeQuest timing analysis. RTL changes require renewed simulation verification
before implementation resumes. See [.agent](.agent) for the complete rules.

Run instructions and the source-hash gate are documented in [sim/README.md](sim/README.md).
Only the latest complete verified simulation set is retained. Use
`sim/clean_results.ps1` after a passing gate to remove superseded runs while
preserving all suite directories referenced by the current gate.

Quartus implementation is authorized for 10M16SAE144C8G with arbitrary provisional
I/O. The first successful mapping resource report was recorded and reported before
changing the inferred RAM pass-through setting. Final board sign-off requires actual electrical
constraints and pin assignments; no hardware programming is authorized.
