# FPGA UART Receiver with Circular Buffer

## 1. Purpose and scope

Implement a UART receiver that captures serial bytes independently of the logic
consuming them. A circular buffer stores completed bytes in arrival order and
allows the consumer to read them later using the FPGA system clock.

This document defines the proposed RTL contract. Implement the RTL and
self-checking testbenches in VHDL-2008 using `.vhd` files, with ModelSim
`vcom -2008` compilation and Quartus configured for VHDL-2008. The target FPGA
is Altera MAX 10 10M16SAE144C8G. Quartus may assign arbitrary provisional I/O
locations for the initial build, as authorized by the user.
The RTL remains portable; no development board or processor bus is assumed.

Initial implementation assumptions:

- One system clock; UART sampling uses clock-enable pulses, not a derived clock.
- UART format: one start bit, eight data bits, no parity, one stop bit (8N1).
- Idle and stop levels are high; start level is low; data is received LSB first.
- Target system clock is 75 MHz, default baud rate is 115200, and buffer depth is
  512 bytes. The maximum intended operating baud rate is 4,000,000 baud (4 Mbaud).
- The serial input is already at a voltage compatible with the FPGA input pin.
  Any required physical-layer transceiver is outside this block.
- The consumer uses the same system clock. A consumer in another clock domain
  requires an asynchronous FIFO or a separate clock-domain crossing interface.
- A byte arriving when the buffer is full is dropped; unread bytes are preserved.
- Baud rate and buffer depth are elaboration-time parameters in the first version.

## 2. Block architecture

```text
uart_rx_i -> input synchronizer -> UART receive state machine -> byte + valid
                                        ^                         |
                                        |                         v
clk -> fractional sampling enable ------+                  circular FIFO
                                                               |
                                                    read request / response

                     framing, break, and overflow -> status registers
```

Suggested RTL modules:

| Module | Responsibility |
| --- | --- |
| `uart_rx_sync` | Synchronize the asynchronous serial input |
| `uart_rx_tick` | Generate the 16× baud sampling enable |
| `uart_rx_core` | Qualify start bits, sample data, validate stop bits |
| `uart_rx_fifo` | Store bytes, track occupancy, service read requests |
| `uart_rx_status` | Sticky diagnostic flags and saturating event counters |
| `uart_rx_circular` | Connect the modules and expose status |

The implementation uses these modules in `rtl/`, plus `uart_rx_pkg.vhd` for
width calculations and counter helpers. The external `level` and diagnostic
counters use `unsigned` ports; serial data uses `std_logic_vector`.

The synchronizer may be implemented inside the receiver rather than as a separate
module. All sequential logic runs on the rising edge of `clk`.

## 3. Parameters and external interface

| Parameter | Default | Meaning |
| --- | --- | --- |
| `CLK_HZ` | 75,000,000 | System clock frequency in hertz |
| `BAUD_RATE` | 115,200 | UART line rate in bits per second |
| `OVERSAMPLE` | 16 | Fixed at 16 for the first implementation |
| `FIFO_DEPTH` | 512 | Power of two, at least 2 |
| `ERROR_COUNT_WIDTH` | 16 | Width of saturating diagnostic counters |

Require positive frequencies and `CLK_HZ > BAUD_RATE * OVERSAMPLE`. Use an
elaboration-time check for unsupported parameters. No runtime divider is needed.

| Signal | Direction | Definition |
| --- | --- | --- |
| `clk` | Input | System clock |
| `rst` | Input | Active-high synchronous reset |
| `uart_rx_i` | Input | Asynchronous UART serial input |
| `rd_req` | Input | Request to remove the oldest byte |
| `rd_ready` | Output | High when a read request can be accepted |
| `rd_data[7:0]` | Output | Registered data for an accepted read |
| `rd_valid` | Output | Read response valid during this cycle |
| `empty`, `full` | Output | FIFO occupancy flags |
| `level` | Output | Number of unread bytes, from 0 through `FIFO_DEPTH` |
| `rx_busy` | Output | Receiver is validating or receiving a frame |
| `framing_error` | Output | Sticky indication of an invalid stop bit |
| `overflow` | Output | Sticky indication that a valid byte was dropped |
| `break_active` | Output | Qualified continuous-low condition is active |
| `framing_error_count` | Output | Saturating count of rejected frames |
| `overflow_count` | Output | Saturating count of valid bytes dropped at full |
| `break_count` | Output | Saturating count of break entries |
| `clear_status` | Input | Clear sticky flags and diagnostic counters |

`level` needs `ceil(log2(FIFO_DEPTH + 1))` bits. Pointer width is
`log2(FIFO_DEPTH)` bits. `rx_busy` is low in the idle and break-wait states.
At the default depth of 512, the read and write pointers are each 9 bits and
wrap from 511 to 0. The occupancy counter is 10 bits, representing 0 through 512.
The data memory holds 512 bytes (4096 bits), excluding pointers and status logic.

## 4. Input synchronization and sampling timebase

Pass `uart_rx_i` through at least two flip-flops before using it. Apply the FPGA
vendor's synchronizer attributes and CDC constraints when targeting a device.
Receiver logic must never use the unsynchronized input. Reset both stages high.

Generate sampling enables with an integer phase accumulator. Define
`TICK_HZ = BAUD_RATE * 16`. On every system clock:

```text
sum = phase + TICK_HZ
if sum >= CLK_HZ:
    phase_next = sum - CLK_HZ
    sample_tick = 1
else:
    phase_next = sum
    sample_tick = 0
```

Size the intermediate sum to hold `CLK_HZ - 1 + TICK_HZ` without overflow.
Reset phase to zero. The average enable rate is `TICK_HZ`; intervals differ by at
most one system clock. At the defaults, the average interval is approximately
40.690 system clocks. The accumulator continues running between frames.

The RTL implements an equivalent reduced ratio to limit area and combinational
width. At elaboration, compute `SCALE = gcd(CLK_HZ, TICK_HZ)`,
`MODULUS = CLK_HZ / SCALE`, and `STEP = TICK_HZ / SCALE`. Store only
`ceil(log2(MODULUS))` phase bits. An enable occurs when
`phase >= MODULUS - STEP`; the next phase adds either `STEP` or
`STEP - MODULUS` using one fixed-width adder with a selected constant operand.
GCD computation and division are elaboration-time operations, not hardware.
Starting from zero, this gives exactly the same enable sequence as the reference
algorithm above. At 4 Mbaud the ratio is 64/75 and phase storage is 7 bits;
at 115200 baud it is 384/15625 and phase storage is 14 bits. The original
unreduced implementation used a 28-bit phase register at this system clock.

Detect a synchronized falling edge on any system clock in `IDLE`. Start the
receive timing counter at zero on that edge; count subsequent sampling enables.
The first enable can occur less than one oversample interval after detection.
This quantization, synchronizer latency, and transmitter clock mismatch must be
included in simulation. The first version uses one center sample per bit.

### Operation at 4 Mbaud

At a 75 MHz system clock, a 4 Mbaud bit lasts 250 ns, or 18.75 system clocks.
The 16× sampling enable averages 64 MHz, below the system clock, so this operating
point satisfies the timebase constraint. Enable intervals are one or two system
clocks; their average is 1.171875 clocks. These are enables within the 75 MHz
domain, not a separate 64 MHz clock.

Use the fractional accumulator rather than rounding the bit period to a fixed
integer clock count. One system clock is approximately 13.33 ns, or 5.33% of a
4 Mbaud bit. Synchronizer delay and start-detection quantization therefore consume
a meaningful part of the sampling margin. Validate the complete receive path at
4 Mbaud with phase sweeps and baud mismatch before declaring this rate supported
on hardware. Keep the receive counters and FIFO paths within the 13.33 ns system
clock period after synthesis and routing.

For 8N1, 4 Mbaud carries at most 400,000 payload bytes per second, equivalent to
3.2 Mbit/s of payload. A requirement for 4 Mbit/s of payload would instead need
5 Mbaud on the UART line. That would require revising the 16× sampling scheme
because its 80 MHz enable rate exceeds the 75 MHz clock.

## 5. Receive state machine

Use sampling-enable counts relative to the detected start edge:

| State | Action and transition |
| --- | --- |
| `IDLE` | Wait for a synchronized high-to-low transition; enter `START` |
| `START` | At enable 8, require low; otherwise abandon the false start |
| `DATA` | Sample bit 0 at enable 24, then bits 1–7 every 16 enables |
| `STOP` | Sample the stop bit at enable 152; emit a byte if high |
| `WAIT_HIGH` | After a low stop sample, discard the frame and wait for high |

The numbered enables refer to the first, second, and subsequent enables after
edge detection; they are not raw counter values. This convention must be kept
consistent in RTL to avoid off-by-one sampling errors.

The RTL uses a 4-bit down-counter: load seven on start detection, then wrap from
zero to fifteen on each bit sample. This gives the specified eight-enable start
delay and sixteen-enable intervals without a frame-length counter or a dynamic
comparison against `23 + 16 * bit_index`.

In `DATA`, shift each sample into bit 7 while moving the other bits toward bit 0.
After eight LSB-first samples, the byte is in its normal bit order. Fixed shift
wiring avoids dynamically indexed writes to the data register. After sampling
bit 7 at enable 136, advance to `STOP`. A high stop sample produces exactly one
system-clock `byte_valid` pulse with a stable `byte_data` value. Return to `IDLE`
immediately after that sample so the following start edge can be detected in
back-to-back frames. No extra idle bit is required.

A low stop sample produces one `framing_error_event`, no FIFO write, and a
transition to `WAIT_HIGH`. Return to `IDLE` when the synchronized input is high.
The receiver then waits for the next falling edge. A short false start produces
neither a byte nor a framing error.

Document the synchronous producer contract in RTL: the FIFO accepts the
registered byte and pulse at the following rising clock edge. It must never
accept an incomplete shift register value.

### Break handling

Independently count consecutive low sampling enables, clearing the count when
the synchronized input is high. After 160 consecutive low enables (approximately
one 8N1 frame), assert `break_active` and issue one `break_event`. Saturate the
low-duration counter; do not repeatedly generate events while the line stays low.
Clear `break_active` when the synchronized line returns high.

A continuous-low input can cause one framing error followed by one break event.
It must not fill the FIFO with zero bytes. If reset is released while RX is low,
wait for a high level before arming start-edge detection; the break detector still
runs. A sampled high level ends this version's break condition; additional noise
filtering can be introduced later if required.

## 6. Circular buffer

Use an 8-bit-wide synchronous memory, a write pointer `wr_ptr`, a read pointer
`rd_ptr`, and an occupancy counter `count`. All `FIFO_DEPTH` locations are usable.
Pointer equality alone does not distinguish empty from full; `count` does.
The RTL declares the occupancy width explicitly and uses one adder for increment
or decrement, selecting the two's-complement constant +1 or -1 before the adder.
For the required power-of-two depth and valid occupancy range, the occupancy MSB
alone indicates full. The empty zero test is shared by read acceptance logic.

```text
empty    = (count == 0)
full     = (count == FIFO_DEPTH)
rd_ready = !empty && !rst
pop      = rd_req && rd_ready
push     = byte_valid && !full && !rst
drop     = byte_valid && full && !rst
```

Acceptance decisions use occupancy immediately before the rising edge. On that
edge, write accepted bytes at `wr_ptr`, read accepted requests at `rd_ptr`, and
advance only the corresponding accepted operation's pointer. Pointer arithmetic
wraps modulo `FIFO_DEPTH`.

| Accepted push | Accepted pop | Next count |
| --- | --- | --- |
| No | No | `count` |
| Yes | No | `count + 1` |
| No | Yes | `count - 1` |
| Yes | Yes | `count` |

Boundary behavior is deliberately explicit:

- Empty plus a new byte and a read request: accept the byte, reject the read.
  The consumer can request it on a later edge; there is no fall-through bypass.
- Full plus a new byte and an accepted read: drop the arriving byte, accept the
  read, and leave `FIFO_DEPTH - 1` bytes. Set overflow and increment its counter.
- With occupancy between empty and full, a read and write can both succeed.
  Their addresses are different, including when occupancy is one.

The conservative full rule avoids relying on device-specific behavior when a
memory location is read and written simultaneously. A future version may allow
replacement at full if its RAM collision behavior is explicitly implemented.

### Read request and response timing

This interface has no response backpressure. The consumer must capture every
cycle with `rd_valid = 1`. A request accepted at rising edge N updates `rd_data`
and asserts `rd_valid` immediately after that edge; the consumer can capture the
response at edge N+1. Without an accepted request at an edge, clear `rd_valid`.
Ignore `rd_data` when `rd_valid` is low.

Consecutive requests can produce consecutive valid responses, one byte per
clock. Occupancy decrements when the request is accepted, so it excludes bytes
already transferred into the read response register. If the consumer needs a
ready/valid output with stalls, add response storage and account for it explicitly.

Use a simple dual-port synchronous RAM coding style: one write port and one
registered read port. Do not reset the memory array. Confirm inferred memory and
read latency in the chosen synthesis tool; small configurations may use registers
or distributed RAM instead of block RAM.

## 7. Reset and diagnostic behavior

Reset has priority over reads, writes, and status events. It clears both pointers,
occupancy, receive state, timing counters, `rd_valid`, sticky flags, and diagnostic
counters. It sets the synchronized input history high and disarms start detection.
After reset, wait for the synchronizer pipeline to fill with real input samples
before allowing a synchronized high to arm detection. Reset-initialized high
values must not arm detection when the physical input is low. Memory contents
are irrelevant while empty.

Reset discards buffered bytes and any partially received frame. Hold reset for
at least one rising edge. If the board supplies an asynchronous reset, synchronize
its deassertion before driving this block.

`clear_status` does not reset the FIFO or interrupt reception. On an edge with
both a clear and an error event, the new event wins: the affected sticky flag is
set and its counter becomes one. Otherwise counters increment on their event and
saturate at their maximum value. Clearing status during an existing break clears
the break counter but leaves `break_active` asserted; no new break event occurs
until the line goes high and another break is detected.

The status implementation uses the incrementer's carry-out to detect saturation,
avoiding a separate full-width all-ones comparator. Status clear selects zero or
one directly according to the event, rather than placing a clear mux before the
incrementer. Break counting stops using the registered active flag; its threshold
uses two four-bit equality checks rather than a separate less-than comparator.

## 8. Capacity and service requirements

Assume a continuous 4,000,000 baud UART stream using 8N1. Each payload byte uses
ten serial bits: one start bit, eight data bits, and one stop bit. This gives:

- Serial bit time: 250 ns.
- Received byte interval: 2.5 microseconds.
- Incoming payload rate: 400,000 bytes/s, equivalent to 3.2 Mbit/s.

Each FIFO location stores one byte. The nominal buffering time for an initially
empty FIFO without reads is:

```text
buffer_time_seconds = FIFO_DEPTH * 10 / BAUD_RATE
                    = FIFO_DEPTH / 400000
```

| FIFO depth | Data storage | Nominal buffering time at 4 Mbaud |
| --- | --- | --- |
| 256 locations | 256 bytes | 640 microseconds |
| 512 locations (default) | 512 bytes | 1.28 ms |
| 1024 locations | 1024 bytes | 2.56 ms |
| 2048 locations | 2048 bytes | 5.12 ms |

For the default depth, service the FIFO comfortably before 1.28 ms of
uninterrupted arrivals accumulate. This is a capacity estimate, not a guaranteed
safe polling interval: account for current occupancy, a frame already in progress,
baud mismatch, scheduling latency, and the time required to drain the FIFO. With
`level` bytes already stored, the remaining nominal capacity is
`(FIFO_DEPTH - level) * 2.5 microseconds`.

At 75 MHz, one byte arrives every 187.5 system clocks on average. The read
interface can accept one read per clock while nonempty, so the consumer can drain
bursts faster than they arrive if it services the FIFO often enough. Its sustained
read capacity should exceed 400,000 bytes/s to provide catch-up margin after
interruptions. A finite FIFO cannot compensate for an indefinitely slower consumer.

When the FIFO is full, a newly completed byte is dropped and the sticky overflow
flag is set. Under the boundary rule in section 6, this also applies if a read is
accepted on that same edge. Leave service margin before full occupancy.

If loss is unacceptable, size the buffer for the maximum service interruption
or add hardware flow control. RTS signaling and programmable watermarks are
outside the first version.

## 9. Verification plan

The detailed test cases, acceptance criteria, and required evidence are defined
in [UART-circular-test-plan.md](UART-circular-test-plan.md).

Build a self-checking testbench with an independent serial transmitter model and
a reference queue. Compare every accepted read response with the queue head.
Model the boundary acceptance rules from section 6, including overflow at full
with a simultaneous pop.

Required scenarios:

1. Reset during idle, during reception, with queued bytes, and with a pending
   read response. Confirm no stale data becomes valid after reset.
2. Receive `00`, `FF`, `55`, `AA`, walking-one patterns, and randomized bytes.
   Check bit order and exactly one enqueue per valid frame.
3. Receive continuous back-to-back frames while reading at different rates.
4. Sweep start-edge phase across the system clock and sampling-enable interval.
   Exercise fractional timing at 75 MHz with both 115200 baud and 4 Mbaud, plus
   additional supported clock rates. Include the actual synchronizer pipeline.
5. Verify a chosen target of at least ±2% transmitter baud mismatch relative to
   nominal receiver baud at both 115200 baud and 4 Mbaud, including long bursts
   and phase sweeps. This is an
   acceptance target to demonstrate, not an assumed measured tolerance.
6. Inject false starts, low stop bits, and continuous-low break conditions.
   Verify rejection, event counts, recovery, and reset release while RX is low.
7. Fill and drain the FIFO exactly; wrap both pointers many times. Include depths
   2, 4, and 512, empty/full reads, simultaneous operations, and overflow recovery.
8. Verify read response timing and consecutive accepted requests.
9. Exercise status clearing on the same edge as each event and counter saturation.
10. Inject narrow glitches at different phases and document behavior. Single-point
    sampling does not promise rejection of glitches coincident with a sample.

Useful assertions:

- `0 <= count <= FIFO_DEPTH` at every clock.
- Pointer changes correspond exactly to accepted pushes or pops, except reset.
- Occupancy changes match the accepted-operation table.
- Each accepted pop produces exactly one response in the defined response cycle.
- Invalid frames never generate a byte pulse.
- Full arrivals preserve all previously unread bytes.
- Break entry generates at most one event until the line returns high.

Before hardware release, inspect synthesis memory inference, run timing analysis,
review the input CDC path, and test real serial traffic at the selected clock and
baud rate. Static timing and CDC checks complement simulation; simulation cannot
prove metastability containment.

## 10. Implementation sequence and completion criteria

1. Implement the synchronizer, fractional timebase, and UART receive state machine.
2. Implement the FIFO and its synchronous read request/response interface.
3. Integrate status registers, reset behavior, and parameter checks.
4. Run the self-checking verification scenarios and assertions.
5. Add device-specific clock, pin, and CDC constraints; synthesize and inspect
   resource use and timing before board testing.

The first version is complete when the selected target meets timing, the stated
verification scenarios pass, valid traffic preserves byte order, overflow is
observable, and malformed traffic recovers without requiring reset. The selected
device is 10M16SAE144C8G; installed Quartus device support has been checked.
Initial implementation uses automatically assigned pins, provisional 3.3-V LVTTL,
and zero external I/O delays relative to the system clock. Final board pinout,
electrical timing, clock source, and any processor-bus adapter remain integration
decisions and must be reviewed before board sign-off.
