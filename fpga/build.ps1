param(
    [ValidateSet(115200,4000000)][int]$BaudRate = 4000000,
    [ValidateSet('Map','Fit','Timing','Assemble','Power','All')][string]$Stage = 'All',
    [string]$QuartusBin = 'C:\intelFPGA_lite\20.1\quartus\bin64'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$acceptedWarningIds=@(292013,16562,215044)
# Recheck the exact current sources before invoking implementation tools.
& (Join-Path $repoRoot 'sim/check_gate.ps1')
$gate = Get-Content -LiteralPath (Join-Path $repoRoot 'sim/results/gate.json') -Raw | ConvertFrom-Json
if ($gate.status -ne 'PASS') { throw 'Simulation gate has not passed.' }
$label = if ($BaudRate -eq 4000000) { '4m' } else { '115200' }
$buildRoot = Join-Path $repoRoot "build/quartus/$label"
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$manifestPath = Join-Path $buildRoot 'manifest.json'
$manifest = [ordered]@{
    timestamp=(Get-Date -Format o); device='10M16SAE144C8G'; baud=$BaudRate
    clock_hz=75000000; fifo_depth=512; optimization='AGGRESSIVE AREA'
    inferred_ram_passthrough='OFF: same-address simultaneous operations are unreachable'
    io='Auto placement, 3.3-V LVTTL, ideal same-clock external delays; provisional'
    simulation_files=$gate.files; map='NOT RUN'; fit='NOT RUN'; timing='NOT RUN'; assembly='NOT RUN'; power='NOT RUN'
    diagnostics=@{}; accepted_warning_ids=$acceptedWarningIds
}
function Save-Manifest { $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath }
function Assert-CurrentSources {
    foreach ($source in $gate.files.PSObject.Properties) {
        if ((Get-FileHash -LiteralPath (Join-Path $repoRoot $source.Name)).Hash -ne $source.Value) {
            throw "Source changed after simulation: $($source.Name)"
        }
    }
}
function Invoke-Quartus([string]$Tool, [string[]]$ToolArgs, [string]$LogName) {
    Assert-CurrentSources
    $exe = Join-Path $QuartusBin "$Tool.exe"
    $logPath = Join-Path $buildRoot "$LogName.log"
    Write-Host "RUN $exe $($ToolArgs -join ' ')"
    & $exe @ToolArgs 2>&1 | Tee-Object -FilePath $logPath | ForEach-Object { Write-Host $_ }
    $code=$LASTEXITCODE
    Assert-CurrentSources
    if ($code -ne 0) { throw "$Tool failed ($code); see $logPath" }
    $diagnostics=@([IO.File]::ReadAllLines($logPath) | Where-Object { $_ -match '^\s*(Warning|Critical Warning|Error)(\s+\(\d+\))?:' })
    $manifest.diagnostics[$LogName]=$diagnostics
    $unresolved=@($diagnostics | Where-Object {
        $_ -notmatch '^\s*(?:Warning|Critical Warning) \((\d+)\):' -or [int]$Matches[1] -notin $acceptedWarningIds
    })
    $script:LastStageStatus = if ($unresolved.Count) { 'SUCCESS_WITH_WARNINGS' } elseif ($diagnostics.Count) { 'PASS_WITH_ACCEPTED_ADVISORY' } else { 'PASS' }
    if ($unresolved.Count -and $Tool -notin @('quartus_fit','quartus_sta','quartus_pow')) {
        throw "$Tool reported unresolved warnings; inspect $logPath before continuing"
    }
    if ($unresolved.Count) { Write-Host "REVIEW REQUIRED: $($unresolved.Count) unresolved $Tool warnings. Continuing diagnostic analysis; build is not clean." }
}
$maySaveManifest = $Stage -in @('Map','All')
try {
    if ($Stage -in @('Map','All')) {
        Save-Manifest
        Invoke-Quartus 'quartus_sh' @('-t',(Join-Path $PSScriptRoot 'create_project.tcl'),$manifest.device,$buildRoot,"$BaudRate") 'project'
        $manifest.build_files = @{}
        foreach ($source in @('fpga/create_project.tcl','fpga/uart_rx_circular.sdc','fpga/provisional_pins.qsf','fpga/build.ps1',"build/quartus/$label/uart_rx_circular.qsf")) {
            $manifest.build_files[$source]=(Get-FileHash -LiteralPath (Join-Path $repoRoot $source)).Hash
        }
        Save-Manifest
    } else {
        if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'Run the Map stage first.' }
        $previous=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $sameSources = @($previous.simulation_files.PSObject.Properties).Count -eq @($gate.files.PSObject.Properties).Count
        foreach ($source in $gate.files.PSObject.Properties) {
            if ($previous.simulation_files.PSObject.Properties[$source.Name].Value -ne $source.Value) { $sameSources=$false }
        }
        if ($previous.map -ne 'PASS' -or -not $sameSources) {
            throw 'No passing mapping result matches the current simulation evidence.'
        }
        foreach ($property in $previous.PSObject.Properties) { $manifest[$property.Name]=$property.Value }
        $manifest.accepted_warning_ids=$acceptedWarningIds
        if ($manifest.diagnostics -isnot [System.Collections.IDictionary]) {
            $priorDiagnostics=@{}
            foreach ($property in $manifest.diagnostics.PSObject.Properties) { $priorDiagnostics[$property.Name]=$property.Value }
            $manifest.diagnostics=$priorDiagnostics
        }
        $maySaveManifest=$true
    }
    Push-Location $buildRoot
    try {
        if ($Stage -in @('Map','All')) {
            Invoke-Quartus 'quartus_map' @('uart_rx_circular','--read_settings_files=on','--write_settings_files=off') 'synthesis'
            $manifest.map='PASS'; Save-Manifest
            # Read a plain .NET string: Windows PowerShell Get-Content attaches
            # provider metadata that must not be recursively serialized to JSON.
            $summary=[IO.File]::ReadAllText((Join-Path $buildRoot 'output_files/uart_rx_circular.map.summary'))
            Write-Host "FIRST PASS RESOURCE SUMMARY ($label):"
            Write-Host $summary
            $snapshotRoot=Join-Path $PSScriptRoot 'results'
            New-Item -ItemType Directory -Path $snapshotRoot -Force | Out-Null
            $snapshot=Join-Path $snapshotRoot "first-map-$label.json"
            [ordered]@{build=$manifest;resource_summary=$summary} | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $snapshotRoot "latest-map-$label.json")
            if (-not (Test-Path -LiteralPath $snapshot)) {
                [ordered]@{build=$manifest;resource_summary=$summary} | ConvertTo-Json -Depth 10 |
                    Set-Content -LiteralPath $snapshot
            }
        }
        if ($Stage -in @('Fit','All')) {
            Invoke-Quartus 'quartus_fit' @('uart_rx_circular','--read_settings_files=on','--write_settings_files=off') 'fitter'
            $manifest.fit=$script:LastStageStatus; Save-Manifest
        }
        if ($Stage -in @('Timing','All')) {
            if ($manifest.fit -notin @('PASS','PASS_WITH_ACCEPTED_ADVISORY','SUCCESS_WITH_WARNINGS')) { throw 'A successful fitted build is required for timing analysis.' }
            Invoke-Quartus 'quartus_sta' @('uart_rx_circular') 'timing'
            $manifest.timing=$script:LastStageStatus; Save-Manifest
        }
        if ($Stage -in @('Assemble','Power','All')) {
            if ($manifest.fit -notin @('PASS','PASS_WITH_ACCEPTED_ADVISORY','SUCCESS_WITH_WARNINGS')) { throw 'A successful fitted build is required for power analysis.' }
            if ($manifest.assembly -ne 'PASS') {
                # Creates programming files on disk; never invokes quartus_pgm.
                Invoke-Quartus 'quartus_asm' @('uart_rx_circular') 'assembly'
                $manifest.assembly=$script:LastStageStatus; Save-Manifest
            }
        }
        if ($Stage -in @('Power','All')) {
            Invoke-Quartus 'quartus_pow' @('uart_rx_circular') 'power'
            $manifest.power=$script:LastStageStatus; Save-Manifest
        }
        if ($manifest.Contains('failure')) { $manifest.Remove('failure') }
        Save-Manifest
    } finally { Pop-Location }
} catch {
    if ($maySaveManifest) { $manifest.failure=$_.Exception.Message; Save-Manifest }
    throw
}
