# UART receiver simulation verification

## Configuration and current status

Verification date: 2026-11-07. Simulator: ModelSim Intel FPGA Starter Edition
2020.1, with VHDL-2008 compilation and 1 ps simulation precision. The clock
generator alternates 6666 ps and 6667 ps half-periods in a rational pattern,
averaging exactly 75 MHz. The primary UART rate is 4 Mbaud; default-rate tests
also run at 115200 baud. The FIFO depth is 512 bytes unless parameterized below.

The current RTL passes a fresh full regression: all 32 configurations, matching
source hashes, and zero warnings or errors. Changes reduce phase-register width,
replace the frame-length count with a four-bit bit timer and fixed shift wiring,
and simplify FIFO and diagnostic arithmetic. See the
[area review](../rtl/AREA_REVIEW.md) for details. The first Quartus attempt rejected
internal reads of output ports. Internal signals now replace those reads without
changing the interface or architecture, and all 32 configurations pass again.
The current source hashes and logs are recorded in `results/gate.json`. Quartus
implementation status and resource results are recorded separately under `fpga/`.

| Suite | Passing configurations | Result |
| --- | --- | --- |
| Unit | 9 | PASS: FIFO depths 2/4/512, status widths 3/16, three tick rates, core |
| Directed and throughput | 3 | PASS: directed at both baud rates; throughput at 4 Mbaud |
| Baud/phase matrix | 10 | PASS: two baud rates x five mismatch values, 32 offsets each |
| Randomized stress | 10 | PASS: seeds 1 through 10, each with 10,220 completed frames |
| Aggregate source-hash gate | 32 | PASS: current sources and scripts match recorded evidence |

The baud/phase matrix sends 92,160 frames in total. At each of its 320
baud/mismatch/offset combinations, all 256 byte values and 32 random frames are
checked. The stress suite completes another 102,200 frames across ten seeds.
The documented +/-2% transmitter mismatch target passes in simulation at both
baud rates; hardware tolerance remains unmeasured.

## Test-to-requirement mapping

| Requirements in the test plan | Implementation and evidence |
| --- | --- |
| RX-01 through RX-05 | `tb_uart`, directed suite: idle, all 256 values, variable gaps; throughput suite: 10,000 back-to-back frames |
| RX-06, RX-07 | Integrated false-start rejection, invalid stop rejection, counters, and next-frame recovery; exact core enable assertions |
| RX-08 through RX-10 | Integrated long break and recovery; `tb_core` checks 159/160 low enables, saturation, and high-level release |
| RX-11 | `tb_core`: glitches before/at/after ten decision points; integrated sub-clock idle glitches; expected sample-dependent corruption/rejection is checked |
| Phase and baud mismatch matrix | `tb_uart`, matrix suite: five mismatch values x 32 offsets x two baud rates; all 256 values plus 32 random frames per combination |
| FIFO-01 through FIFO-11 | `tb_fifo` at depths 2, 4, 512; scoreboard checks every cycle, all 12 boundary/operation bins, full/drop/drain, 21 fill/drain laps, and 30,000 random operations |
| CTRL-01 | `tb_core` resets at every enable position from start detection through invalid stop and wait-high, plus idle reset |
| CTRL-02, CTRL-03 | Integrated reset with queued bytes, active response, and low serial input; core unsettled-input arming check |
| CTRL-04 | Integrated clear during a frame with previously queued data; FIFO contents and reception preserved |
| CTRL-05 through CTRL-07, CTRL-09 | `tb_status` at widths 3 and 16: all event combinations with clear/reset, sticky flags, independent counter arithmetic, saturation; FIFO reset with simultaneous operations |
| CTRL-08 | Integrated clear during sustained break; active indication remains and counter does not retrigger |
| Throughput/service | Continuous drain, exact 600-frame stalled burst with 88 drops, and 400 frames during a nominal 1 ms service interruption |
| Random stress | Ten seeds, each with 10,220 completed frames plus breaks, false starts, resets, clears, and consumer stalls; drain and diagnostic scoreboards |
| Fractional timebase | `tb_tick` at 115200, 1 Mbaud, and 4 Mbaud; 100,000 cycles per configuration, exact enable sequence, interval bounds, average rate |

## Assertions and functional coverage

FIFO checks assert the reference queue order, occupancy, full/empty flags,
pre-edge read/write/drop acceptance, response timing, and no output for an empty
read. RTL simulation-only assertions check both pointer updates and wrapping,
count updates, and absence of simultaneous access to the same RAM address.

Core unit tests exercise every normal state transition, all eight bit sample
positions, invalid-start recovery, invalid-stop recovery, break entry/release,
and reset in each receive state. Ten glitch decision points (start, eight data
bits, stop) are crossed with before/at/after timing. Status tests exhaust all
eight event masks crossed with clear and reset and reach counter saturation.

Functional coverage comes from explicit test loops, scoreboard assertions, and
the `COVER` messages in per-test logs. It is not a statement of measured line,
branch, toggle, or FSM code-coverage percentages. No such percentage or coverage
database is claimed. The optional simulator code-coverage facilities have not
been used. Analog metastability, device timing, RAM inference, and physical I/O
behavior require the later implementation and hardware checks in the test plan.

## Evidence and reproduction

See [README.md](README.md) for batch commands. Each run retains compiler logs,
simulator logs, versions, generics, seeds, and SHA-256 source/script hashes under
`build/sim/`. The gate checker aggregates only matching, clean passing runs and
writes [results/gate.json](results/gate.json). A saved gate snapshot applies only
to its recorded hashes; run the checker again after modifying sources.

Only the latest complete verified simulation set is retained. Superseded baseline
and resolved failure artifacts are removed with `clean_results.ps1` after a
passing gate. Every suite directory referenced by the current gate is preserved.
