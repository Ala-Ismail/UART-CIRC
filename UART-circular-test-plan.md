# UART Circular Buffer Test Plan

## 1. Purpose and configuration

Verify the receiver and FIFO contract in [UART-circular.md](UART-circular.md).
This document defines verification requirements. Execution results and coverage
evidence are recorded separately in `sim/VERIFICATION.md` and
`sim/results/gate.json`.

| Setting | Primary test configuration |
| --- | --- |
| RTL and testbench language | VHDL-2008 (`.vhd`); compile with ModelSim `vcom -2008` |
| Target FPGA | Altera MAX 10, 10M16SAE144C8G; automatic provisional I/O |
| System clock | 75 MHz (period approximately 13.333333 ns) |
| UART rate | 4,000,000 baud |
| Frame format | 8N1, LSB first, idle high |
| Oversampling | 16 enables per bit, fractional accumulator |
| FIFO depth | 512 bytes, all locations usable |
| Pointers | 9 bits, wrapping from 511 to 0 |
| Occupancy | 10 bits, representing 0 through 512 |
| Read interface | Request/response without response backpressure |
| Overflow policy | Drop the new byte and preserve unread data |

Also run reception tests at the documented default of 115200 baud, and FIFO
parameter tests at depths 2 and 4. The primary configuration must pass the entire
applicable suite. At 4 Mbaud, each bit lasts 250 ns and each frame lasts 2.5 us;
the payload rate is 400,000 bytes/s. A 512-byte FIFO provides nominally 1.28 ms
of buffering from empty.

## 2. Testbench and checking strategy

Use an independent serial transmitter model, a consumer driver, a reference
queue, protocol monitors, and assertions. Keep transmitter timing independent of
the DUT's sampling enables and counters. Include the actual input synchronizer
in integrated tests.

Use simulator time precision of 1 ps or better. Generate the 75 MHz clock with
fractional-time scheduling or a rational-period pattern so rounding does not
introduce significant frequency error during long tests. Record actual simulated
clock and transmitter rates in the test log.

For FIFO unit tests, inject byte-valid pulses directly. This allows exact
alignment of arrivals, reads, and full/empty boundaries. For integrated tests,
send UART frames through `uart_rx_i` and verify their decoded contents and FIFO
results. Observe internal acceptance signals when needed for cycle-level checks,
but derive expected byte values independently from transmitted data.

At each rising edge, apply the design's pre-edge occupancy rules:

1. Reset clears the reference queue, pending responses, and status model.
2. Accept a read only when pre-edge occupancy is nonzero.
3. Accept a valid arriving byte only when pre-edge occupancy is below depth.
4. If full before the edge, drop the arrival even when a read succeeds on that edge.
5. If empty before the edge, reject a read even when an arrival succeeds.
6. Compare the read response with the oldest accepted byte and update occupancy.

Check registered outputs with a race-free VHDL monitor that samples after
sequential and combinational delta-cycle updates have settled. A read accepted
at edge N produces
`rd_valid` and data after edge N, available for consumer capture at edge N+1.
Compare every response, not only the final queue contents. Account for the
registered UART-to-FIFO handoff when scheduling integrated boundary checks.

Every test must have a timeout, deterministic seed logging, and a final check
for unexpected responses, pending transactions, and diagnostic events.

## 3. Directed UART tests

| ID | Stimulus | Required result |
| --- | --- | --- |
| RX-01 | Hold RX high without frames | No data, framing error, overflow, or break |
| RX-02 | Send `00`, `FF`, `55`, `AA`, walking ones, and walking zeros | Correct values and bit order; one byte per frame |
| RX-03 | Send every byte value from 0 to 255 | Exact ordered output with no duplicates or missing bytes |
| RX-04 | Send at least 10,000 back-to-back frames while draining | No loss or errors; no extra idle bit required |
| RX-05 | Insert variable idle gaps, including long gaps | Correct reception of the first and following frames |
| RX-06 | Drive low, return high before the start-validation sample, then send a valid frame | False start produces no byte or framing error; next frame succeeds |
| RX-07 | Hold the stop bit low at its validation sample | Reject that frame, count one framing error, recover after high |
| RX-08 | Hold RX low for many frame times | No queued zero bytes; one break entry and no repeated break events |
| RX-09 | End a break, then send valid traffic with a clean falling start edge | Break clears and reception resumes without reset |
| RX-10 | Apply low pulses just below and above the 160-low-enable break threshold | Break qualification follows sampled-low count; no premature event |
| RX-11 | Inject narrow glitches during idle, start, data, and stop | Record sample-dependent effects; no unexplained status or repeated events |

For RX-08, a low stop sample may produce one framing error before the break
event. A long continuous low must not repeatedly increment either counter.
RX-11 characterizes noise sensitivity: this single-sample design does not promise
rejection of a glitch that overlaps a decision sample.

## 4. Sampling phase and baud mismatch

At both 115200 baud and 4 Mbaud:

- Sweep start-edge offset across a system-clock period using at least 32 offsets.
- Vary idle duration to cover different fractional-accumulator phases; collect
  coverage of start detection relative to the next sampling enable.
- Test transmitter baud offsets of -2%, -1%, 0%, +1%, and +2% relative to nominal.
- At each combination, send all byte values and a back-to-back randomized burst.
- Include the synchronizer and the earliest/latest sample-enable alignments.

The acceptance target is zero incorrect or missing bytes for this matrix while
the consumer prevents overflow. The +/-2% target is a requirement to verify,
not a measured capability. If it fails, record the failing phase and waveform,
then resolve the receive timing or explicitly revise the design requirement.
Larger mismatch values may be swept to characterize the limit, without requiring
success outside the stated target.

## 5. FIFO tests

| ID | Stimulus | Required result |
| --- | --- | --- |
| FIFO-01 | Reset, then request reads while empty | `empty=1`, `level=0`, `rd_ready=0`; no response or pointer movement |
| FIFO-02 | Write one byte, then read it | Correct data and response timing; occupancy returns to zero |
| FIFO-03 | Write exactly 512 bytes without reads | `level=512`, `full=1`; no overflow for these accepted bytes |
| FIFO-04 | Attempt additional writes while full | Each arrival is dropped; sticky overflow and drop count update |
| FIFO-05 | Drain after overflow | All 512 original bytes emerge in order; dropped bytes never appear |
| FIFO-06 | Simultaneous arrival and request while empty | Arrival succeeds, read is rejected; final level is one |
| FIFO-07 | Simultaneous arrival and request with intermediate occupancy, including one byte | Both succeed; oldest byte is returned; level is unchanged |
| FIFO-08 | Simultaneous arrival and request while full | Read succeeds, arrival is dropped, overflow is recorded; level becomes 511 |
| FIFO-09 | Hold read request high through a drain | Consecutive responses while requests are accepted; no extra response after empty |
| FIFO-10 | Alternate bursts of writes and reads through at least 20 pointer wraps | No reordering, duplication, or incorrect flags at wrap boundaries |
| FIFO-11 | Use depths 2 and 4 | Same boundary behavior; all configured locations usable |

There is no underflow flag in the current interface. An empty read is an ignored
request; tests must not expect an underflow diagnostic.

## 6. Reset and diagnostic tests

| ID | Stimulus | Required result |
| --- | --- | --- |
| CTRL-01 | Assert synchronous reset during idle, start, each data position, and stop | Partial frame is discarded; receiver and FIFO return to reset state |
| CTRL-02 | Reset with unread bytes and with an active read response | Queue discarded; `rd_valid` cleared; no stale response after reset |
| CTRL-03 | Release reset while physical RX is low | Reset-initialized synchronizer highs do not arm a false start; break can qualify |
| CTRL-04 | Clear status with queued data and during reception | Queue and active frame preserved; flags and counters clear |
| CTRL-05 | Clear status on the same edge as each diagnostic event | Event wins; affected counter is one and affected sticky flag is set |
| CTRL-06 | Generate repeated framing errors, dropped bytes, and distinct breaks | Each corresponding counter increments exactly once per event |
| CTRL-07 | Drive each counter to its maximum, then cause more events | Counter saturates instead of wrapping |
| CTRL-08 | Clear status during a sustained break | Break counter clears; `break_active` stays high; no new event until a new break |
| CTRL-09 | Assert reset with reads, arrivals, and diagnostic events | Reset takes priority; no response, enqueue, or retained event |

Use a smaller legal `ERROR_COUNT_WIDTH` in an additional configuration to make
counter saturation practical to test. Separately check default-width sizing.

## 7. Throughput and randomized stress

Run continuous 4 Mbaud reception with these consumer patterns:

- Continuous reads: no overflow, ordered data, and low occupancy.
- Burst draining after nominal 1 ms interruptions from an empty queue: expected
  arrivals fit in 512 bytes; confirm the actual phase-dependent maximum occupancy.
- No reads until at least 600 valid frames have completed and their FIFO handoffs
  have settled: retain the first 512, drop the rest, and check exact drop count.
- Random read bursts and pauses, including pauses beyond nominal 1.28 ms capacity:
  allow only the drops predicted by pre-edge full occupancy.

Run at least 10 recorded random seeds with at least 10,000 frames per seed at
4 Mbaud. Include valid frames, malformed stops, false starts, breaks, resets, and
status clears. Drain at the end of each run and check all remaining expected data.
Use unique byte sequences or a deterministic pseudorandom sequence to expose
ordering errors that repeated identical bytes could conceal.

## 8. Assertions and coverage

Assert occupancy bounds, exact count updates, pointer movement only on accepted
operations, modulo-depth wrap, correct full/empty flags, and one response per
accepted read. Assert that invalid frames cannot enqueue data and overflow cannot
overwrite unread data. Check these properties with reset conditions explicitly
handled and with no uninitialized control values after reset.

Collect coverage for every receiver state and transition, each data bit position,
pointer wrap, occupancy at 0, 1, 511, and 512, and all read/arrival combinations
at empty, intermediate, and full occupancy. Cross baud mismatch with start phase,
and cover diagnostic-event/status-clear collisions and reset during every state.
For smaller-depth runs, substitute the corresponding depth boundary values.

## 9. Synthesis and hardware validation

These checks follow the clean-code and simulation gate. The selected target is
10M16SAE144C8G and Quartus device support has been checked. Initial fitting uses
automatic I/O placement and provisional electrical timing constraints. Report
those assumptions with results and replace them with actual board requirements
before final timing sign-off or hardware use.

1. Synthesize for the selected FPGA and inspect the 512-by-8 RAM inference and
   registered read latency. Check that FIFO behavior matches RTL simulation.
2. Constrain the system clock to 75 MHz and verify implemented timing, including
   the fractional accumulator and FIFO control paths.
3. Review synchronizer placement, CDC reporting, and input constraints. Do not
   suppress synchronous internal timing paths as part of the asynchronous input
   exception. Simulation does not model analog metastability reliability.
4. Use a serial source and physical interface rated for 4 Mbaud. Send known and
   pseudorandom sequences; compare drained bytes with the source sequence.
5. Exercise back-to-back traffic and intentional consumer stalls. Capture FIFO
   occupancy and overflow, verifying the boundary policy against known traffic.
6. Inject malformed frames and breaks where supported by the test source, then
   verify reception recovers without resetting the FPGA.

## 10. Exit criteria and evidence

Verification is complete when all required directed tests pass, the stated phase
and mismatch matrix passes, all random seeds pass their scoreboards, assertions
report no failures, and required coverage has been hit or an exclusion justified.
Hardware release additionally requires satisfactory implementation timing, CDC
review, memory inference review, and the board checks above.

Save simulator/tool versions, parameter values, random seeds, test summaries,
coverage reports, and timing/resource reports. Retain failure waveforms and exact
reproduction commands. Track each test as planned, passed, failed, or blocked;
documentation alone must not be recorded as a passing test.
