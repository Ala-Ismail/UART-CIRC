# RTL area and fan-in review

Reviewed and updated on 2026-11-07 for 75 MHz, a 512-byte FIFO, and baud rates up
to 4 Mbaud. The RTL review is now supplemented by Quartus results for
10M16SAE144C8G; see [implementation results](../fpga/results/IMPLEMENTATION.md).

| Block | Original structure | Updated structure |
| --- | --- | --- |
| Sampling timer | 28-bit phase; add, compare, then conditional subtract | Elaboration-time GCD reduction; 7-bit phase at 4 Mbaud, 14 bits at 115200 baud; compare old phase and select a constant before one adder |
| Receive timing | Eight-bit frame-enable count compared against a value calculated from bit index | Four-bit down-counter; zero decode at each sample; three-bit data-bit index |
| Receive data | Variable-index writes to eight storage bits | Fixed one-bit shift wiring with a shared sample enable |
| Break detection | Increment, less-than saturation test, and equality threshold test | Registered active flag stops counting; two four-bit threshold checks |
| FIFO occupancy | Integer-range count with separate increment/decrement expressions and magnitude tests | Explicit ten-bit count; one adder with +1/-1 operand; full from the MSB, shared empty test |
| Diagnostic counters | Separate all-ones saturation comparisons; status clear feeds incrementer inputs | Carry-out saturation detection; zero/one clear result selected separately; event-driven updates |

The data RAM and registered read path retain their synchronous coding style and
have no data-array reset. The 512-byte capacity, all external ports, read latency,
full/empty boundary policy, drop-new overflow behavior, diagnostic semantics,
and exact sample-enable sequence are preserved.

At 4 Mbaud, the phase ratio reduces to 64/75; at 115200 baud, it reduces to
384/15625. Scaling the zero-initialized phase by the GCD proves that the reduced
and original accumulators wrap on exactly the same system-clock edges. The
existing timebase test compares against the original unreduced reference.
The core tests check samples at enables 8, 24, 40, ..., 136, and 152, independently
of the new bit timer.

Small decodes and shared arithmetic replace the largest RTL comparison and
selection structures. Remaining width-dependent paths include the phase
threshold comparison (14 bits at default baud), the FIFO's ten-bit empty test,
and diagnostic increment carry chains (16 counter bits plus carry at default
width). Quartus has mapped these paths and reports passing timing at 75 MHz.
At 4 Mbaud it reports 42 four-input, 81 three-input, and 110 two-or-fewer-input
functions, plus eight register-only LEs. This does not imply every multi-level
logic cone depends on four or fewer signals.

No register replication or extra pipeline latency has been introduced. Register
width reductions are explicit in RTL, but the original synthesis may already
have removed constant bits or shared some arithmetic. Actual area savings must
therefore come from a later before/after Quartus comparison using the same full
device, constraints, and settings. The first successful synthesis result was
reported at 279 LEs/167 registers. Disabling unnecessary inferred RAM pass-through
logic, justified by the no-collision invariant, produced clean mapping at
247 LEs/140 registers. The fitted result is 241 LEs/132 registers, one M9K,
and 91.21 MHz worst reported Fmax. The first snapshot is preserved separately;
no further RTL optimization followed that report.

See [simulation verification](../sim/VERIFICATION.md) and the current
[source-hash gate](../sim/results/gate.json) for functional validation status.
