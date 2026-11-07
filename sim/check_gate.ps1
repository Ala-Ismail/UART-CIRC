param([string]$EvidenceRoot = 'build/sim')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$evidencePath = if ([IO.Path]::IsPathRooted($EvidenceRoot)) { $EvidenceRoot } else { Join-Path $repoRoot $EvidenceRoot }
$required = @()
foreach ($depth in @(2,4,512)) { $required += "tb_fifo_-gDEPTH=$depth`_-gSEED=17" }
foreach ($width in @(3,16)) { $required += "tb_status_-gWIDTH=$width" }
foreach ($baud in @(115200,1000000,4000000)) { $required += "tb_tick_-gBAUD=$baud" }
$required += 'tb_core'
foreach ($baud in @(115200,4000000)) { $required += "tb_uart_-gBAUD=$baud`_-gSUITE=0" }
$required += 'tb_uart_-gBAUD=4000000_-gSUITE=2'
foreach ($baud in @(115200,4000000)) {
    foreach ($offset in -2..2) { $required += "tb_uart_-gBAUD=$baud`_-gSUITE=1_-gMATRIX_OFFSET=$offset" }
}
foreach ($seed in 1..10) { $required += "tb_uart_-gBAUD=4000000_-gSUITE=3_-gSEED=$seed" }
$accepted = @{}
$fingerprint = @{}
foreach ($file in Get-ChildItem -LiteralPath $evidencePath -Filter manifest.json -Recurse | Sort-Object LastWriteTime) {
    $run = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if ($run.status -ne 'PASS') { continue }
    $current = $true
    foreach ($source in $run.files) {
        $sourcePath = Join-Path $repoRoot $source.path
        if (-not (Test-Path -LiteralPath $sourcePath) -or
            (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $source.sha256) {
            $current=$false; break
        }
    }
    if (-not $current -or $run.files.Count -ne 15) { continue }
    $logs = Get-ChildItem -LiteralPath $file.DirectoryName -Filter '*.log'
    $diagnostics = $logs | Select-String -Pattern '(?i)(\*\*\s+(warning|error|fatal|failure)|\bwarning\s*:|\berror\s*:|[1-9][0-9]*\s+warnings?\b)'
    if ($diagnostics) { continue }
    foreach ($result in $run.results) {
        $logPath = Join-Path $file.DirectoryName $result.log
        $testEntity = ($result.test -split '_-g')[0]
        if ($result.status -eq 'PASS' -and (Test-Path -LiteralPath $logPath) -and
            (Select-String -LiteralPath $logPath -Pattern "PASS $testEntity\b" -Quiet)) {
            $relativeRun = $file.DirectoryName.Substring($repoRoot.Length+1).Replace('\','/')
            $accepted[$result.test]=[ordered]@{test=$result.test;status='PASS';run=$relativeRun;log=$result.log}
        }
    }
    foreach ($source in $run.files) { $fingerprint[$source.path]=$source.sha256 }
}
$missing = @($required | Where-Object { -not $accepted.ContainsKey($_) })
$gate = [ordered]@{
    timestamp=(Get-Date -Format o)
    status=$(if ($missing.Count -eq 0) {'PASS'} else {'INCOMPLETE'})
    required_tests=$required.Count; passed_tests=($required.Count-$missing.Count)
    missing_tests=$missing; files=$fingerprint
    results=@($required | Where-Object { $accepted.ContainsKey($_) } | ForEach-Object { $accepted[$_] })
}
$resultDirectory=Join-Path $PSScriptRoot 'results'
New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
$gate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $resultDirectory 'gate.json')
if ($missing.Count) { throw "Simulation gate incomplete: $($missing -join ', ')" }
Write-Host "PASS simulation gate: $($required.Count) tests, matching source hashes and clean logs. No Quartus implementation invoked."
