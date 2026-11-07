$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$acceptedWarningIds=@(292013,16562,215044)
function Read-Report([string]$Path) { [IO.File]::ReadAllText($Path) }
function Number-Field([string]$Text, [string]$Name) {
    $match=[regex]::Match($Text, '(?m)^\s*' + [regex]::Escape($Name) + '\s*:\s*([\d,]+)')
    if (-not $match.Success) { throw "Missing resource field $Name" }
    return [int]$match.Groups[1].Value.Replace(',','')
}
$builds=@()
foreach ($label in @('4m','115200')) {
    $root=Join-Path $repoRoot "build/quartus/$label"
    $manifest=Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
    $fit=Read-Report (Join-Path $root 'output_files/uart_rx_circular.fit.summary')
    $fitReport=Read-Report (Join-Path $root 'output_files/uart_rx_circular.fit.rpt')
    $timing=Read-Report (Join-Path $root 'output_files/uart_rx_circular.sta.summary')
    $staReport=Read-Report (Join-Path $root 'output_files/uart_rx_circular.sta.rpt')
    $power=Read-Report (Join-Path $root 'output_files/uart_rx_circular.pow.summary')
    if ($fit -notmatch 'Fitter Status : Successful') { throw "$label fitting did not succeed" }
    $slacks=@([regex]::Matches($timing, '(?m)^Slack\s*:\s*(-?[\d.]+)') | ForEach-Object { [double]$_.Groups[1].Value })
    if ($slacks.Count -ne 9 -or @($slacks | Where-Object { $_ -lt 0 }).Count) { throw "$label timing checks failed or missing" }
    $corners=@()
    foreach ($match in [regex]::Matches($timing, "(?m)^Type\s*:\s*(.+)\r?\nSlack\s*:\s*(-?[\d.]+)\r?\nTNS\s*:\s*(-?[\d.]+)")) {
        $corners += [ordered]@{check=$match.Groups[1].Value.Trim();slack_ns=[double]$match.Groups[2].Value;tns_ns=[double]$match.Groups[3].Value}
    }
    $fmax=@([regex]::Matches($staReport,'(?m)^;\s*([\d.]+) MHz\s*;\s*[\d.]+ MHz\s*;\s*clk\s*;') | ForEach-Object { [double]$_.Groups[1].Value })
    $ramMatch=[regex]::Match($fitReport,'; M9Ks\s*;\s*(\d+) / (\d+)')
    if (-not $ramMatch.Success -or -not $fmax.Count) { throw "Missing $label RAM or Fmax result" }
    $diagnostics=@()
    foreach ($stage in @('synthesis','fitter','timing','assembly','power')) {
        foreach ($line in [IO.File]::ReadAllLines((Join-Path $root "$stage.log"))) {
            if ($line -match '^\s*(Warning|Critical Warning) \((\d+)\):') {
                $id=[int]$Matches[2]
                $diagnostics += [ordered]@{stage=$stage;id=$id;accepted_or_deferred=($id -in $acceptedWarningIds);message=$line}
            }
            if ($line -match '^\s*Error') { throw "$label $stage contains an error" }
        }
    }
    $builds += [ordered]@{
        baud=$manifest.baud;device=$manifest.device;clock_hz=75000000;sdc_period_ns=13.333
        logic_elements=(Number-Field $fit 'Total logic elements');available_les=15840
        registers=(Number-Field $fit 'Total registers');pins=(Number-Field $fit 'Total pins');available_pins=101
        memory_bits=(Number-Field $fit 'Total memory bits');available_memory_bits=562176
        m9k_blocks=[int]$ramMatch.Groups[1].Value;available_m9ks=[int]$ramMatch.Groups[2].Value
        multipliers=(Number-Field $fit 'Embedded Multiplier 9-bit elements');plls=(Number-Field $fit 'Total PLLs')
        worst_fmax_mhz=($fmax | Measure-Object -Minimum).Minimum
        timing_checks=$corners;timing_pass=$true;diagnostics=$diagnostics
        power_summary=$power;fit_summary=$fit;relative_build_directory="build/quartus/$label"
        source_and_build_manifest=$manifest
    }
}
[ordered]@{timestamp=(Get-Date -Format o);accepted_or_deferred_warning_ids=$acceptedWarningIds;builds=$builds} |
    ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'results/implementation.json')
Write-Host 'PASS: both fitted builds, nine nonnegative timing checks each, no tool errors; diagnostics retained with policy classifications.'
