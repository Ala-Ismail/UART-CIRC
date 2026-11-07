# ModelSim verification

Run from the repository root in PowerShell:

```powershell
.\sim\run.ps1 -Suite All
.\sim\check_gate.ps1
.\sim\clean_results.ps1
```

Use `-ModelSimBin` to override the detected installation directory. The runner
compiles all RTL and testbenches with `vcom -2008`, elaborates each configuration,
and runs ModelSim at 1 ps precision. Errors, warnings, failed assertions, missing
PASS markers, and timeouts fail the run. No Quartus synthesis command is invoked;
the Quartus version command is used only to record the installed version.

Suites can also be run separately:

```powershell
.\sim\run.ps1 -Suite Unit
.\sim\run.ps1 -Suite Directed
.\sim\run.ps1 -Suite Matrix -MatrixOffset -2
.\sim\run.ps1 -Suite Matrix -MatrixOffset -1
.\sim\run.ps1 -Suite Matrix -MatrixOffset 0
.\sim\run.ps1 -Suite Matrix -MatrixOffset 1
.\sim\run.ps1 -Suite Matrix -MatrixOffset 2
.\sim\run.ps1 -Suite Stress
.\sim\check_gate.ps1
```

Independent runs use separate libraries and timestamped directories and may run
concurrently. An omitted `-MatrixOffset` runs all five mismatch values. Use
`-Waves` to retain recursive waveforms for reproducing failures; the initial
failure transcript is preserved even without waveform logging.

The gate checker requires 32 passing configurations: nine unit tests, three
directed/throughput tests, ten baud/mismatch matrix tests, and ten random seeds.
It accepts evidence only when the complete source/script manifest matches the
current files, the logs are clean, and every expected test has a PASS marker.
It writes `sim/results/gate.json`; rerun the checker after source changes rather
than treating an old saved PASS as current evidence.

Local libraries, transcripts, per-test logs, and source-hash manifests are kept
under `build/sim/` and ignored by Git. The gate snapshot records their relative
paths. Functional coverage is checked with testbench assertions and `COVER`
messages; a licensed code-coverage database is not required by this suite.

Keep only the latest complete verified set. After the gate passes, run
`clean_results.ps1`; it refreshes the gate and removes older run directories,
preserving every directory referenced by the passing gate. Separately run suites
may span multiple directories. Cleanup refuses to proceed with an incomplete
gate or directory links and only removes validated children of `build/sim/`.
