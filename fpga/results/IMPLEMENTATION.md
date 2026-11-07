# Quartus implementation results

Date: 2026-11-07. Quartus Prime Lite 20.1.1 Build 720; device
**10M16SAE144C8G**; Aggressive Area mode; 512-byte FIFO. The complete 32-test
ModelSim gate passed on the source hashes used for these builds.

## First successful synthesis result

The first successful 4 Mbaud synthesis pass was reported before changing the
RAM setting: **279 LEs, 246 combinational functions, 167 registers, 4096 memory
bits, and 79 pins**. Quartus reported zero errors and one RAM pass-through
warning. See [FIRST_PASS.md](FIRST_PASS.md) and
[first-map-4m.json](first-map-4m.json) for the preserved reference.

Disabling inferred RAM pass-through logic for unreachable simultaneous
same-address accesses produced a clean mapping pass at **247 LEs and 140
registers**. No RTL architecture change followed the first resource report.
Fitting packs eight registers into RAM and changes logic packing, giving the
final figures below. Mapping estimates and fitted counts are distinct results.

## Fitted resource utilization

| Resource | Available | 4 Mbaud | Utilization | 115200 baud |
| --- | --- | --- | --- | --- |
| Logic elements | 15,840 | **241** | **1.52%** | 249 |
| Combinational functions | 15,840 | 233 | 1.47% | 241 |
| Dedicated logic registers | 15,840 | **132** | **0.83%** | 139 |
| M9K blocks | 61 | **1** | **1.64%** | 1 |
| Logical memory bits | 562,176 | **4,096** | **0.73%** | 4,096 |
| I/O pins | 101 | **79** | **78.22%** | 79 |
| Embedded 9-bit multipliers | 90 | 0 | 0% | 0 |
| PLLs | 1 | 0 | 0% | 0 |
| UFM / ADC blocks | 1 / 1 | 0 / 0 | 0% / 0% | 0 / 0 |

The RAM is one 512-by-8 simple dual-port memory in one M9K block. I/O count
includes the 48 exported diagnostic-counter bits. There is no asynchronous
memory read or data-array reset. No latches were reported in the synthesis logs.

At 4 Mbaud, the fitter reports 42 four-input functions, 81 three-input functions,
110 functions with two or fewer inputs, and eight register-only LEs. Of the
233 combinational LEs, 86 use arithmetic mode and 147 use normal mode. These
counts describe physical LUT usage; they do not imply every multi-level logic
cone depends on four or fewer signals. Further area changes are deferred after
this recorded result.

## Timing

The clock constraint is **13.333 ns**, slightly stricter than the exact 75 MHz
period and representable at TimeQuest's picosecond precision. The reports cover
Slow 1200 mV at 85 C, Slow 1200 mV at 0 C, and Fast 1200 mV at 0 C.

| Result | 4 Mbaud | 115200 baud |
| --- | --- | --- |
| Worst reported Fmax | **91.21 MHz** | **91.44 MHz** |
| Worst setup slack | **+2.369 ns** | **+2.397 ns** |
| Worst hold slack | **+0.102 ns** | **+0.110 ns** |
| Worst minimum-pulse-width slack | +5.931 ns | +5.931 ns |
| Setup/hold/pulse-width checks | PASS: all nine checks | PASS: all nine checks |
| Total negative slack | 0 ns | 0 ns |
| Timing Analyzer errors / warnings | 0 / 0 | 0 / 0 |

TimeQuest reports fully constrained setup and hold requirements and identifies
one two-register synchronizer chain. Only the pad-to-first-stage asynchronous
RX path is excepted; stage-to-stage timing remains enabled. No measured MTBF
claim is made from the tool's statistical model.

## I/O and warning status

Initial automatic pin choices were back-annotated into
[provisional_pins.qsf](../provisional_pins.qsf). The selected I/O standard is
provisional **3.3-V LVTTL**. Configuration banks are explicitly set to 3.3 V.
External input/output delays are provisionally zero relative to the system
clock. These assumptions must be replaced or validated for the actual board.

Synthesis, assembly, and timing analysis finish with zero errors/warnings.
Fitting succeeds with advisories, so this is not a zero-warning board release:

- **292013, LogicLock licensing:** explicitly accepted by the user; no LogicLock
  regions are used and balancing constraints are disabled.
- **16562, single-supply power review:** deferred by the user for now.
- **169177, 3.3-V input interface requirements:** retained for eventual board
  electrical validation of the five input pins.
- **215044, missing board thermal model:** power-analysis advisory deferred by
  the user. The vectorless estimates are 315.77 mW at 4 Mbaud and 315.24 mW at
  115200 baud, with low activity-data confidence. These are estimates, not board
  power measurements or thermal sign-off.

The 115200-baud fitter also reports **15714**, incomplete I/O assignments. Its
details are retained in the fitter's I/O Assignment Warnings table and in the raw
diagnostics in `implementation.json`. This is separate from timing analysis,
which finishes with zero warnings and fully constrained setup/hold paths.

## Files and reproduction

Open the portable GUI project [uart_rx_circular.qpf](../uart_rx_circular.qpf),
with its [QSF](../uart_rx_circular.qsf) and [SDC](../uart_rx_circular.sdc).
It selects the 4 Mbaud configuration using relative source paths. Project loading
was checked with `check_project.tcl`; the compiled builds are in separate output
directories.

From the repository root:

```powershell
.\fpga\build.ps1 -BaudRate 4000000 -Stage All
.\fpga\build.ps1 -BaudRate 115200 -Stage All
.\fpga\report_results.ps1
```

The build script rechecks simulation hashes before running Quartus. It runs
mapping, fitting, timing, assembly, and power analysis; it never invokes the
programmer. Review required warnings remain visible and classified in the logs.
The normalized [implementation.json](implementation.json) includes current
resource figures, all nine timing checks, raw summaries, warnings, and the
source/build manifests. Raw tool outputs and generated programming files remain
under `build/quartus/4m` and `build/quartus/115200`. No FPGA was programmed.
