# First successful Quartus synthesis pass

Captured before any subsequent implementation-setting changes. Device:
**10M16SAE144C8G**; Quartus Prime Lite 20.1.1 Build 720; clock 75 MHz; UART
4 Mbaud; FIFO 512 bytes; optimization mode Aggressive Area. I/O is provisional:
automatic placement, 3.3-V LVTTL, and ideal same-clock external delays.

| Resource | First successful synthesis result |
| --- | --- |
| Estimated logic elements | **279** |
| Combinational functions | 246 |
| Dedicated logic registers / total registers | **167** |
| Logical memory bits | **4,096** |
| I/O pins | **79** (5 input, 74 output) |
| Virtual pins | 0 |
| Embedded 9-bit multipliers | 0 |
| PLLs | 0 |
| UFM / ADC blocks | 0 / 0 |

Quartus marked Analysis & Synthesis **successful with zero errors and one
warning**. Warning 276020 says RAM pass-through logic was inserted to preserve
the RTL read-during-write behavior. The warning was reported to the user together
with these numbers before changing the RAM implementation setting. Under the
repository's zero-warning rule, fitting did not proceed from this result.

The FIFO was inferred as one logical 512-by-8 dual-port RAM. Physical memory-block
packing and final logic utilization require fitting; synthesis estimates may
change. This is a first successful synthesis snapshot, not a clean final build
or a timing pass. Its original raw summary, warning text, settings, and source
hashes are preserved in [first-map-4m.json](first-map-4m.json).

The RTL invariant excludes a simultaneous accepted read and write to the same
address: empty rejects reads, full rejects arrivals, and intermediate occupancy
has different pointers. Simulation checks this invariant. The next build may
therefore disable inferred RAM pass-through logic without changing legal FIFO
behavior. This report remains the unchanged first-pass reference.
