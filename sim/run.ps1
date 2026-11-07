param(
    [string]$ModelSimBin = 'C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem',
    [ValidateSet('All','Unit','Directed','Matrix','Stress')][string]$Suite = 'All',
    [switch]$Waves,
    [ValidateRange(-2,3)][int]$MatrixOffset = 3
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6)
$runRoot = Join-Path $repoRoot "build\sim\$runId-$Suite"
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$sources = @(
    'rtl/uart_rx_pkg.vhd','rtl/uart_rx_sync.vhd','rtl/uart_rx_tick.vhd',
    'rtl/uart_rx_core.vhd','rtl/uart_rx_fifo.vhd','rtl/uart_rx_status.vhd',
    'rtl/uart_rx_circular.vhd','sim/tb_support_pkg.vhd','sim/tb_fifo.vhd',
    'sim/tb_status.vhd','sim/tb_tick.vhd','sim/tb_core.vhd','sim/tb_uart.vhd'
)
$manifestFiles = $sources + @('sim/run.ps1','sim/run_one.do')
$hashes = foreach ($source in $manifestFiles) {
    $hash = Get-FileHash -LiteralPath (Join-Path $repoRoot $source) -Algorithm SHA256
    [ordered]@{ path=$source; sha256=$hash.Hash }
}
$revision = (& git -C $repoRoot rev-parse HEAD | Out-String).Trim()
$manifest = [ordered]@{
    timestamp=(Get-Date -Format o); revision=$revision; suite=$Suite
    clock_hz=75000000; fifo_depth=512; language='VHDL-2008'; matrix_offset=$MatrixOffset
    files=$hashes; results=@(); status='RUNNING'
}
function Save-Manifest {
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'manifest.json')
}
function Invoke-CheckedTool([string]$Tool, [string[]]$ToolArgs, [string]$LogName) {
    $exe = Join-Path $ModelSimBin "$Tool.exe"
    if (-not (Test-Path -LiteralPath $exe)) { throw "Missing tool: $exe" }
    $logPath = Join-Path $runRoot "$LogName.log"
    "COMMAND: $exe $($ToolArgs -join ' ')" | Set-Content -LiteralPath $logPath
    $output = & $exe @ToolArgs 2>&1
    $exitCode = $LASTEXITCODE
    $output | Add-Content -LiteralPath $logPath
    $bad = $output | Select-String -Pattern '(?i)(\*\*\s+(warning|error|fatal)|\bwarning\s*:|\berror\s*:|\bfatal\s*:|[1-9][0-9]*\s+warnings?\b)'
    if ($exitCode -ne 0 -or $bad) {
        $output | Select-Object -Last 35 | ForEach-Object { Write-Host $_ }
        throw "$Tool failed or reported diagnostics. See $logPath"
    }
    return ($output | Out-String)
}
Push-Location $runRoot
try {
    Save-Manifest
    $manifest.quartus_version = (& "$env:QUARTUS_ROOTDIR\bin64\quartus_sh.exe" --version | Out-String).Trim()
    $manifest.modelsim_version = (Invoke-CheckedTool 'vsim' @('-version') 'version').Trim()
    Invoke-CheckedTool 'vlib' @('work') 'vlib' | Out-Null
    foreach ($source in $sources) {
        $logName = 'compile-' + [IO.Path]::GetFileNameWithoutExtension($source)
        Invoke-CheckedTool 'vcom' @('-2008','-work','work',(Join-Path $repoRoot $source)) $logName | Out-Null
    }
    $tests = @()
    if ($Suite -in @('All','Unit')) {
        foreach ($depth in @(2,4,512)) { $tests += ,@('tb_fifo',"-gDEPTH=$depth",'-gSEED=17') }
        foreach ($width in @(3,16)) { $tests += ,@('tb_status',"-gWIDTH=$width") }
        foreach ($baud in @(115200,1000000,4000000)) { $tests += ,@('tb_tick',"-gBAUD=$baud") }
        $tests += ,@('tb_core')
    }
    if ($Suite -in @('All','Directed')) {
        foreach ($baud in @(115200,4000000)) { $tests += ,@('tb_uart',"-gBAUD=$baud",'-gSUITE=0') }
        $tests += ,@('tb_uart','-gBAUD=4000000','-gSUITE=2')
    }
    if ($Suite -in @('All','Matrix')) {
        foreach ($baud in @(115200,4000000)) {
            $offsets = if ($MatrixOffset -eq 3) { -2..2 } else { @($MatrixOffset) }
            foreach ($offset in $offsets) {
                $tests += ,@('tb_uart',"-gBAUD=$baud",'-gSUITE=1',"-gMATRIX_OFFSET=$offset")
            }
        }
    }
    if ($Suite -in @('All','Stress')) {
        foreach ($seed in 1..10) { $tests += ,@('tb_uart','-gBAUD=4000000','-gSUITE=3',"-gSEED=$seed") }
    }
    foreach ($test in $tests) {
        $testName = $test -join '_'
        $env:UART_TEST = $test[0]
        $env:UART_GENERICS = ($test | Select-Object -Skip 1) -join ' '
        $env:UART_WAVE = (Join-Path $runRoot "$testName.wlf").Replace('\','/')
        $env:UART_LOG_WAVES = if ($Waves) { '1' } else { '0' }
        Write-Host "RUN $testName"
        $output = Invoke-CheckedTool 'vsim' @('-c','-do',(Join-Path $PSScriptRoot 'run_one.do')) $testName
        if ($output -notmatch "PASS $($test[0])\b") { throw "Missing PASS marker: $testName" }
        $manifest.results += [ordered]@{test=$testName;status='PASS';log="$testName.log"}
        Save-Manifest
        Write-Host "PASS $testName"
    }
    $manifest.status='PASS'; Save-Manifest
    Write-Host "PASS suite=$Suite tests=$($tests.Count) evidence=$runRoot"
} catch {
    $manifest.status='FAIL'; $manifest.failure=$_.Exception.Message; Save-Manifest
    throw
} finally {
    Pop-Location
}
