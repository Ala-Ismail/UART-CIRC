# UART-CIRC User Manual

Version: 2026-11-07. Implementation language: VHDL-2008.

## 1. What the design does

UART-CIRC receives UART bytes and stores them in a circular FIFO until other
FPGA logic reads them. It supports continuous back-to-back 8N1 frames, receives
data LSB first, and preserves byte order. All internal logic and the consumer
interface use the same system clock.

| Item | Current configuration |
| --- | --- |
| FPGA | Altera MAX 10 **10M16SAE144C8G** |
| System clock | **75 MHz**, provided externally |
| UART format | **8N1**: one start bit, eight data bits, no parity, one stop bit |
| Quartus GUI project baud | **4,000,000 baud** |
| VHDL entity default baud | **115200 baud**; override explicitly for 4 Mbaud |
| FIFO capacity | **512 bytes**, all locations usable |
| FIFO pointers | Nine bits; wrap from 511 to zero |
| Occupancy counter | Ten bits; represents zero through 512 |
| Diagnostic counters | 16-bit saturating counters by default |
| UART electrical interface | Logic-level input; provisional 3.3-V LVTTL assignment |

The receiver does not provide UART transmission, parity modes, RTS/CTS flow
control, a processor-bus adapter, or runtime baud changes. A consumer using
another clock domain requires a separate CDC interface or asynchronous FIFO.

At 4 Mbaud, a serial bit takes 250 ns and an 8N1 byte takes 2.5 us. Payload
throughput is **400,000 bytes/s**, or 3.2 Mbit/s. The 512-byte FIFO provides
**1.28 ms** of nominal buffering from empty without reads. Service it well before
that capacity is exhausted, allowing for existing occupancy and service latency.

## 2. Files to use

| File or directory | Purpose |
| --- | --- |
| [README.md](README.md) | Current stage status and results |
| [UART-circular.md](UART-circular.md) | Architecture and exact interface contract |
| [UART-circular-test-plan.md](UART-circular-test-plan.md) | Verification requirements |
| `rtl/` | Synthesizable receiver, FIFO, status logic, and shared package |
| [sim/README.md](sim/README.md) | ModelSim commands and evidence handling |
| [fpga/uart_rx_circular.qpf](fpga/uart_rx_circular.qpf) | Portable Quartus GUI project, configured for 4 Mbaud |
| [fpga/uart_rx_circular.qsf](fpga/uart_rx_circular.qsf) | Device, source, parameter, I/O, and optimization settings |
| [fpga/uart_rx_circular.sdc](fpga/uart_rx_circular.sdc) | Clock, provisional I/O timing, and RX input exception |
| [fpga/provisional_pins.qsf](fpga/provisional_pins.qsf) | Initial automatic pin choices used by project-generation scripts |
| [fpga/results/IMPLEMENTATION.md](fpga/results/IMPLEMENTATION.md) | Fitted resources, timing, and diagnostic review |

Generated libraries, reports, databases, and programming files are under `build/`
and ignored by Git. The portable project files, constraints, scripts, and saved
result summaries remain source-controlled candidates. A fresh checkout requires
new local simulation runs; the saved result snapshot alone is not a passing gate.

## 3. Tools

The verified local toolchain is Quartus Prime Lite **20.1.1 Build 720** and
ModelSim Intel FPGA Starter Edition **2020.1** on Windows.

Default executable directories used by the scripts:

```text
C:\intelFPGA_lite\20.1\quartus\bin64
C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem
```

Use the `-QuartusBin` and `-ModelSimBin` script parameters if your installation
uses different paths. Set `QUARTUS_ROOTDIR` to your Quartus installation directory
for the simulation runner's tool-version check. Run the commands below from the
repository root in PowerShell.

## 4. Verify before building the FPGA

```powershell
.\sim\run.ps1 -Suite All
.\sim\check_gate.ps1
.\sim\clean_results.ps1
```

The runner uses `vcom -2008` and batch ModelSim simulation at 1 ps precision.
The gate requires **32 passing configurations**: nine unit tests, three
directed/throughput tests, ten baud/mismatch matrix configurations, and ten
random seeds. Tests include overflow, full/empty boundaries, pointer wrap,
malformed frames, reset, status handling, and phase sweeps with +/-2% transmitter
baud mismatch at both 115200 baud and 4 Mbaud.

Compilation, elaboration, and required simulation must have zero warnings/errors,
failed assertions, mismatches, or timeouts before synthesis or mapping proceeds.
The gate checks source hashes and actual local logs. RTL or testbench changes
require a fresh applicable regression. Keep only the latest complete verified
result set; cleanup preserves all suite directories referenced by that gate.

For a focused overflow check, run `sim/run.ps1 -Suite Directed`. Its integrated
600-frame stalled burst must retain the first 512 bytes and count 88 dropped
bytes. This focused run alone does not replace the full implementation gate.

## 5. Build or open the Quartus project

For the complete scripted 4 Mbaud build:

```powershell
.\fpga\build.ps1 -BaudRate 4000000 -Stage All
.\fpga\report_results.ps1
```

For the default-rate build:

```powershell
.\fpga\build.ps1 -BaudRate 115200 -Stage All
.\fpga\report_results.ps1
```

The build script rechecks the simulation gate, generates a project, and runs
mapping, fitting, TimeQuest analysis, assembly, and power analysis. Individual
stages are available as `Map`, `Fit`, `Timing`, `Assemble`, and `Power`. Generate
and map the project before running later stages. Assembly creates programming
files on disk; the script never invokes the FPGA programmer.

The separate build directories are:

```text
build/quartus/4m/
build/quartus/115200/
```

For GUI use, open **`fpga/uart_rx_circular.qpf`** in Quartus. Its QSF uses relative
source paths and selects 4 Mbaud. GUI-generated output files are directed to
`build/quartus/gui/output_files/`. The separate script-generated QPF/QSF files
also exist in each baud-specific build directory.

The SDC constrains the clock to **13.333 ns**, a slightly conservative rounding
of the exact 75 MHz period. External synchronous I/O delays are provisionally
zero. The asynchronous UART input path is excepted only up to the first
synchronizer register; the two-stage synchronizer remains internally timed.

## 6. Connect the receiver

The provisional input assignments are shown below. They are tool-selected pins,
not a confirmed board pinout.

| Input | Provisional package pin | Function |
| --- | --- | --- |
| `clk` | 28 | External 75 MHz system clock |
| `rst` | 131 | Active-high synchronous reset |
| `uart_rx_i` | 64 | UART serial input, idle high |
| `rd_req` | 8 | Consumer read request |
| `clear_status` | 61 | Clear sticky diagnostics and counters |

Use a UART source with compatible logic levels. An RS-232 interface requires
appropriate level conversion. Confirm the board's pin connections, I/O voltage
requirements, and actual input/output timing before hardware use. Integrating
this module inside another FPGA design does not require exposing every status
signal as a physical package pin.

## 7. Interface reference

| Signal | Direction | Meaning |
| --- | --- | --- |
| `clk`, `rst`, `uart_rx_i` | Input | Clock, synchronous reset, and asynchronous UART input |
| `rd_req` | Input | Request the oldest unread byte |
| `rd_ready` | Output | A read can be accepted at the next rising edge if it remains high |
| `rd_data[7:0]` | Output | Registered byte; use only when `rd_valid` is high |
| `rd_valid` | Output | Read response is valid this cycle |
| `empty`, `full` | Output | FIFO has zero or 512 unread bytes |
| `level[9:0]` | Output | Unread RAM occupancy; excludes an already issued response |
| `rx_busy` | Output | Receiver is checking a start bit, receiving data, or checking stop |
| `framing_error` | Output | Sticky invalid-stop indication |
| `overflow` | Output | Sticky full-FIFO drop indication |
| `break_active` | Output | Qualified continuous-low RX condition is active |
| `framing_error_count` | Output | Number of rejected frames, saturating at 65535 |
| `overflow_count` | Output | Number of valid arriving bytes dropped while full, saturating at 65535 |
| `break_count` | Output | Number of break entries, saturating at 65535 |
| `clear_status` | Input | Clear sticky flags and diagnostic counters at a rising edge |

### Reading bytes

A read is accepted at a rising edge when `rd_req = 1`, `rd_ready = 1`, and reset
is inactive. Immediately after that edge, `rd_data` contains the oldest byte and
`rd_valid` is asserted. A synchronous consumer captures this response at the
following rising edge. Consecutive accepted requests produce consecutive valid
responses, up to one byte per system clock.

The response has **no backpressure**. Capture every cycle with `rd_valid = 1`.
There is no underflow flag: a request while empty is ignored and produces no
valid response. Unread RAM occupancy may be zero while the final read response
is still valid. `rd_data` is unspecified when `rd_valid` is low and is not reset.

### Overflow and simultaneous operations

- When full, drop the newly received byte, preserve unread data, set `overflow`,
  and increment `overflow_count`.
- Full plus a simultaneous accepted read still drops the new byte. Occupancy
  becomes 511. Decisions use occupancy before the edge.
- Empty plus a simultaneous arrival accepts the byte and rejects the read.
  There is no fall-through path.
- At intermediate occupancy, read and write can both succeed and occupancy
  stays unchanged.

### Reset, errors, and recovery

Assert `rst` for at least one rising clock edge. Reset discards buffered data,
any partial frame, and pending read validity, and clears all diagnostics. Allow
at least one idle-high UART bit time after release before starting traffic.
If RX is low during reset release, start detection waits for an actual
synchronized high; a sustained low can still qualify as a break.

A false start produces no byte and no framing error. A low stop-bit sample
rejects the frame, records one framing error, and waits for high before arming
the next falling start edge. A sustained low produces one break event after
160 consecutive low sampling enables. It does not repeatedly enqueue zero
bytes or repeatedly increment the break counter. A subsequent high clears
`break_active` and allows recovery without reset.

`clear_status` clears flags/counters without draining the FIFO or interrupting
reception. A new event on the clear edge wins: its flag is set and its counter
becomes one. Clearing status during a break leaves `break_active` high and does
not create another break event.

## 8. VHDL integration example

Inside the parent architecture, declare signals such as:

```vhdl
signal rx_data       : std_logic_vector(7 downto 0);
signal rx_valid      : std_logic;
signal rx_level      : unsigned(9 downto 0);
signal rx_overflow   : std_logic;
signal payload      : std_logic_vector(7 downto 0);
signal payload_valid : std_logic;
```

Import `ieee.std_logic_1164.all` and `ieee.numeric_std.all`. Instantiate the
receiver in the concurrent part of the architecture. The following example
drains continuously and requires a consumer that can accept every response:

```vhdl
receiver : entity work.uart_rx_circular
  generic map (
    CLK_HZ => 75000000, BAUD_RATE => 4000000,
    OVERSAMPLE => 16, FIFO_DEPTH => 512, ERROR_COUNT_WIDTH => 16
  )
  port map (
    clk => clk, rst => rst, uart_rx_i => uart_rx_pad,
    rd_req => '1', clear_status => clear_rx_status,
    rd_ready => open, rd_data => rx_data, rd_valid => rx_valid,
    empty => open, full => open, level => rx_level,
    rx_busy => open, framing_error => open, overflow => rx_overflow,
    break_active => open, framing_error_count => open,
    overflow_count => open, break_count => open
  );

process(clk)
begin
  if rising_edge(clk) then
    payload_valid <= '0';
    if rst = '1' then
      payload <= (others => '0');
    elsif rx_valid = '1' then
      payload <= rx_data;
      payload_valid <= '1';
    end if;
  end if;
end process;
```

If the consumer pauses, replace constant `rd_req` with its request control and
allow for a response to a request already accepted. Compile `uart_rx_pkg.vhd`
first, then the leaf modules, followed by `uart_rx_circular.vhd`. The supplied
scripts already use this order. Keep internal register feedback on internal
signals for compatibility with the installed Quartus front end.

## 9. Current verified results

| Result | 4 Mbaud build |
| --- | --- |
| ModelSim gate | All 32 configurations pass; zero warnings/errors |
| Fitted logic | **241 / 15,840 LEs (1.52%)** |
| Dedicated registers | **132** |
| FIFO memory | **One M9K**, 4096 logical data bits |
| External pins for the standalone top | **79 / 101** |
| Worst reported Fmax | **91.21 MHz** |
| Worst setup / hold slack | **+2.369 ns / +0.102 ns** |
| Hardware validation | Not performed; no FPGA programmed |

The first successful synthesis result, recorded before the RAM implementation
setting changed, was **279 LEs and 167 registers**, with one pass-through warning.
The later clean mapping result is 247 LEs and 140 registers; fitted packing gives
the 241-LE/132-register result above. See
[FIRST_PASS.md](fpga/results/FIRST_PASS.md) for the unchanged reference and
[IMPLEMENTATION.md](fpga/results/IMPLEMENTATION.md) for complete results.

LogicLock license warning 292013 and power warnings 16562/215044 are explicitly
accepted/deferred for this provisional build and remain in the logs. Board I/O
advisory 169177 and the default-rate build's incomplete drive-strength warning
15714 remain documented. These do not constitute final board electrical or
thermal validation.

## 10. Troubleshooting

| Symptom | Check or action |
| --- | --- |
| No received bytes | Release reset, provide the 75 MHz clock, check RX idle high and the input connection |
| Incorrect data or framing errors | Match baud and 8N1 format; remember the entity defaults to 115200 while the GUI project selects 4 Mbaud |
| Missing bytes and overflow set | Drain more often, reduce interruptions, or review buffer sizing; preserve the drop-new contract |
| Reads while `empty` is high | Expect no response; use `rd_ready` and capture only valid responses |
| `level = 0` but `rd_valid = 1` | This is the final byte already transferred from RAM to the response register |
| Break remains active | Restore a valid high level on RX; clearing counters alone does not clear the active condition |
| Gate checker rejects an old PASS | Rerun the required simulations on current sources and keep the local logs referenced by the gate |
| Quartus cannot find the device | Check MAX 10 support and the exact 10M16SAE144C8G selection |
| Timing or I/O advisory after board changes | Replace provisional pins/delays/standards with actual board constraints and rebuild |

For architectural changes or additional UART formats, update the design document
and test plan together with the VHDL and repeat verification before implementation.
